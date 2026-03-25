extends Node
class_name PlayerWindow

# ---------------------------------------------------------------------------
# PlayerWindow — root controller for the shared Player / TV display window.
#
# Phase 2 responsibilities:
#   • Host the MapView (same scene as DM uses, but without DM UI)
#   • React to "map_loaded" packets from the DM process via PlayerMain
#   • Phase 4 will add a FoW CanvasLayer and player token spawning
#
# This node is instantiated by PlayerMain.gd, which also owns PlayerClient.
# PlayerMain connects PlayerClient.state_received → PlayerWindow.on_state().
# ---------------------------------------------------------------------------

const MapViewScene: PackedScene = preload("res://scenes/MapView.tscn")
const DEBUG_FOG_SNAPSHOT: bool = true

signal fog_snapshot_applied(payload: Dictionary)

var _map_view: MapView = null
var _tokens_by_id: Dictionary = {}
var _has_loaded_map: bool = false
var _pending_fog_snapshot: Dictionary = {}
var _pending_fog_deltas: Array = []
var _incoming_fog_snapshot_chunks: Dictionary = {}
var _bound_player_id: String = ""
var _notes_canvas: CanvasLayer = null
var _notes_panel: PanelContainer = null
var _notes_vbox: VBoxContainer = null
var _notes_font_size: int = 28
var _notes_dragging: bool = false
var _notes_drag_offset: Vector2 = Vector2.ZERO
var _notes_resizing: bool = false
var _notes_resize_origin: Vector2 = Vector2.ZERO
var _notes_resize_start_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	_map_view = MapViewScene.instantiate() as MapView
	_map_view.name = "MapView"
	add_child(_map_view)
	_map_view.allow_keyboard_pan = false
	_map_view.set_dm_view(false)
	_build_puzzle_notes_panel()
	print("PlayerWindow: ready — awaiting map from DM")


func _map() -> MapData:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.map != null:
		var m: MapData = registry.map.get_map()
		if m != null:
			return m
	if _map_view != null:
		return _map_view.get_map()
	return null


# ---------------------------------------------------------------------------
# Called by PlayerMain when a state packet arrives from the DM
# ---------------------------------------------------------------------------

func on_state(data: Dictionary) -> void:
	var msg: String = data.get("msg", "")
	match msg:
		"map_loaded":
			_handle_map_loaded(data.get("map", {}))
		"map_updated":
			_handle_map_updated(data.get("map", {}))
		"fog_state_snapshot":
			_handle_fog_state_snapshot(data)
		"fog_state_snapshot_begin":
			_handle_fog_state_snapshot_begin(data)
		"fog_state_snapshot_chunk":
			_handle_fog_state_snapshot_chunk(data)
		"fog_state_snapshot_end":
			_handle_fog_state_snapshot_end(data)
		"fog_updated":
			_handle_fog_updated(data)
		"fog_delta":
			_handle_fog_delta(data)
		"fog_brush_stroke":
			_handle_fog_brush_stroke(data)
		"fog_overlay_toggle":
			_handle_fog_overlay_toggle(data)
		"flashlights_only_toggle":
			_handle_flashlights_only_toggle(data)
		"camera_update":
			_handle_camera_update(data)
		"state", "delta":
			_handle_player_state(data)
		"token_state":
			_handle_token_state(data.get("tokens", []) as Array)
		"token_added":
			_handle_token_added(data.get("token", {}) as Dictionary)
		"token_removed":
			_handle_token_removed(str(data.get("token_id", "")))
		"token_moved":
			_handle_token_moved(str(data.get("token_id", "")), data.get("world_pos", {}) as Dictionary)
		"token_updated":
			_handle_token_added(data.get("token", {}) as Dictionary)
		"puzzle_notes_state":
			pass # Handled by the puzzle_notes catch-all below the match block
		"token_detected":
			if _map_view != null:
				_map_view.set_token_detected(str(data.get("token_id", "")), true)
		"token_undetected":
			if _map_view != null:
				_map_view.set_token_detected(str(data.get("token_id", "")), false)
		"player_bind":
			_bound_player_id = str(data.get("player_id", ""))
			print("PlayerWindow: bound to player_id=%s" % _bound_player_id)
		"measurement_state":
			_handle_measurement_state(data.get("measurements", []) as Array)
		"measurement_added":
			_handle_measurement_added(data.get("measurement", {}) as Dictionary)
		"measurement_removed":
			_handle_measurement_removed(str(data.get("measurement_id", "")))
		"measurement_moved":
			_handle_measurement_moved(data)
		"measurement_updated":
			_handle_measurement_added(data.get("measurement", {}) as Dictionary)
		_:
			pass
	# Puzzle notes piggyback on token messages (and standalone puzzle_notes_state).
	# Process them from ANY message that carries the key, so they work even if
	# the standalone message type is dropped or unrecognised.
	if data.has("puzzle_notes"):
		_handle_puzzle_notes_state(data.get("puzzle_notes", []) as Array)


# ---------------------------------------------------------------------------
# Map loading
# ---------------------------------------------------------------------------

func _handle_map_loaded(map_dict: Dictionary) -> void:
	if map_dict.is_empty():
		push_warning("PlayerWindow: received empty map dict")
		return
	var map: MapData = MapData.from_dict(map_dict)
	# Keep Map service in sync if available
	var sreg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if sreg != null and sreg.map != null:
		sreg.map.load(map)

	_map_view.load_map(map)
	# Restore player viewport rotation immediately from the map data so the
	# correct angle is visible before (or in case of late arrival of) camera_update.
	if map.camera_rotation != 0:
		var cs: Dictionary = _map_view.get_camera_state()
		_map_view.set_camera_state(
			Vector2(float(cs["position"]["x"]), float(cs["position"]["y"])),
			float(cs["zoom"]),
			map.camera_rotation)
	_has_loaded_map = true
	_apply_cached_fog_stamp()
	var map_snapshot: Variant = map_dict.get("fog_snapshot", {})
	if map_snapshot is Dictionary and not (map_snapshot as Dictionary).is_empty():
		_handle_fog_state_snapshot(map_snapshot as Dictionary)
	_apply_pending_fog_packets()
	_clear_tokens()
	_apply_token_size_from_map(map)
	# Initialise the measurement overlay scale and shapes from the map bundle.
	if _map_view != null and _map_view.measurement_overlay != null:
		var px_per_5ft: float = map.cell_px \
				if map.grid_type == MapData.GridType.SQUARE \
				else map.hex_size * 2.0
		_map_view.measurement_overlay.set_scale_px(px_per_5ft)
		_map_view.measurement_overlay.load_measurements(map.measurements)
	print("PlayerWindow: map loaded — '%s'" % map.map_name)


func _handle_map_updated(map_dict: Dictionary) -> void:
	## Apply map updates (fog/walls/grid) while preserving player camera.
	if map_dict.is_empty() or _map_view == null:
		return
	var cam_state: Dictionary = _map_view.get_camera_state()
	var map: MapData = MapData.from_dict(map_dict)
	# Inform Map service of updates when available
	var sreg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if sreg != null and sreg.map != null:
		sreg.map.update(map)

	_map_view.load_map(map)
	_has_loaded_map = true
	_apply_cached_fog_stamp()
	var map_snapshot: Variant = map_dict.get("fog_snapshot", {})
	if map_snapshot is Dictionary and not (map_snapshot as Dictionary).is_empty():
		_handle_fog_state_snapshot(map_snapshot as Dictionary)
	_apply_pending_fog_packets()
	_map_view.set_camera_state(
		Vector2(float(cam_state["position"]["x"]), float(cam_state["position"]["y"])),
		float(cam_state["zoom"]),
		int(cam_state.get("rotation", 0)))
	_apply_token_size_from_map(map)
	print("PlayerWindow: map updated (grid/scale) — '%s'" % map.map_name)


func _handle_camera_update(data: Dictionary) -> void:
	if _map_view == null:
		return
	var pos_d: Dictionary = data.get("position", {"x": 0.0, "y": 0.0})
	var pos := Vector2(float(pos_d.get("x", 0.0)), float(pos_d.get("y", 0.0)))
	var zoom := float(data.get("zoom", 1.0))
	var rotation := int(data.get("rotation", 0))
	_map_view.set_camera_state(pos, zoom, rotation)


func _handle_fog_state_snapshot(data: Dictionary) -> void:
	if not _has_loaded_map:
		_pending_fog_snapshot = data.duplicate(true)
		return
	if _map_view == null or _map() == null:
		_pending_fog_snapshot = data.duplicate(true)
		return
	var fog_state_b64 := str(data.get("fog_state_png_b64", ""))
	if fog_state_b64.is_empty():
		push_warning("PlayerWindow: fog_state_snapshot missing fog_state_png_b64")
		return

	var fog_state_png := Marshalls.base64_to_raw(fog_state_b64)
	if fog_state_png.is_empty():
		push_warning("PlayerWindow: fog_state_snapshot PNG decode returned empty buffer")
		return

	var snapshot_hash := hash(fog_state_png)
	if DEBUG_FOG_SNAPSHOT:
		print("PlayerWindow: fog snapshot recv (stamp_bytes=%d stamp_hash=%d)" % [fog_state_png.size(), snapshot_hash])

	_map_view.apply_fog_snapshot(fog_state_png)

	print("PlayerWindow: fog_state_snapshot applied (stamp_bytes=%d)" % fog_state_png.size())
	fog_snapshot_applied.emit({
		"snapshot_bytes": fog_state_png.size(),
		"snapshot_hash": snapshot_hash,
	})


func _handle_fog_state_snapshot_begin(data: Dictionary) -> void:
	var chunks := maxi(1, int(data.get("chunks", 1)))
	var parts: Array = []
	parts.resize(chunks)
	for i in range(chunks):
		parts[i] = ""
	_incoming_fog_snapshot_chunks = {
		"snapshot_hash": int(data.get("snapshot_hash", -1)),
		"snapshot_bytes": int(data.get("snapshot_bytes", -1)),
		"chunks": chunks,
		"parts": parts,
	}


func _handle_fog_state_snapshot_chunk(data: Dictionary) -> void:
	if _incoming_fog_snapshot_chunks.is_empty():
		_handle_fog_state_snapshot_begin(data)
	var expected_hash := int(_incoming_fog_snapshot_chunks.get("snapshot_hash", -1))
	var incoming_hash := int(data.get("snapshot_hash", -1))
	if expected_hash != -1 and incoming_hash != -1 and incoming_hash != expected_hash:
		return
	var parts: Array = _incoming_fog_snapshot_chunks.get("parts", []) as Array
	var index := int(data.get("index", -1))
	if index < 0 or index >= parts.size():
		return
	parts[index] = str(data.get("fog_state_png_b64_chunk", ""))
	_incoming_fog_snapshot_chunks["parts"] = parts


func _handle_fog_state_snapshot_end(data: Dictionary) -> void:
	if _incoming_fog_snapshot_chunks.is_empty():
		return
	var expected_hash := int(_incoming_fog_snapshot_chunks.get("snapshot_hash", -1))
	var incoming_hash := int(data.get("snapshot_hash", -1))
	if expected_hash != -1 and incoming_hash != -1 and incoming_hash != expected_hash:
		_incoming_fog_snapshot_chunks.clear()
		return

	var parts: Array = _incoming_fog_snapshot_chunks.get("parts", []) as Array
	var joined_b64 := ""
	for part in parts:
		var text := str(part)
		if text.is_empty():
			push_warning("PlayerWindow: fog_state_snapshot chunk missing before end")
			_incoming_fog_snapshot_chunks.clear()
			return
		joined_b64 += text

	var snapshot := {
		"msg": "fog_state_snapshot",
		"snapshot_bytes": int(data.get("snapshot_bytes", _incoming_fog_snapshot_chunks.get("snapshot_bytes", -1))),
		"snapshot_hash": int(data.get("snapshot_hash", _incoming_fog_snapshot_chunks.get("snapshot_hash", -1))),
		"fog_state_png_b64": joined_b64,
	}
	_incoming_fog_snapshot_chunks.clear()
	_handle_fog_state_snapshot(snapshot)


func _handle_fog_updated(data: Dictionary) -> void:
	if not _has_loaded_map or _map() == null:
		_pending_fog_deltas.append(data.duplicate(true))
		return
	var cell_px := int(data.get("fog_cell_px", 32))
	var hidden_cells := data.get("hidden_cells", []) as Array
	_map_view.apply_fog_state(cell_px, hidden_cells)


func _handle_fog_delta(data: Dictionary) -> void:
	if not _has_loaded_map or _map() == null:
		_pending_fog_deltas.append(data.duplicate(true))
		return
	var cell_px := int(data.get("fog_cell_px", 32))
	var revealed := data.get("revealed_cells", []) as Array
	var hidden := data.get("hidden_cells", []) as Array
	_map_view.apply_fog_delta(cell_px, revealed, hidden)


func _handle_fog_brush_stroke(data: Dictionary) -> void:
	if _map_view == null:
		return
	_map_view.apply_fog_brush_stroke(data)


func _handle_fog_overlay_toggle(data: Dictionary) -> void:
	if _map_view == null:
		return
	_map_view.set_fog_overlay_enabled(bool(data.get("enabled", false)))


func _handle_flashlights_only_toggle(data: Dictionary) -> void:
	if _map_view == null:
		return
	_map_view.set_flashlights_only(bool(data.get("enabled", false)))


func _apply_cached_fog_stamp() -> void:
	if _map_view == null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.fog == null:
		return
	var cached := registry.fog.get_fog_state()
	if cached.is_empty():
		return
	_map_view.apply_fog_snapshot(cached)


func _handle_player_state(data: Dictionary) -> void:
	if _map_view == null:
		return
	var players_raw: Variant = data.get("players", [])
	if not players_raw is Array:
		return
	var active_ids: Dictionary = {}
	for entry in players_raw:
		if not entry is Dictionary:
			continue
		var item := entry as Dictionary
		var player_id := str(item.get("id", ""))
		if player_id.is_empty():
			continue
		active_ids[player_id] = true
		var token: PlayerSprite = _ensure_token(player_id)
		if token != null:
			token.apply_from_state(item)

	for existing_id in _tokens_by_id.keys():
		if active_ids.has(existing_id):
			continue
		var stale = _tokens_by_id[existing_id]
		if is_instance_valid(stale):
			stale.queue_free()
		_tokens_by_id.erase(existing_id)


func _ensure_token(player_id: String) -> PlayerSprite:
	if _tokens_by_id.has(player_id):
		var existing: PlayerSprite = _tokens_by_id[player_id] as PlayerSprite
		if is_instance_valid(existing):
			return existing
		_tokens_by_id.erase(player_id)
	var scene: PackedScene = load("res://scenes/PlayerSprite.tscn") as PackedScene
	var token: PlayerSprite = scene.instantiate() as PlayerSprite if scene else null
	if token == null:
		return null
	token.name = "PlayerToken_%s" % player_id.left(8)
	token.enable_remote_smoothing(true)
	var token_layer: Node2D = _map_view.get_token_layer()
	token_layer.add_child(token)
	_tokens_by_id[player_id] = token
	return token


func _clear_tokens() -> void:
	for id in _tokens_by_id.keys():
		var token = _tokens_by_id[id]
		if is_instance_valid(token):
			token.queue_free()
	_tokens_by_id.clear()


func _apply_token_size_from_map(map: MapData) -> void:
	var token_diameter_px := map.cell_px if map.grid_type == MapData.GridType.SQUARE else map.hex_size * 2.0
	for id in _tokens_by_id.keys():
		var token: PlayerSprite = _tokens_by_id[id] as PlayerSprite
		if not is_instance_valid(token):
			continue
		token.set_token_diameter_px(token_diameter_px)


func _apply_pending_fog_packets() -> void:
	if _map_view == null:
		return
	if _map() == null:
		return
	if not _pending_fog_snapshot.is_empty():
		var snapshot_packet := _pending_fog_snapshot
		_pending_fog_snapshot = {}
		_handle_fog_state_snapshot(snapshot_packet)
	if not _pending_fog_deltas.is_empty():
		var queued := _pending_fog_deltas.duplicate(true)
		_pending_fog_deltas.clear()
		for packet in queued:
			if not packet is Dictionary:
				continue
			var msg := str((packet as Dictionary).get("msg", ""))
			if msg == "fog_updated":
				_handle_fog_updated(packet as Dictionary)
			elif msg == "fog_delta":
				_handle_fog_delta(packet as Dictionary)


# ---------------------------------------------------------------------------
# Token message handlers (player receive side)
# ---------------------------------------------------------------------------

func _handle_token_state(token_dicts: Array) -> void:
	## Replace all DM-placed tokens in MapView with the current visible snapshot.
	if _map_view == null:
		return
	_map_view.load_token_sprites(token_dicts, false)
	# Seed passthrough rects for any doors/portals already open in the snapshot.
	for raw in token_dicts:
		if raw is Dictionary:
			var td: TokenData = TokenData.from_dict(raw as Dictionary)
			_map_view.apply_token_passthrough_state(td)


func _handle_token_added(token_dict: Dictionary) -> void:
	if _map_view == null or token_dict.is_empty():
		return
	var data: TokenData = TokenData.from_dict(token_dict)
	_map_view.add_token_sprite(data, false)
	_map_view.apply_token_passthrough_state(data)


func _handle_token_removed(id: String) -> void:
	if _map_view == null or id.is_empty():
		return
	_map_view.remove_token_sprite(id)
	_map_view.clear_token_passthrough(id)


func _handle_token_moved(id: String, pos_dict: Dictionary) -> void:
	if _map_view == null or id.is_empty():
		return
	var new_pos := Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))
	var token_layer: Node2D = _map_view.get_token_layer()
	if token_layer == null:
		return
	var matched_sprite: TokenSprite = null
	for child in token_layer.get_children():
		var ts: TokenSprite = child as TokenSprite
		if ts != null and ts.token_id == id:
			ts.global_position = new_pos
			matched_sprite = ts
			break
	# Rebuild door wall / passthrough rect at the new position.
	if matched_sprite != null:
		var td := TokenData.new()
		td.id = id
		td.world_pos = new_pos
		td.category = matched_sprite.get_token_category()
		td.width_px = matched_sprite.get_token_width_px()
		td.height_px = matched_sprite.get_token_height_px()
		td.blocks_los = matched_sprite.get_token_blocks_los()
		_map_view.apply_token_passthrough_state(td)


# ---------------------------------------------------------------------------
# Puzzle notes panel (player display overlay)
# ---------------------------------------------------------------------------

func _build_puzzle_notes_panel() -> void:
	_notes_canvas = CanvasLayer.new()
	_notes_canvas.layer = 100
	add_child(_notes_canvas)

	_notes_panel = PanelContainer.new()
	_notes_panel.visible = false
	_notes_panel.custom_minimum_size = Vector2(360, 200)
	_notes_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_notes_panel.add_theme_stylebox_override("panel", style)
	_notes_canvas.add_child(_notes_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_notes_panel.add_child(outer)

	# Drag-handle / title bar.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_notes_header_gui_input)
	outer.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "Puzzle Notes"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title_lbl)

	var size_down := Button.new()
	size_down.text = "A-"
	size_down.custom_minimum_size = Vector2(44, 0)
	size_down.pressed.connect(_on_notes_font_size_change.bind(-4))
	header.add_child(size_down)

	var size_up := Button.new()
	size_up.text = "A+"
	size_up.custom_minimum_size = Vector2(44, 0)
	size_up.pressed.connect(_on_notes_font_size_change.bind(4))
	header.add_child(size_up)

	var close_btn := Button.new()
	close_btn.text = "\u2715"
	close_btn.custom_minimum_size = Vector2(36, 0)
	close_btn.pressed.connect(func() -> void: _notes_panel.hide())
	header.add_child(close_btn)

	# Scrollable note list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_notes_vbox = VBoxContainer.new()
	_notes_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(_notes_vbox)

	# Resize grip in the bottom-right corner.
	var grip := Label.new()
	grip.text = "\u2921" # ⤡ diagonal arrow
	grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grip.add_theme_font_size_override("font_size", 18)
	grip.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 0.6))
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.gui_input.connect(_on_notes_resize_gui_input)
	outer.add_child(grip)


func _handle_puzzle_notes_state(notes: Array) -> void:
	if _notes_panel == null or _notes_vbox == null:
		return
	# Remove old children immediately (not queue_free) so child count is accurate.
	for child in _notes_vbox.get_children():
		_notes_vbox.remove_child(child)
		child.queue_free()
	if notes.is_empty():
		_notes_panel.hide()
		return
	for raw: Variant in notes:
		if not raw is Dictionary:
			continue
		var d := raw as Dictionary
		var label_text: String = str(d.get("label", ""))
		var note_text: String = str(d.get("text", ""))
		if note_text.is_empty():
			continue
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 4)
		if not label_text.is_empty():
			var src_lbl := Label.new()
			src_lbl.text = label_text
			src_lbl.add_theme_font_size_override("font_size", maxi(16, _notes_font_size - 6))
			src_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 0.8))
			entry.add_child(src_lbl)
		var note_lbl := RichTextLabel.new()
		note_lbl.bbcode_enabled = false
		note_lbl.fit_content = true
		note_lbl.scroll_active = false
		note_lbl.text = note_text
		note_lbl.add_theme_font_size_override("normal_font_size", _notes_font_size)
		note_lbl.add_theme_color_override("default_color", Color.WHITE)
		entry.add_child(note_lbl)
		_notes_vbox.add_child(entry)
	if _notes_vbox.get_child_count() > 0:
		# Position near top-right of the viewport on first show.
		if not _notes_panel.visible:
			var vp_size := get_viewport().get_visible_rect().size
			_notes_panel.position = Vector2(maxf(0.0, vp_size.x - 440.0), 24.0)
		_notes_panel.show()
	else:
		_notes_panel.hide()


func _on_notes_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_notes_dragging = mb.pressed
			if mb.pressed:
				_notes_drag_offset = _notes_panel.position - mb.global_position
	elif event is InputEventMouseMotion and _notes_dragging:
		_notes_panel.position = (event as InputEventMouseMotion).global_position + _notes_drag_offset


func _on_notes_resize_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_notes_resizing = mb.pressed
			if mb.pressed:
				_notes_resize_origin = mb.global_position
				_notes_resize_start_size = _notes_panel.size
	elif event is InputEventMouseMotion and _notes_resizing:
		var delta := (event as InputEventMouseMotion).global_position - _notes_resize_origin
		var new_size := _notes_resize_start_size + delta
		_notes_panel.size = Vector2(
			maxf(new_size.x, _notes_panel.custom_minimum_size.x),
			maxf(new_size.y, _notes_panel.custom_minimum_size.y)
		)


func _on_notes_font_size_change(delta: int) -> void:
	_notes_font_size = clampi(_notes_font_size + delta, 14, 72)
	# Re-apply font sizes to existing labels.
	if _notes_vbox == null:
		return
	for child in _notes_vbox.get_children():
		var entry: VBoxContainer = child as VBoxContainer
		if entry == null:
			continue
		for sub in entry.get_children():
			if sub is RichTextLabel:
				(sub as RichTextLabel).add_theme_font_size_override("normal_font_size", _notes_font_size)
			elif sub is Label:
				(sub as Label).add_theme_font_size_override("font_size", maxi(16, _notes_font_size - 6))


# ---------------------------------------------------------------------------
# Measurement message handlers (player receive side)
# ---------------------------------------------------------------------------

func _handle_measurement_state(dicts: Array) -> void:
	if _map_view == null or _map_view.measurement_overlay == null:
		return
	_map_view.measurement_overlay.load_measurements(dicts)


func _handle_measurement_added(d: Dictionary) -> void:
	if _map_view == null or _map_view.measurement_overlay == null or d.is_empty():
		return
	var md: MeasurementData = MeasurementData.from_dict(d)
	_map_view.measurement_overlay.add_or_update(md)


func _handle_measurement_removed(id: String) -> void:
	if _map_view == null or _map_view.measurement_overlay == null or id.is_empty():
		return
	_map_view.measurement_overlay.remove_shape(id)


func _handle_measurement_moved(data: Dictionary) -> void:
	if _map_view == null or _map_view.measurement_overlay == null:
		return
	var id: String = str(data.get("measurement_id", ""))
	if id.is_empty():
		return
	var ws: Dictionary = data.get("world_start", {"x": 0.0, "y": 0.0}) as Dictionary
	var we: Dictionary = data.get("world_end", {"x": 0.0, "y": 0.0}) as Dictionary
	var overlay: MeasurementOverlay = _map_view.measurement_overlay
	var existing_md: MeasurementData = overlay._measurements.get(id, null) as MeasurementData
	if existing_md != null:
		existing_md.world_start = Vector2(float(ws.get("x", 0.0)), float(ws.get("y", 0.0)))
		existing_md.world_end = Vector2(float(we.get("x", 0.0)), float(we.get("y", 0.0)))
		overlay.add_or_update(existing_md)
