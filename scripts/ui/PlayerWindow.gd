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


func _ready() -> void:
	_map_view = MapViewScene.instantiate() as MapView
	_map_view.name = "MapView"
	add_child(_map_view)
	_map_view.allow_keyboard_pan = false
	_map_view.set_dm_view(false)
	print("PlayerWindow: ready — awaiting map from DM")


func _map() -> MapData:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.map != null and registry.map.service != null:
		var m: MapData = registry.map.service.get_map() as MapData
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
		_:
			pass


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


func _apply_cached_fog_stamp() -> void:
	if _map_view == null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.fog == null or registry.fog.service == null:
		return
	var cached := registry.fog.service.get_fog_state()
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
