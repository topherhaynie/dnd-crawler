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
var _passage_paths: Array = []
var _passage_width_px: float = 48.0


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
	# Load icon assets at runtime — gracefully skips any that haven't been imported yet.
	for icon_key: String in ["door", "door2", "trap", "tunnel"]:
		var tex: Texture2D = load("res://assets/%s.png" % icon_key) as Texture2D
		if tex != null:
			_icon_key_map[icon_key] = tex


func _draw() -> void:
	var rx: float = _width_px * 0.5
	var ry: float = _height_px * 0.5
	var inner_r: float = minf(rx, ry)
	var fill_color: Color = CATEGORY_COLORS.get(_category, Color.GRAY)
	var seg: int = 40

	if _category == TokenData.TokenCategory.SECRET_PASSAGE and _passage_paths.size() > 0:
		_draw_passage_corridors()
		return

	if _shape == 1: # RECTANGLE
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
		# Label is only rendered on the DM side.
		_label_node.visible = is_dm
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
	_refresh_visibility()
	queue_redraw()


## Returns the larger of width/height for broad hit-test compatibility.
func get_token_diameter_px() -> float:
	return maxf(_width_px, _height_px)


func get_token_width_px() -> float:
	return _width_px


func get_token_height_px() -> float:
	return _height_px


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
