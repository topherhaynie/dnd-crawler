extends Node

# ---------------------------------------------------------------------------
# BackendRuntime — authoritative gameplay backend for the DM host process.
#
# Responsibilities:
#   - Spawn/sync player tokens in the shared MapView token layer
#   - Resolve input vectors from InputManager (multi-source arbitration)
#   - Advance authoritative player movement and wall collision
#   - Build state packets consumed by Player windows
#
# DMWindow owns UI and map editing; this backend owns simulation/state.
# ---------------------------------------------------------------------------

const PlayerSpriteScene: PackedScene = preload("res://scenes/PlayerSprite.tscn")
const NORMAL_VISION_HALF_ANGLE_RAD: float = 0.9599311 ## 55 degrees
const ENABLE_AUTOMATIC_FOG_REVEAL: bool = false

var _map_view: Node2D = null
var _dm_tokens: Dictionary = {}
var _spawn_initialized: bool = false
var _force_los_reveal: bool = true
var _cached_wall_edges: Array = []
var _cached_wall_signature: String = ""
var _los_prev_origin_by_token: Dictionary = {}


func _game_state() -> Node:
	return get_node("/root/GameState")


func _input_manager() -> Node:
	return get_node("/root/InputManager")


func configure(map_view: Node2D) -> void:
	_map_view = map_view


func reset_for_new_map() -> void:
	_spawn_initialized = false
	_force_los_reveal = true
	_los_prev_origin_by_token.clear()
	_rebuild_cached_wall_edges(_map_view.get_map() if _map_view else null)
	sync_profiles()
	_ensure_spawn_positions()


func sync_profiles() -> void:
	if _map_view == null:
		return
	var active: Dictionary = {}
	for profile in _game_state().profiles:
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		active[p.id] = true
		_ensure_token(p)
	for id in _dm_tokens.keys():
		if active.has(id):
			continue
		var stale = _dm_tokens[id]
		if stale is Node:
			_los_prev_origin_by_token.erase((stale as Node).get_instance_id())
		if is_instance_valid(stale):
			stale.queue_free()
		_dm_tokens.erase(id)


func step(delta: float) -> bool:
	if _map_view == null:
		return false
	var map: MapData = _map_view.get_map() if _map_view else null
	if map == null:
		return false

	sync_profiles()
	_ensure_spawn_positions()

	var moved := false
	var max_bounds := Vector2.ZERO
	if _map_view.map_image and _map_view.map_image.texture:
		max_bounds = _map_view.map_image.texture.get_size()

	for profile in _game_state().profiles:
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		var token: Node2D = _ensure_token(p)
		if token == null:
			continue
		if token.has_method("set_token_diameter_px"):
			token.set_token_diameter_px(_token_diameter_px_for_map(map))
		var vec: Vector2 = _input_manager().get_vector(p.id)
		token.set_movement_input(vec)
		var prev_pos: Vector2 = token.global_position
		token.step_authoritative_motion(delta, _profile_speed_px_per_second(p, map), max_bounds)
		token.global_position = _resolve_wall_collision(prev_pos, token.global_position, map)
		var pos: Vector2 = token.global_position
		if _game_state().player_positions.get(p.id, Vector2.ZERO) != pos:
			_game_state().player_positions[p.id] = pos
			moved = true
	return moved


func _step_fog_authority(_delta: float, map: MapData) -> void:
	if not ENABLE_AUTOMATIC_FOG_REVEAL:
		return
	if map == null:
		return
	var wall_sig := _wall_signature(map)
	if wall_sig != _cached_wall_signature:
		_rebuild_cached_wall_edges(map)
	if map.fog_hidden_cells.is_empty():
		return

	var revealed_candidates := _reveal_fog_from_tokens_los(map)
	if revealed_candidates.is_empty():
		return
	var hidden_dict := _hidden_cells_dict_from_array(map.fog_hidden_cells)
	var applied_revealed: Array = []
	for cell in revealed_candidates:
		if not cell is Vector2i:
			continue
		if not hidden_dict.has(cell):
			continue
		hidden_dict.erase(cell)
		applied_revealed.append(cell)
	if applied_revealed.is_empty():
		return
	map.fog_hidden_cells = _hidden_cells_array(hidden_dict)

	if _map_view and _map_view.has_method("apply_fog_delta"):
		_map_view.apply_fog_delta(map.fog_cell_px, applied_revealed, [])
	# MapView.apply_fog_delta already emits fog deltas through the DM pipeline.
	# Avoid duplicate backend emissions that can amplify websocket traffic.


func _reveal_fog_from_tokens_los(map: MapData) -> Array:
	var hidden: Dictionary = _hidden_cells_dict_from_array(map.fog_hidden_cells)
	if hidden.is_empty() or _dm_tokens.is_empty():
		return []

	var revealed: Array = []
	var cell_px: int = maxi(1, map.fog_cell_px)
	var px_per_5ft := map.cell_px if map.grid_type == MapData.GridType.SQUARE else map.hex_size * 2.0

	for token_entry in _dm_tokens.values():
		if not token_entry is Node2D:
			continue
		var token := token_entry as Node2D
		if not is_instance_valid(token):
			continue

		var vision_type := int(token.get("vision_type")) if token.get("vision_type") != null else 0
		var darkvision_range := float(token.get("darkvision_range")) if token.get("darkvision_range") != null else 60.0
		var radius_feet := darkvision_range if vision_type == 1 else 30.0
		var radius_px := (radius_feet / 5.0) * px_per_5ft
		if bool(token.get("is_dashing")):
			radius_px *= 0.5
		radius_px = maxf(radius_px, 16.0)

		var origin: Vector2 = token.global_position
		var facing_dir := Vector2.RIGHT.rotated(token.rotation)
		var token_key := token.get_instance_id()
		var prev_origin := _los_prev_origin_by_token.get(token_key, origin) as Vector2
		var travel := prev_origin.distance_to(origin)
		# Fewer stamps than cursor brush dragging: backend reveal should stay smooth
		# under many entities and tiny fog cells.
		var stamp_spacing := clampf(radius_px * 0.4, 24.0, 128.0)
		var samples := maxi(1, int(ceil(travel / stamp_spacing)))
		for i in range(samples + 1):
			var t := float(i) / float(samples)
			var stamp_origin := prev_origin.lerp(origin, t)
			_stamp_reveal_from_origin(hidden, revealed, stamp_origin, facing_dir, vision_type, radius_px, cell_px)

		_los_prev_origin_by_token[token_key] = origin

	return revealed


func _hidden_cells_dict_from_array(raw_cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for cell in raw_cells:
		if cell is Vector2i:
			out[cell] = true
		elif cell is Array and (cell as Array).size() >= 2:
			var arr := cell as Array
			out[Vector2i(int(arr[0]), int(arr[1]))] = true
		elif cell is Dictionary:
			out[Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0)))] = true
	return out


func _hidden_cells_array(hidden_dict: Dictionary) -> Array:
	var out: Array = []
	for key in hidden_dict.keys():
		if key is Vector2i:
			out.append(key)
	return out


func _is_cell_in_vision_cone(origin: Vector2, facing_dir: Vector2, vision_type: int, radius_px: float, cell_center: Vector2) -> bool:
	var to_cell := cell_center - origin
	if to_cell.length() > radius_px:
		return false
	if vision_type == 0 and to_cell.length_squared() > 0.001:
		var angle_delta := absf(facing_dir.angle_to(to_cell.normalized()))
		if angle_delta > NORMAL_VISION_HALF_ANGLE_RAD:
			return false
	return true


func _stamp_reveal_from_origin(hidden: Dictionary, revealed: Array, origin: Vector2, facing_dir: Vector2, vision_type: int, radius_px: float, cell_px: int) -> void:
	var radius_cells := int(ceil(radius_px / float(cell_px)))
	var center := Vector2i(floori(origin.x / cell_px), floori(origin.y / cell_px))
	var sample_step := _auto_reveal_sample_step(radius_cells)
	for y in range(center.y - radius_cells, center.y + radius_cells + 1, sample_step):
		for x in range(center.x - radius_cells, center.x + radius_cells + 1, sample_step):
			var sample_cell := Vector2i(x, y)
			var sample_center := Vector2((x + 0.5) * cell_px, (y + 0.5) * cell_px)
			if not _is_cell_in_vision_cone(origin, facing_dir, vision_type, radius_px, sample_center):
				continue
			# Reveal a small block per sample to approximate dense brush fill
			# with significantly less per-frame cell testing.
			for by in range(sample_step):
				for bx in range(sample_step):
					var cell := Vector2i(sample_cell.x + bx, sample_cell.y + by)
					if not hidden.has(cell):
						continue
					var cell_center := Vector2((cell.x + 0.5) * cell_px, (cell.y + 0.5) * cell_px)
					if not _is_cell_in_vision_cone(origin, facing_dir, vision_type, radius_px, cell_center):
						continue
					hidden.erase(cell)
					revealed.append(cell)


func _auto_reveal_sample_step(radius_cells: int) -> int:
	if radius_cells >= 72:
		return 4
	if radius_cells >= 40:
		return 3
	if radius_cells >= 20:
		return 2
	return 1


func _is_los_blocked(origin: Vector2, target: Vector2, _map: MapData) -> bool:
	var seg_len := origin.distance_to(target)
	if seg_len <= 0.001:
		return false
	for edge in _cached_wall_edges:
		if not edge is Array:
			continue
		var pair := edge as Array
		if pair.size() < 2:
			continue
		var av: Variant = pair[0]
		var bv: Variant = pair[1]
		if not av is Vector2 or not bv is Vector2:
			continue
		var a := av as Vector2
		var b := bv as Vector2
		var hit: Variant = Geometry2D.segment_intersects_segment(origin, target, a, b)
		if not hit is Vector2:
			continue
		var hp := hit as Vector2
		var d := origin.distance_to(hp)
		if d > 1.0 and d < (seg_len - 1.0):
			return true
	return false


func _wall_signature(map: MapData) -> String:
	if map == null:
		return ""
	var poly_count := map.wall_polygons.size()
	var point_count := 0
	for poly in map.wall_polygons:
		if poly is Array:
			point_count += (poly as Array).size()
	return "%d:%d" % [poly_count, point_count]


func _rebuild_cached_wall_edges(map: MapData) -> void:
	_cached_wall_edges.clear()
	_cached_wall_signature = _wall_signature(map)
	if map == null:
		return
	for poly in map.wall_polygons:
		if not poly is Array:
			continue
		var pts := poly as Array
		if pts.size() < 2:
			continue
		for i in range(pts.size()):
			var av: Variant = pts[i]
			var bv: Variant = pts[(i + 1) % pts.size()]
			if av is Vector2 and bv is Vector2:
				_cached_wall_edges.append([av, bv])


func build_player_state_payload() -> Array:
	var players: Array = []
	if _map_view == null:
		return players
	var map: MapData = _map_view.get_map() if _map_view else null
	var token_diameter_px := _token_diameter_px_for_map(map) if map else 48.0
	for profile in _game_state().profiles:
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		var token: Node2D = _dm_tokens.get(p.id, null) as Node2D
		if token and is_instance_valid(token):
			_game_state().player_positions[p.id] = token.global_position
		var pos: Vector2 = _game_state().player_positions.get(p.id, Vector2.ZERO)
		players.append({
			"id": p.id,
			"name": p.player_name,
			"base_speed": p.base_speed,
			"vision_type": p.vision_type,
			"darkvision_range": p.darkvision_range,
			"perception_mod": p.perception_mod,
			"is_dashing": bool(p.extras.get("is_dashing", false)),
			"vision_scale": _vision_scale_for_profile(p),
			"token_diameter_px": token_diameter_px,
			"facing": token.rotation if token and is_instance_valid(token) else 0.0,
			"position": {"x": pos.x, "y": pos.y},
		})
	return players


func _ensure_spawn_positions() -> void:
	if _spawn_initialized or _map_view == null:
		return
	var map: MapData = _map_view.get_map()
	if map == null:
		return
	var map_size: Vector2 = _map_view.map_image.texture.get_size() if _map_view.map_image and _map_view.map_image.texture else Vector2(1920, 1080)
	var origin: Vector2 = map_size * 0.5
	var idx := 0
	for profile in _game_state().profiles:
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		var current: Vector2 = _game_state().player_positions.get(p.id, Vector2.ZERO)
		if current == Vector2.ZERO:
			_game_state().player_positions[p.id] = origin + Vector2((idx % 4) * 40.0, floor(float(idx) / 4.0) * 40.0)
		_ensure_token(p)
		var token: Node2D = _dm_tokens.get(p.id, null) as Node2D
		if token and is_instance_valid(token):
			token.global_position = _game_state().player_positions[p.id]
		idx += 1
	_spawn_initialized = true


func _ensure_token(profile: PlayerProfile) -> Node2D:
	if _dm_tokens.has(profile.id):
		var existing = _dm_tokens[profile.id]
		if is_instance_valid(existing):
			existing.apply_from_state({
				"id": profile.id,
				"name": profile.player_name,
				"base_speed": profile.base_speed,
				"vision_type": profile.vision_type,
				"darkvision_range": profile.darkvision_range,
				"perception_mod": profile.perception_mod,
				"is_dashing": bool(profile.extras.get("is_dashing", false)),
				"vision_scale": _vision_scale_for_profile(profile),
				"position": {
					"x": _game_state().player_positions.get(profile.id, Vector2.ZERO).x,
					"y": _game_state().player_positions.get(profile.id, Vector2.ZERO).y,
				},
			})
			return existing
		_dm_tokens.erase(profile.id)

	if _map_view == null or PlayerSpriteScene == null:
		return null
	var token: Node2D = PlayerSpriteScene.instantiate() as Node2D
	if token == null:
		return null
	token.name = "DMToken_%s" % profile.id.left(8)
	_map_view.get_token_layer().add_child(token)
	token.apply_from_state({
		"id": profile.id,
		"name": profile.player_name,
		"base_speed": profile.base_speed,
		"vision_type": profile.vision_type,
		"darkvision_range": profile.darkvision_range,
		"perception_mod": profile.perception_mod,
		"is_dashing": bool(profile.extras.get("is_dashing", false)),
		"vision_scale": _vision_scale_for_profile(profile),
		"position": {
			"x": _game_state().player_positions.get(profile.id, Vector2.ZERO).x,
			"y": _game_state().player_positions.get(profile.id, Vector2.ZERO).y,
		},
	})
	_dm_tokens[profile.id] = token
	return token


func _profile_speed_px_per_second(profile: PlayerProfile, map: MapData) -> float:
	var px_per_5ft := map.cell_px if map.grid_type == MapData.GridType.SQUARE else map.hex_size * 2.0
	var speed := (maxf(profile.base_speed, 5.0) / 5.0) * px_per_5ft
	if bool(profile.extras.get("is_dashing", false)):
		speed *= 1.5
	return speed


func _vision_scale_for_profile(profile: PlayerProfile) -> float:
	var dash := bool(profile.extras.get("is_dashing", false))
	var scale := 0.5 if dash else 1.0
	var fog_manager := get_node_or_null("/root/FogManager")
	if fog_manager and fog_manager.has_method("compute_dash_vision_scale"):
		scale = float(fog_manager.compute_dash_vision_scale(dash))
	if fog_manager and fog_manager.has_method("set_vision_scale"):
		return float(fog_manager.set_vision_scale(profile.id, scale))
	return clampf(scale, 0.1, 4.0)


func _token_diameter_px_for_map(map: MapData) -> float:
	return map.cell_px if map.grid_type == MapData.GridType.SQUARE else map.hex_size * 2.0


func _resolve_wall_collision(prev_pos: Vector2, next_pos: Vector2, map: MapData) -> Vector2:
	if map.wall_polygons.is_empty():
		return next_pos
	if not _point_inside_any_wall(next_pos, map) and not _segment_hits_any_wall(prev_pos, next_pos, map):
		return next_pos

	var hit_info := _first_wall_hit(prev_pos, next_pos, map)
	if hit_info.is_empty():
		return prev_pos

	var hit_point := hit_info["point"] as Vector2
	var edge_a := hit_info["a"] as Vector2
	var edge_b := hit_info["b"] as Vector2
	var move_vec := next_pos - prev_pos
	if move_vec.length_squared() <= 0.000001:
		return prev_pos

	var edge_dir := (edge_b - edge_a).normalized()
	if edge_dir.length_squared() <= 0.000001:
		return prev_pos

	var remaining := next_pos - hit_point
	var slide_vec := edge_dir * remaining.dot(edge_dir)
	if slide_vec.length_squared() <= 0.000001:
		return prev_pos

	var slide_start := hit_point - move_vec.normalized() * 1.0
	var slide_target := slide_start + slide_vec
	if _point_inside_any_wall(slide_target, map):
		return slide_start
	if _segment_hits_any_wall(slide_start, slide_target, map):
		return slide_start
	return slide_target


func _point_inside_any_wall(pos: Vector2, map: MapData) -> bool:
	for poly in map.wall_polygons:
		if not poly is Array:
			continue
		var points := PackedVector2Array()
		for p in poly:
			if p is Vector2:
				points.append(p)
		if points.size() < 3:
			continue
		if Geometry2D.is_point_in_polygon(pos, points):
			return true
	return false


func _segment_hits_any_wall(a: Vector2, b: Vector2, map: MapData) -> bool:
	var seg_len := a.distance_to(b)
	if seg_len <= 0.001:
		return false
	for poly in map.wall_polygons:
		if not poly is Array:
			continue
		var pts := poly as Array
		if pts.size() < 2:
			continue
		for i in range(pts.size()):
			var av: Variant = pts[i]
			var bv: Variant = pts[(i + 1) % pts.size()]
			if not av is Vector2 or not bv is Vector2:
				continue
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, av as Vector2, bv as Vector2)
			if not hit is Vector2:
				continue
			var d := a.distance_to(hit as Vector2)
			if d > 0.5 and d < (seg_len - 0.5):
				return true
	return false


func _first_wall_hit(a: Vector2, b: Vector2, map: MapData) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var seg_len := a.distance_to(b)
	if seg_len <= 0.001:
		return best
	for poly in map.wall_polygons:
		if not poly is Array:
			continue
		var pts := poly as Array
		if pts.size() < 2:
			continue
		for i in range(pts.size()):
			var av: Variant = pts[i]
			var bv: Variant = pts[(i + 1) % pts.size()]
			if not av is Vector2 or not bv is Vector2:
				continue
			var pa := av as Vector2
			var pb := bv as Vector2
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, pa, pb)
			if not hit is Vector2:
				continue
			var hp := hit as Vector2
			var d := a.distance_to(hp)
			if d <= 0.5 or d >= (seg_len - 0.5):
				continue
			if d < best_d:
				best_d = d
				best = {"point": hp, "a": pa, "b": pb}
	return best
