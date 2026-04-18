extends Node2D
class_name TokenSprite

# ---------------------------------------------------------------------------
# TokenSprite — lightweight renderer for a single DM-placed token.
#
# Placed as a child of MapView's token_layer Node2D.
# The DM sees all tokens; hidden tokens appear at reduced alpha with a
# "hidden" modulation tint.  Player-side views hide tokens whose
# is_visible_to_players == false entirely.
#
# Children expected in the scene (or created procedurally if absent):
#   _icon   — ColorRect or Sprite2D (placeholder circle drawn via _draw)
#   _label  — Label (DM-only name overlay)
# ---------------------------------------------------------------------------

## Default diameter (world-space px) — matches the TokenData default.
const TOKEN_DIAMETER_PX: float = 48.0

## Alpha for tokens that are hidden from players (DM view only).
const HIDDEN_ALPHA: float = 0.45

## Category int → default icon_key for categories that have a bundled asset.
## Tokens whose icon_key field is non-empty override this default.
const CATEGORY_DEFAULT_ICON_KEYS: Dictionary = {
	0: "door", # DOOR
	1: "trap", # TRAP
	3: "tunnel", # SECRET_PASSAGE
}

## Category → distinct fill colour.
const CATEGORY_COLORS: Dictionary = {
	0: Color(0.65, 0.43, 0.18, 1.0), # DOOR           — warm wood-brown
	1: Color(0.95, 0.48, 0.04, 1.0), # TRAP           — warning orange
	2: Color(0.22, 0.55, 0.92, 1.0), # HIDDEN_OBJECT  — sky blue
	3: Color(0.55, 0.10, 0.82, 1.0), # SECRET_PASSAGE — deep violet
	4: Color(0.85, 0.07, 0.12, 1.0), # MONSTER        — blood red
	5: Color(0.05, 0.72, 0.38, 1.0), # EVENT          — emerald green
	6: Color(0.95, 0.78, 0.06, 1.0), # NPC            — gold
	7: Color(0.48, 0.48, 0.50, 1.0), # GENERIC        — neutral grey
}

## Category → single uppercase letter drawn in the token centre.
const CATEGORY_SYMBOLS: Dictionary = {
	0: "D", # DOOR
	1: "T", # TRAP
	2: "H", # HIDDEN_OBJECT
	3: "S", # SECRET_PASSAGE
	4: "M", # MONSTER
	5: "E", # EVENT
	6: "N", # NPC
	7: "G", # GENERIC
}

var token_id: String = ""

var _category: int = 0
var _blocks_los: bool = true
var _is_dm: bool = false
var _is_visible_to_players: bool = false
var _width_px: float = TOKEN_DIAMETER_PX
var _height_px: float = TOKEN_DIAMETER_PX
var _shape: int = 0 ## 0 = ELLIPSE, 1 = RECTANGLE (mirrors TokenData.TokenShape)
var _label_node: Label = null
var _icon_texture: Texture2D = null
var _icon_key_map: Dictionary = {}
var _show_handles: bool = false
var _is_selected: bool = false
var _passage_paths: Array = []
var _passage_width_px: float = 48.0
var _roam_path: PackedVector2Array = PackedVector2Array()
var _roam_loop: bool = true
var _is_detected: bool = false
var _is_active_turn: bool = false
var _trigger_radius_px: float = 96.0
## Custom icon image texture (circular-masked) — set from local file or network.
var _custom_icon_texture: ImageTexture = null
## Absolute path to the custom icon image file (for lazy loading via shared cache).
var _icon_image_path: String = ""

## HP bar state — set externally via set_hp_bar().
var _hp_current: int = -1 ## -1 = no HP bar
var _hp_max: int = 0
var _hp_temp: int = 0

## Active conditions — Array of condition name strings for badge drawing.
var _conditions: Array = []

## Statblock visibility level for player display ("none"/"name"/"partial"/"full").
var _statblock_visibility: String = "none"
## Resolved statblock display info from the DM (see TokenData.statblock_display).
var _statblock_display: Dictionary = {}
## Secondary label for stat info (AC / HP) shown on player display.
var _stat_label_node: Label = null

# Remote position interpolation (player display smoothing).
var _remote_smoothing: bool = false
var _remote_target: Vector2 = Vector2.ZERO
var _remote_initialized: bool = false
const _REMOTE_LERP_SPEED: float = 24.0
const _REMOTE_SNAP_EPSILON: float = 0.75
const _REMOTE_TELEPORT_DIST: float = 200.0


func _process(delta: float) -> void:
	if not _remote_smoothing:
		return
	var dist: float = global_position.distance_to(_remote_target)
	if dist <= _REMOTE_SNAP_EPSILON:
		global_position = _remote_target
		return
	if dist > _REMOTE_TELEPORT_DIST:
		global_position = _remote_target
		return
	global_position = global_position.lerp(_remote_target, clampf(delta * _REMOTE_LERP_SPEED, 0.0, 1.0))


func _ready() -> void:
	_label_node = Label.new()
	_label_node.name = "TokenLabel"
	_label_node.add_theme_font_size_override("font_size", 11)
	_label_node.add_theme_color_override("font_color", Color.WHITE)
	_label_node.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_label_node.add_theme_constant_override("shadow_offset_x", 1)
	_label_node.add_theme_constant_override("shadow_offset_y", 1)
	_label_node.position = Vector2(-_width_px * 0.5, _height_px * 0.5 + 2.0)
	add_child(_label_node)
	# Secondary stat info label for player display (AC / type).
	_stat_label_node = Label.new()
	_stat_label_node.name = "StatLabel"
	_stat_label_node.add_theme_font_size_override("font_size", 10)
	_stat_label_node.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	_stat_label_node.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_stat_label_node.add_theme_constant_override("shadow_offset_x", 1)
	_stat_label_node.add_theme_constant_override("shadow_offset_y", 1)
	_stat_label_node.position = Vector2(-_width_px * 0.5, _height_px * 0.5 + 16.0)
	_stat_label_node.visible = false
	add_child(_stat_label_node)
	# Load icon assets at runtime — gracefully skips any that haven't been imported yet.
	for icon_key: String in ["door", "door2", "trap", "tunnel"]:
		var tex: Texture2D = load("res://assets/%s.png" % icon_key) as Texture2D
		if tex != null:
			_icon_key_map[icon_key] = tex


func _draw() -> void:
	# Roam path drawn first so the token renders on top.
	if _is_dm and _roam_path.size() >= 2:
		_draw_roam_path()

	var rx: float = _width_px * 0.5
	var ry: float = _height_px * 0.5
	var inner_r: float = minf(rx, ry)
	var fill_color: Color = CATEGORY_COLORS.get(_category, Color.GRAY)
	var seg: int = 40

	# Lazy-load custom icon texture on first draw.
	if _custom_icon_texture == null and not _icon_image_path.is_empty():
		_custom_icon_texture = TokenIconUtils.get_or_load_circular_texture(_icon_image_path)

	if _category == TokenData.TokenCategory.SECRET_PASSAGE and _passage_paths.size() > 0:
		_draw_passage_corridors()
		return

	if _shape == 1: # RECTANGLE
		# Custom icon image fills the entire rect (already circular-masked).
		if _custom_icon_texture != null:
			draw_texture_rect(
				_custom_icon_texture,
				Rect2(-rx, -ry, _width_px, _height_px),
				false
			)
		else:
			draw_rect(Rect2(-rx, -ry, _width_px, _height_px), fill_color)
			# Icon or letter symbol.
			if _icon_texture != null:
				var icon_size: float = inner_r * 2.0 * 0.85
				draw_texture_rect(
					_icon_texture,
					Rect2(-icon_size * 0.5, -icon_size * 0.5, icon_size, icon_size),
					false
				)
			else:
				var sym_size: int = maxi(8, int(inner_r * 0.7))
				var sym: String = CATEGORY_SYMBOLS.get(_category, "G")
				draw_string(
					ThemeDB.fallback_font,
					Vector2(-inner_r, sym_size * 0.38),
					sym,
					HORIZONTAL_ALIGNMENT_CENTER,
					int(inner_r * 2.0),
					sym_size,
					Color(1.0, 1.0, 1.0, 0.9)
				)
		# Rectangle border.
		draw_rect(Rect2(-rx, -ry, _width_px, _height_px), Color(0.0, 0.0, 0.0, 0.6), false, 2.0)
		# Hidden badge: top-right corner (DM view only).
		if _is_dm and not _is_visible_to_players:
			var badge_r: float = maxf(6.0, inner_r * 0.22)
			var badge_pos := Vector2(rx - badge_r * 0.7, -ry + badge_r * 0.7)
			draw_circle(badge_pos, badge_r, Color(0.0, 0.0, 0.0, 0.82))
			var b_size: int = maxi(7, int(badge_r * 1.3))
			draw_string(
				ThemeDB.fallback_font,
				Vector2(badge_pos.x - badge_r, badge_pos.y + b_size * 0.38),
				"?",
				HORIZONTAL_ALIGNMENT_CENTER,
				int(badge_r * 2.0),
				b_size,
				Color(1.0, 0.92, 0.1, 1.0)
			)
		# Selection highlight (filled glow + ring).
		if _is_selected:
			var sel_pad: float = 4.0
			var sr := Rect2(- (rx + sel_pad), - (ry + sel_pad), _width_px + sel_pad * 2.0, _height_px + sel_pad * 2.0)
			draw_rect(sr, Color(0.2, 0.55, 1.0, 0.18), true)
			draw_rect(sr, Color(0.2, 0.55, 1.0, 0.9), false, 3.0)
		# Active-turn highlight (gold glow + ring outside selection ring).
		if _is_active_turn:
			var act_pad: float = 9.0
			var ar := Rect2(- (rx + act_pad), - (ry + act_pad), _width_px + act_pad * 2.0, _height_px + act_pad * 2.0)
			draw_rect(ar, Color(1.0, 0.85, 0.1, 0.15), true)
			draw_rect(ar, Color(1.0, 0.85, 0.1, 0.95), false, 4.0)
		# Resize and rotation handles (DM hover only).
		if _show_handles and _is_dm:
			# Rect ring outside the token boundary.
			draw_rect(Rect2(- (rx + 5.0), - (ry + 5.0), _width_px + 10.0, _height_px + 10.0), Color(1.0, 1.0, 1.0, 0.85), false, 1.5)
			# 8 bounding-box handle squares (TL T TR  R  BR B BL  L).
			var sq: float = maxf(5.0, inner_r * 0.09)
			var handle_positions: Array = [
				Vector2(-rx, -ry), Vector2(0.0, -ry), Vector2(rx, -ry),
				Vector2(rx, 0.0), Vector2(rx, ry), Vector2(0.0, ry),
				Vector2(-rx, ry), Vector2(-rx, 0.0),
			]
			for hp: Vector2 in handle_positions:
				draw_rect(Rect2(hp.x - sq * 0.5, hp.y - sq * 0.5, sq, sq), Color(1.0, 1.0, 1.0, 0.9))
			# Rotation handle: circle 22 px above top bounding edge.
			var rot_y: float = - ry - 22.0
			draw_line(Vector2(0.0, -ry), Vector2(0.0, rot_y), Color(1.0, 1.0, 1.0, 0.7), 1.5)
			draw_circle(Vector2(0.0, rot_y), 5.0, Color(1.0, 1.0, 0.3, 0.9))
	else: # ELLIPSE (default)
		# Custom icon image fills the ellipse bounding box (already circular-masked).
		if _custom_icon_texture != null:
			draw_texture_rect(
				_custom_icon_texture,
				Rect2(-rx, -ry, _width_px, _height_px),
				false
			)
		else:
			# Ellipse fill via scaled draw context.
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(rx, ry))
			draw_circle(Vector2.ZERO, 1.0, fill_color)
			draw_set_transform(Vector2.ZERO)
			# Icon or letter symbol.
			if _icon_texture != null:
				var icon_size: float = inner_r * 2.0 * 0.85
				draw_texture_rect(
					_icon_texture,
					Rect2(-icon_size * 0.5, -icon_size * 0.5, icon_size, icon_size),
					false
				)
			else:
				var sym_size: int = maxi(8, int(inner_r * 0.7))
				var sym: String = CATEGORY_SYMBOLS.get(_category, "G")
				draw_string(
					ThemeDB.fallback_font,
					Vector2(-inner_r, sym_size * 0.38),
					sym,
					HORIZONTAL_ALIGNMENT_CENTER,
					int(inner_r * 2.0),
					sym_size,
					Color(1.0, 1.0, 1.0, 0.9)
				)
		# Ellipse border.
		var border_pts := PackedVector2Array()
		for i: int in seg:
			var a: float = TAU * float(i) / float(seg)
			border_pts.append(Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(border_pts + PackedVector2Array([border_pts[0]]), Color(0.0, 0.0, 0.0, 0.6), 2.0)
		# Hidden badge: top-right corner (DM view only).
		if _is_dm and not _is_visible_to_players:
			var badge_r: float = maxf(6.0, inner_r * 0.22)
			var badge_pos := Vector2(rx - badge_r * 0.7, -ry + badge_r * 0.7)
			draw_circle(badge_pos, badge_r, Color(0.0, 0.0, 0.0, 0.82))
			var b_size: int = maxi(7, int(badge_r * 1.3))
			draw_string(
				ThemeDB.fallback_font,
				Vector2(badge_pos.x - badge_r, badge_pos.y + b_size * 0.38),
				"?",
				HORIZONTAL_ALIGNMENT_CENTER,
				int(badge_r * 2.0),
				b_size,
				Color(1.0, 0.92, 0.1, 1.0)
			)
		# Selection highlight (filled glow + ring).
		if _is_selected:
			var sel_pad: float = 4.0
			var sel_rx: float = rx + sel_pad
			var sel_ry: float = ry + sel_pad
			# Filled glow.
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(sel_rx, sel_ry))
			draw_circle(Vector2.ZERO, 1.0, Color(0.2, 0.55, 1.0, 0.18))
			draw_set_transform(Vector2.ZERO)
			# Ring.
			var sel_pts := PackedVector2Array()
			for i: int in seg:
				var a: float = TAU * float(i) / float(seg)
				sel_pts.append(Vector2(cos(a) * sel_rx, sin(a) * sel_ry))
			draw_polyline(sel_pts + PackedVector2Array([sel_pts[0]]), Color(0.2, 0.55, 1.0, 0.9), 3.0)
		# Active-turn highlight (gold glow + ring outside selection ring).
		if _is_active_turn:
			var act_pad: float = 9.0
			var act_rx: float = rx + act_pad
			var act_ry: float = ry + act_pad
			# Filled glow.
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(act_rx, act_ry))
			draw_circle(Vector2.ZERO, 1.0, Color(1.0, 0.85, 0.1, 0.15))
			draw_set_transform(Vector2.ZERO)
			# Ring.
			var act_pts := PackedVector2Array()
			for i: int in seg:
				var a: float = TAU * float(i) / float(seg)
				act_pts.append(Vector2(cos(a) * act_rx, sin(a) * act_ry))
			draw_polyline(act_pts + PackedVector2Array([act_pts[0]]), Color(1.0, 0.85, 0.1, 0.95), 4.0)
		# Resize and rotation handles (DM hover only).
		if _show_handles and _is_dm:
			# Ellipse ring outside the token boundary.
			var ring_rx: float = rx + 5.0
			var ring_ry: float = ry + 5.0
			var ring_pts := PackedVector2Array()
			for i: int in seg:
				var a: float = TAU * float(i) / float(seg)
				ring_pts.append(Vector2(cos(a) * ring_rx, sin(a) * ring_ry))
			draw_polyline(ring_pts + PackedVector2Array([ring_pts[0]]), Color(1.0, 1.0, 1.0, 0.85), 1.5)
			# 8 bounding-box handle squares (TL T TR  R  BR B BL  L).
			var sq: float = maxf(5.0, inner_r * 0.09)
			var handle_positions: Array = [
				Vector2(-rx, -ry), Vector2(0.0, -ry), Vector2(rx, -ry),
				Vector2(rx, 0.0), Vector2(rx, ry), Vector2(0.0, ry),
				Vector2(-rx, ry), Vector2(-rx, 0.0),
			]
			for hp: Vector2 in handle_positions:
				draw_rect(Rect2(hp.x - sq * 0.5, hp.y - sq * 0.5, sq, sq), Color(1.0, 1.0, 1.0, 0.9))
			# Rotation handle: circle 22 px above top bounding edge.
			var rot_y: float = - ry - 22.0
			draw_line(Vector2(0.0, -ry), Vector2(0.0, rot_y), Color(1.0, 1.0, 1.0, 0.7), 1.5)
			draw_circle(Vector2(0.0, rot_y), 5.0, Color(1.0, 1.0, 0.3, 0.9))
	# Trigger-radius dashed circle + drag handle (DM view, handles shown).
	if _show_handles and _is_dm and _trigger_radius_px > 0.0:
		var dash_segs: int = 48
		var dash_color := Color(0.4, 0.85, 1.0, 0.55)
		for i: int in dash_segs:
			if i % 2 == 1:
				continue
			var a0: float = TAU * float(i) / float(dash_segs)
			var a1: float = TAU * float(i + 1) / float(dash_segs)
			draw_line(
				Vector2(cos(a0) * _trigger_radius_px, sin(a0) * _trigger_radius_px),
				Vector2(cos(a1) * _trigger_radius_px, sin(a1) * _trigger_radius_px),
				dash_color, 1.5)
		# Drag handle at rightmost point.
		var handle_pos := Vector2(_trigger_radius_px, 0.0)
		draw_circle(handle_pos, 6.0, Color(0.4, 0.85, 1.0, 0.9))
		draw_circle(handle_pos, 6.0, Color.WHITE, false, 1.5)

	# Detection badge: yellow "!" shown on player displays when token is
	# sensed but not yet revealed (perception < DC while within range).
	if _is_detected and not _is_visible_to_players:
		var det_size: int = maxi(14, int(minf(_width_px, _height_px) * 0.5))
		draw_string(
			ThemeDB.fallback_font,
			Vector2(-float(det_size) * 0.3, float(det_size) * 0.4),
			"!",
			HORIZONTAL_ALIGNMENT_CENTER,
			det_size,
			det_size,
			Color(1.0, 0.92, 0.1, 1.0)
		)

	# HP bar — drawn below token when statblock is attached.
	if _hp_current >= 0 and _hp_max > 0:
		_draw_hp_bar()
		# Bloodied indicator — red tint when at ≤ 50% HP.
		if _hp_current > 0 and float(_hp_current) <= float(_hp_max) * 0.5:
			_draw_bloodied_indicator()

	# Condition badges — drawn below HP bar when conditions are active.
	if not _conditions.is_empty():
		_draw_condition_badges()


func set_detected(detected: bool) -> void:
	if _is_detected == detected:
		return
	_is_detected = detected
	queue_redraw()


## Update the HP bar display.  Pass current_hp = -1 to hide the bar.
func set_hp_bar(current_hp: int, max_hp: int, temp_hp: int = 0) -> void:
	if _hp_current == current_hp and _hp_max == max_hp and _hp_temp == temp_hp:
		return
	_hp_current = current_hp
	_hp_max = max_hp
	_hp_temp = temp_hp
	queue_redraw()


## Update the condition badge list. Pass an empty array to clear all badges.
func set_conditions(conds: Array) -> void:
	if _conditions == conds:
		return
	_conditions = conds.duplicate()
	queue_redraw()


## Update the secondary stat label shown beneath the token on the player display.
func _update_stat_label() -> void:
	if _stat_label_node == null:
		return
	if _is_dm or _statblock_visibility == "none" or _statblock_display.is_empty():
		_stat_label_node.visible = false
		return
	var parts: PackedStringArray = PackedStringArray()
	if _statblock_visibility == "name":
		# Name-only: show creature type/size if available.
		var ctype: String = str(_statblock_display.get("creature_type", ""))
		var csize: String = str(_statblock_display.get("size", ""))
		if not csize.is_empty() and not ctype.is_empty():
			parts.append("%s %s" % [csize, ctype])
		elif not ctype.is_empty():
			parts.append(ctype)
	elif _statblock_visibility == "partial" or _statblock_visibility == "full":
		var ac_val: int = int(_statblock_display.get("ac", 0))
		if ac_val > 0:
			parts.append("AC %d" % ac_val)
		var cr_val: Variant = _statblock_display.get("cr", null)
		if cr_val != null:
			var cr_f: float = float(cr_val)
			if cr_f > 0.0:
				if cr_f < 1.0:
					if absf(cr_f - 0.125) < 0.01:
						parts.append("CR 1/8")
					elif absf(cr_f - 0.25) < 0.01:
						parts.append("CR 1/4")
					elif absf(cr_f - 0.5) < 0.01:
						parts.append("CR 1/2")
					else:
						parts.append("CR %s" % str(cr_f))
				else:
					parts.append("CR %d" % int(cr_f))
	if parts.is_empty():
		_stat_label_node.visible = false
		return
	_stat_label_node.text = " | ".join(parts)
	_stat_label_node.position = Vector2(-_width_px * 0.5, _height_px * 0.5 + 16.0)
	_stat_label_node.visible = true


## Enable remote position smoothing and set the interpolation target.
func set_remote_target(pos: Vector2) -> void:
	_remote_target = pos
	if not _remote_smoothing:
		_remote_smoothing = true
	if not _remote_initialized:
		_remote_initialized = true
		global_position = pos


## Apply all fields from a TokenData instance.
func apply_from_data(data: TokenData, is_dm: bool) -> void:
	token_id = data.id
	_category = data.category
	_blocks_los = data.blocks_los
	_is_dm = is_dm
	_is_visible_to_players = data.is_visible_to_players
	_width_px = maxf(24.0, data.width_px)
	_height_px = maxf(24.0, data.height_px)
	rotation_degrees = data.rotation_deg
	global_position = data.world_pos
	if _label_node != null:
		_label_node.text = data.label
		# Label is rendered on DM side, or on player side when statblock is shared.
		var show_label: bool = is_dm or data.statblock_visibility != "none"
		_label_node.visible = show_label
		_label_node.position = Vector2(-_width_px * 0.5, _height_px * 0.5 + 2.0)
	# Resolve icon texture: explicit icon_key > category default > letter fallback.
	var icon_key: String = data.icon_key
	if icon_key.is_empty():
		var default_key: Variant = CATEGORY_DEFAULT_ICON_KEYS.get(_category, "")
		icon_key = str(default_key)
	var tex_val: Variant = _icon_key_map.get(icon_key, null)
	_icon_texture = tex_val as Texture2D
	_shape = data.token_shape
	_passage_paths = data.passage_paths.duplicate()
	_passage_width_px = data.passage_width_px
	_roam_path = data.roam_path.duplicate()
	_roam_loop = data.roam_loop
	_trigger_radius_px = maxf(0.0, data.trigger_radius_px)
	# Custom icon image — store path for lazy loading; clear stale texture.
	var new_icon_path: String = data.icon_image_path
	if new_icon_path != _icon_image_path:
		_icon_image_path = new_icon_path
		_custom_icon_texture = null # Will be lazy-loaded on next _draw()
	# HP bar — read first statblock override's current/max HP.
	_hp_current = -1
	_hp_max = 0
	_hp_temp = 0
	if data.statblock_refs.size() > 0:
		var first_ref: String = str(data.statblock_refs[0])
		var ovr: Variant = data.statblock_overrides.get(first_ref, null)
		if ovr is Dictionary:
			var so: StatblockOverride = StatblockOverride.from_dict(ovr as Dictionary)
			if so.max_hp > 0:
				_hp_current = so.current_hp
				_hp_max = so.max_hp
				_hp_temp = so.temp_hp
	# Statblock visibility for player display.
	_statblock_visibility = data.statblock_visibility
	_statblock_display = data.statblock_display
	_update_stat_label()
	_refresh_visibility()
	queue_redraw()


## Returns the larger of width/height for broad hit-test compatibility.
func get_token_diameter_px() -> float:
	return maxf(_width_px, _height_px)


func get_token_width_px() -> float:
	return _width_px


func get_token_height_px() -> float:
	return _height_px


func get_trigger_radius_px() -> float:
	return _trigger_radius_px


func set_trigger_radius_px(radius: float) -> void:
	_trigger_radius_px = maxf(0.0, radius)
	queue_redraw()


## Set a pre-built circular icon texture (used by the player display for
## network-received icons where the file path is not available locally).
func set_custom_icon_texture(tex: ImageTexture) -> void:
	_custom_icon_texture = tex
	queue_redraw()


func get_token_category() -> int:
	return _category


func get_token_blocks_los() -> bool:
	return _blocks_los


## Show or hide the resize handle ring (called by MapView on DM hover).
func set_show_handles(enabled: bool) -> void:
	if _show_handles == enabled:
		return
	_show_handles = enabled
	queue_redraw()


## Mark this token as selected (blue highlight ring).
func set_selected(sel: bool) -> void:
	if _is_selected == sel:
		return
	_is_selected = sel
	queue_redraw()


## Mark this token as the active combat turn (gold highlight ring).
func set_active_turn(active: bool) -> void:
	if _is_active_turn == active:
		return
	_is_active_turn = active
	queue_redraw()


## Live-update size during a resize drag before the service is committed.
func set_size_px(new_w: float, new_h: float) -> void:
	_width_px = clampf(new_w, 24.0, 1024.0)
	_height_px = clampf(new_h, 24.0, 1024.0)
	if _label_node != null:
		_label_node.position = Vector2(-_width_px * 0.5, _height_px * 0.5 + 2.0)
	queue_redraw()


## Set rotation in degrees (live update during rotation drag).
func set_rotation_deg(deg: float) -> void:
	rotation_degrees = deg
	queue_redraw()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _draw_hp_bar() -> void:
	var bar_w: float = _width_px * 0.9
	var bar_h: float = clampf(_height_px * 0.08, 3.0, 6.0)
	var bar_x: float = - bar_w * 0.5
	var bar_y: float = _height_px * 0.5 + 3.0
	# Background
	draw_rect(Rect2(bar_x - 1.0, bar_y - 1.0, bar_w + 2.0, bar_h + 2.0), Color(0.0, 0.0, 0.0, 0.7))
	# HP fill
	var ratio: float = clampf(float(_hp_current) / float(_hp_max), 0.0, 1.0)
	var hp_color: Color
	if ratio > 0.5:
		hp_color = Color(0.2, 0.8, 0.2, 0.9).lerp(Color(0.95, 0.85, 0.1, 0.9), 1.0 - (ratio - 0.5) * 2.0)
	else:
		hp_color = Color(0.95, 0.85, 0.1, 0.9).lerp(Color(0.9, 0.15, 0.1, 0.9), 1.0 - ratio * 2.0)
	if ratio > 0.0:
		draw_rect(Rect2(bar_x, bar_y, bar_w * ratio, bar_h), hp_color)
	# Temp HP segment (blue, appended after current HP)
	if _hp_temp > 0:
		var temp_ratio: float = clampf(float(_hp_temp) / float(_hp_max), 0.0, 1.0 - ratio)
		if temp_ratio > 0.0:
			draw_rect(Rect2(bar_x + bar_w * ratio, bar_y, bar_w * temp_ratio, bar_h), Color(0.3, 0.6, 1.0, 0.9))


func _draw_bloodied_indicator() -> void:
	## Subtle red border pulsing effect for bloodied (≤ 50% HP) tokens.
	var half_w: float = _width_px * 0.5
	var half_h: float = _height_px * 0.5
	var bloodied_color := Color(0.85, 0.1, 0.1, 0.5)
	if _shape == 0: # ELLIPSE
		draw_arc(Vector2.ZERO, maxf(half_w, half_h) + 1.0, 0.0, TAU, 48,
			bloodied_color, 2.0)
	else: # RECTANGLE
		draw_rect(Rect2(-half_w - 1.0, -half_h - 1.0, _width_px + 2.0, _height_px + 2.0),
			bloodied_color, false, 2.0)


func _draw_condition_badges() -> void:
	## Draw small coloured pill badges (abbreviation + background) below the token.
	## Positioned below the HP bar if present, otherwise directly below the token.
	var bar_h: float = clampf(_height_px * 0.08, 3.0, 6.0)
	var hp_bar_total: float = 0.0
	if _hp_current >= 0 and _hp_max > 0:
		# HP bar sits at _height_px * 0.5 + 3.0; include its height + gap.
		hp_bar_total = bar_h + 3.0
	var pill_h: float = clampf(_height_px * 0.14, 8.0, 12.0)
	var pill_font_size: int = maxi(7, int(pill_h * 0.75))
	var pill_pad_x: float = 3.0
	var pill_gap: float = 2.0
	# Measure total width of all pills to center them under the token.
	var pill_widths: Array = []
	for raw: Variant in _conditions:
		var cname: String = raw if raw is String else str(raw)
		var abbrev: String = ConditionRules.get_abbrev(cname)
		# Approximate char width: font_size * 0.6 per char.
		var text_w: float = float(abbrev.length()) * float(pill_font_size) * 0.62
		pill_widths.append(text_w + pill_pad_x * 2.0)
	var total_w: float = 0.0
	for pw: Variant in pill_widths:
		total_w += float(pw)
	total_w += pill_gap * float(maxi(0, _conditions.size() - 1))
	var origin_y: float = _height_px * 0.5 + 3.0 + hp_bar_total + 2.0
	var origin_x: float = - total_w * 0.5
	for idx: int in range(_conditions.size()):
		var raw: Variant = _conditions[idx]
		var cname: String = raw if raw is String else str(raw)
		var abbrev: String = ConditionRules.get_abbrev(cname)
		var col: Color = ConditionRules.get_color(cname)
		var pw: float = float(pill_widths[idx])
		draw_rect(Rect2(origin_x, origin_y, pw, pill_h), Color(0.0, 0.0, 0.0, 0.55))
		draw_rect(Rect2(origin_x + 0.5, origin_y + 0.5, pw - 1.0, pill_h - 1.0), col)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(origin_x + pill_pad_x, origin_y + pill_h * 0.5 + float(pill_font_size) * 0.36),
			abbrev,
			HORIZONTAL_ALIGNMENT_LEFT,
			int(pw - pill_pad_x),
			pill_font_size,
			Color.WHITE
		)
		origin_x += pw + pill_gap


func _refresh_visibility() -> void:
	if _is_dm:
		# DM always sees the token; hidden ones are desaturated/transparent.
		self.visible = true
		self.modulate = Color(1.0, 1.0, 1.0, HIDDEN_ALPHA if not _is_visible_to_players else 1.0)
	else:
		# Player only sees tokens explicitly the DM has revealed.
		self.visible = _is_visible_to_players
		self.modulate = Color.WHITE


## Draw the passage corridor when this is a SECRET_PASSAGE token with path data.
## Points in passage_paths are world-space; to_local() converts them for draw_*.
func _draw_passage_corridors() -> void:
	var fill_color: Color = CATEGORY_COLORS.get(_category, Color.GRAY)
	var junction_map: Dictionary = _classify_passage_endpoints()
	var half_w: float = _passage_width_px

	# Pre-convert all chains to local space once.
	var local_chains: Array[PackedVector2Array] = []
	for raw: Variant in _passage_paths:
		if not (raw is PackedVector2Array) or (raw as PackedVector2Array).size() < 2:
			local_chains.append(PackedVector2Array())
			continue
		var lp := PackedVector2Array()
		for v: Vector2 in (raw as PackedVector2Array):
			lp.append(to_local(v))
		local_chains.append(lp)

	# Two-pass rendering: all borders first so fills always cover junction artifacts.
	# Border and fill circles at each chain's endpoints simulate the round caps
	# that Line2D draws during WIP editing, so the committed result matches.
	for lp: PackedVector2Array in local_chains:
		if lp.size() < 2:
			continue
		draw_circle(lp[0], half_w + 2.0, Color(0.0, 0.0, 0.0, 0.55))
		draw_circle(lp[lp.size() - 1], half_w + 2.0, Color(0.0, 0.0, 0.0, 0.55))
		draw_polyline(lp, Color(0.0, 0.0, 0.0, 0.55), half_w * 2.0 + 4.0, false)
	for lp: PackedVector2Array in local_chains:
		if lp.size() < 2:
			continue
		draw_circle(lp[0], half_w, fill_color)
		draw_circle(lp[lp.size() - 1], half_w, fill_color)
		draw_polyline(lp, fill_color, half_w * 2.0, true)

	# Draw endpoint markers: tunnel icon at terminals, connector dot at junctions.
	var drawn_endpoints: Dictionary = {}
	for raw: Variant in _passage_paths:
		if not raw is PackedVector2Array:
			continue
		var chain: PackedVector2Array = raw as PackedVector2Array
		if chain.size() < 1:
			continue
		var endpoints: PackedVector2Array = PackedVector2Array([chain[0], chain[chain.size() - 1]])
		for pt: Vector2 in endpoints:
			var pt_key: Vector2 = pt.snapped(Vector2.ONE * 0.01)
			if drawn_endpoints.has(pt_key):
				continue
			drawn_endpoints[pt_key] = true
			var degree: Variant = junction_map.get(pt_key, 1)
			var local_pt: Vector2 = to_local(pt)
			if int(degree) > 1:
				# Junction: filled dot with border.
				draw_circle(local_pt, half_w * 0.45, Color(0.0, 0.0, 0.0, 0.7))
				draw_circle(local_pt, half_w * 0.32, fill_color)
			else:
				# Terminal: tunnel icon or crosshatch marker.
				if _icon_texture != null:
					var icon_s: float = half_w * 1.6
					draw_texture_rect(
						_icon_texture,
						Rect2(local_pt.x - icon_s * 0.5, local_pt.y - icon_s * 0.5, icon_s, icon_s),
						false
					)
				else:
					draw_circle(local_pt, half_w * 0.45, Color(0.0, 0.0, 0.0, 0.7))
					draw_circle(local_pt, half_w * 0.32, fill_color)
					# Cross-hair to distinguish terminals from junctions.
					var arm: float = half_w * 0.28
					draw_line(local_pt + Vector2(-arm, 0.0), local_pt + Vector2(arm, 0.0),
						Color(1.0, 1.0, 1.0, 0.85), 2.0)
					draw_line(local_pt + Vector2(0.0, -arm), local_pt + Vector2(0.0, arm),
						Color(1.0, 1.0, 1.0, 0.85), 2.0)

	# DM anchor handle: always-visible marker at local origin so the token can be
	# clicked after corridors have replaced the ellipse visual.  Displayed on the
	# DM side only; players never see this indicator.
	if _is_dm:
		var anchor_r: float = maxf(10.0, half_w * 0.22)
		draw_circle(Vector2.ZERO, anchor_r + 2.0, Color(0.0, 0.0, 0.0, 0.55))
		draw_circle(Vector2.ZERO, anchor_r, fill_color.lightened(0.25))
		var arm: float = anchor_r * 0.55
		draw_line(Vector2(-arm, 0.0), Vector2(arm, 0.0), Color(1.0, 1.0, 1.0, 0.9), 1.5)
		draw_line(Vector2(0.0, -arm), Vector2(0.0, arm), Color(1.0, 1.0, 1.0, 0.9), 1.5)

	# Hidden badge at local origin (DM view only).
	if _is_dm and not _is_visible_to_players:
		var badge_r: float = 9.0
		var badge_pos := Vector2(half_w * 0.3, -half_w * 0.3)
		draw_circle(badge_pos, badge_r, Color(0.0, 0.0, 0.0, 0.82))
		var b_size: int = 9
		draw_string(
			ThemeDB.fallback_font,
			Vector2(badge_pos.x - badge_r, badge_pos.y + b_size * 0.38),
			"?", HORIZONTAL_ALIGNMENT_CENTER,
			int(badge_r * 2.0), b_size, Color(1.0, 0.92, 0.1, 1.0)
		)


## Counts passage endpoint degrees so the renderer can distinguish terminals
## (degree 1) from junctions (degree >= 2).  Keys are snapped Vector2 positions.
func _classify_passage_endpoints() -> Dictionary:
	var result: Dictionary = {}
	for raw: Variant in _passage_paths:
		if not raw is PackedVector2Array:
			continue
		var chain: PackedVector2Array = raw as PackedVector2Array
		if chain.size() < 1:
			continue
		for pt: Vector2 in [chain[0], chain[chain.size() - 1]]:
			var key: Vector2 = pt.snapped(Vector2.ONE * 0.01)
			result[key] = int(result.get(key, 0)) + 1
	return result


## Draw the roam path overlay — DM view only.
## Points are in world-space; to_local() converts them for draw_*.
func _draw_roam_path() -> void:
	const PATH_COLOR: Color = Color(0.2, 0.8, 0.9, 0.6)
	const BORDER_COLOR: Color = Color(0.0, 0.0, 0.0, 0.35)
	const LINE_WIDTH: float = 3.0
	const DOT_RADIUS: float = 5.0
	const ARROW_SIZE: float = 7.0

	# Convert to local space
	var local_pts := PackedVector2Array()
	for v: Vector2 in _roam_path:
		local_pts.append(to_local(v))

	# Build draw path — optionally close for loops
	var draw_pts: PackedVector2Array = local_pts.duplicate()
	if _roam_loop and draw_pts.size() >= 2:
		draw_pts.append(draw_pts[0])

	# Border
	draw_polyline(draw_pts, BORDER_COLOR, LINE_WIDTH + 2.0, true)
	# Fill
	draw_polyline(draw_pts, PATH_COLOR, LINE_WIDTH, true)

	# Direction arrows at segment midpoints
	for i: int in range(draw_pts.size() - 1):
		var a: Vector2 = draw_pts[i]
		var b: Vector2 = draw_pts[i + 1]
		var seg_len: float = a.distance_to(b)
		if seg_len < 20.0:
			continue
		var mid: Vector2 = (a + b) * 0.5
		var dir: Vector2 = (b - a).normalized()
		var perp: Vector2 = dir.rotated(PI * 0.5)
		var tip: Vector2 = mid + dir * ARROW_SIZE
		var left_pt: Vector2 = mid - dir * ARROW_SIZE * 0.5 + perp * ARROW_SIZE * 0.5
		var right_pt: Vector2 = mid - dir * ARROW_SIZE * 0.5 - perp * ARROW_SIZE * 0.5
		draw_colored_polygon(PackedVector2Array([tip, left_pt, right_pt]), PATH_COLOR)

	# Waypoint dots
	for pt: Vector2 in local_pts:
		draw_circle(pt, DOT_RADIUS + 1.0, BORDER_COLOR)
		draw_circle(pt, DOT_RADIUS, PATH_COLOR)
