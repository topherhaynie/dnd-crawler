extends Node
class_name BackendRuntime

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
const NORMAL_VISION_RANGE_FEET: float = 30.0
const ENABLE_AUTOMATIC_FOG_REVEAL: bool = false

var _map_view: MapView = null
var _dm_tokens: Dictionary = {}
var _spawn_initialized: bool = false
var _force_los_reveal: bool = true
var _cached_wall_edges: Array = []
var _cached_passthrough_version: int = -1
var _walls_dirty: bool = true
var _los_prev_origin_by_token: Dictionary = {}
var _dragging_token_ids: Dictionary = {}


func _game_state() -> GameStateManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.game_state == null:
		return null
	return registry.game_state


func _input_manager() -> InputManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.input == null:
		return null
	return registry.input


func _map() -> MapData:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.map != null and registry.map.model != null:
		return registry.map.model
	if _map_view != null:
		return _map_view.get_map()
	return null


func configure(map_view: MapView) -> void:
	_map_view = map_view


func _active_profiles() -> Array:
	## Returns only the profiles active in the current session.
	## With no session loaded this returns empty — no tokens on a fresh map.
	var gs := _game_state()
	if gs == null:
		return []
	var out: Array = []
	for raw in gs.list_profiles():
		if raw is PlayerProfile and gs.is_profile_active((raw as PlayerProfile).id):
			out.append(raw)
	return out


func reset_for_new_map() -> void:
	_spawn_initialized = false
	_force_los_reveal = true
	_los_prev_origin_by_token.clear()
	_rebuild_cached_wall_edges(_map())
	sync_profiles()
	_ensure_spawn_positions()


func sync_profiles() -> void:
	if _map_view == null:
		return
	var active: Dictionary = {}
	for profile in _active_profiles():
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


func mark_walls_dirty() -> void:
	_walls_dirty = true


func step(delta: float) -> bool:
	if _map_view == null:
		return false
	var map: MapData = _map()
	if map == null:
		return false
	var pt_ver: int = _map_view.get_passthrough_version() if _map_view != null else 0
	if _walls_dirty or pt_ver != _cached_passthrough_version:
		_rebuild_cached_wall_edges(map)
		_walls_dirty = false
	_ensure_spawn_positions()

	var moved := false
	var max_bounds := Vector2.ZERO
	if _map_view.map_image and _map_view.map_image.texture:
		max_bounds = _map_view.map_image.texture.get_size()

	for profile in _active_profiles():
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		var token: PlayerSprite = _dm_tokens.get(p.id, null) as PlayerSprite
		if token == null or not is_instance_valid(token):
			token = _ensure_token(p)
		if token == null:
			continue
		# Skip tokens being dragged by the DM
		if _dragging_token_ids.has(p.id):
			continue
		token.set_token_diameter_px(_token_diameter_px_for_profile(p, map))
		var token_radius_px := _token_diameter_px_for_profile(p, map) * 0.5
		token.set_vision_radius_px(_profile_vision_radius_px(p, map))
		var vec: Vector2 = Vector2.ZERO
		var imgr := _input_manager()
		if imgr != null:
			vec = imgr.get_vector(p.id)
		# if vec != Vector2.ZERO:
		# 	print("BackendRuntime: input for %s => %s" % [p.id, str(vec)])
		token.set_movement_input(vec)
		var prev_pos: Vector2 = token.global_position
		token.step_authoritative_motion(delta, _profile_speed_px_per_second(p, map), max_bounds)
		token.global_position = _resolve_wall_collision(prev_pos, token.global_position, map, token_radius_px)
		var pos: Vector2 = token.global_position
		if _game_state().player_positions.get(p.id, Vector2.ZERO) != pos:
			_game_state().player_positions[p.id] = pos
			moved = true
	return moved


func _rebuild_cached_wall_edges(map: MapData) -> void:
	_cached_wall_edges.clear()
	_cached_passthrough_version = _map_view.get_passthrough_version() if _map_view != null else 0
	var pass_rects: Dictionary = _map_view.get_passthrough_rects() if _map_view != null else {}
	var pass_polys: Dictionary = _map_view.get_passthrough_polys() if _map_view != null else {}
	if map == null:
		return
	for poly in map.wall_polygons:
		if not poly is Array:
			continue
		var pts := poly as Array
		if pts.size() < 2:
			continue
		# Clip polygon by open-door passthrough rects and passage corridor
		# quads so the opening is removed — the rest of the wall keeps edges.
		var packed := PackedVector2Array()
		for raw_pt: Variant in pts:
			if raw_pt is Vector2:
				packed.append(raw_pt as Vector2)
		if packed.size() < 3:
			continue
		var fragments := _clip_polygon_by_passthroughs(packed, pass_rects, pass_polys)
		for frag in fragments:
			for i in range(frag.size()):
				_cached_wall_edges.append([frag[i], frag[(i + 1) % frag.size()]])

	# Include edges from closed DOOR token wall quads (rotation-aware).
	var door_quads: Dictionary = _map_view.get_door_wall_quads() if _map_view != null else {}
	for door_quad: Variant in door_quads.values():
		var quad: PackedVector2Array = door_quad as PackedVector2Array
		for i in range(quad.size()):
			_cached_wall_edges.append([quad[i], quad[(i + 1) % quad.size()]])


func build_player_state_payload() -> Array:
	var players: Array = []
	if _map_view == null:
		return players
	var map: MapData = _map()
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var im: InputManager = registry.input if registry != null and registry.input != null else null
	var gs_mgr: GameStateManager = _game_state()
	var dv_disabled: bool = gs_mgr.is_darkvision_disabled() if gs_mgr != null else false
	for profile in _active_profiles():
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		var token_diameter_px: float = _token_diameter_px_for_profile(p, map) if map else 48.0
		var token: Node2D = _dm_tokens.get(p.id, null) as Node2D
		if token and is_instance_valid(token):
			gs_mgr.player_positions[p.id] = token.global_position
		var pos: Vector2 = gs_mgr.player_positions.get(p.id, Vector2.ZERO)
		var dashing: bool = im.is_dashing(p.id) if im != null else false
		var locked: bool = gs_mgr.is_locked(p.id)
		var light_off: bool = gs_mgr.is_light_off(p.id)
		var eff_vision_type: int = PlayerProfile.VisionType.NORMAL if dv_disabled else p.get_vision_type()
		players.append({
			"id": p.id,
			"name": p.player_name,
			"base_speed": p.get_speed(),
			"vision_type": eff_vision_type,
			"darkvision_range": p.get_darkvision_range(),
			"vision_radius_px": _profile_vision_radius_px(p, map),
			"perception_mod": p.get_passive_perception() - 10,
			"is_dashing": dashing,
			"is_locked": locked,
			"light_off": light_off,
			"vision_scale": _vision_scale_for_profile(p),
			"token_diameter_px": token_diameter_px,
			"facing": token.rotation if token and is_instance_valid(token) else 0.0,
			"icon_facing_deg": p.icon_facing_deg,
			"indicator_color": p.indicator_color.to_html(false),
			"position": {"x": pos.x, "y": pos.y},
		})
	return players


func get_dm_token_nodes() -> Dictionary:
	return _dm_tokens


func begin_token_drag(token_id: Variant) -> void:
	var token: PlayerSprite = _dm_tokens.get(token_id, null) as PlayerSprite
	if token == null or not is_instance_valid(token):
		return
	_dragging_token_ids[token_id] = true
	token.set_light_suppressed(true)


func end_token_drag(token_id: Variant, new_world_pos: Vector2) -> void:
	_dragging_token_ids.erase(token_id)
	var token: PlayerSprite = _dm_tokens.get(token_id, null) as PlayerSprite
	if token == null or not is_instance_valid(token):
		return
	token.global_position = new_world_pos
	var gs := _game_state()
	if gs != null:
		gs.player_positions[token_id] = new_world_pos
	token.set_light_suppressed(false)


func move_all_to_spawns() -> void:
	if _map_view == null:
		return
	var map: MapData = _map()
	if map == null:
		return
	var gs := _game_state()
	if gs == null:
		return
	var map_size: Vector2 = _map_view.map_image.texture.get_size() if _map_view.map_image and _map_view.map_image.texture else Vector2(1920, 1080)
	var origin: Vector2 = map_size * 0.5
	var spawn_pts: Array = map.spawn_points if map.spawn_points.size() > 0 else []

	# Pass 1: build profile_id → spawn point for explicit bindings.
	var bound_profiles: Dictionary = {}
	var bound_spawns: Dictionary = {}
	for sp_idx in range(spawn_pts.size()):
		var sp: Dictionary = spawn_pts[sp_idx] as Dictionary
		var pid: String = str(sp.get("profile_id", ""))
		if not pid.is_empty():
			bound_profiles[pid] = sp
			bound_spawns[sp_idx] = true

	# Collect unbound spawn points for round-robin.
	var unbound_spawns: Array = []
	for sp_idx in range(spawn_pts.size()):
		if not bound_spawns.has(sp_idx):
			unbound_spawns.append(spawn_pts[sp_idx])

	var rr_idx := 0
	for profile in _active_profiles():
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		if bound_profiles.has(p.id):
			var sp: Dictionary = bound_profiles[p.id] as Dictionary
			gs.player_positions[p.id] = Vector2(sp.get("x", origin.x), sp.get("y", origin.y))
		elif unbound_spawns.size() > 0:
			var sp: Dictionary = unbound_spawns[rr_idx % unbound_spawns.size()] as Dictionary
			gs.player_positions[p.id] = Vector2(sp.get("x", origin.x), sp.get("y", origin.y))
			rr_idx += 1
		elif spawn_pts.size() > 0:
			var sp: Dictionary = spawn_pts[rr_idx % spawn_pts.size()] as Dictionary
			gs.player_positions[p.id] = Vector2(sp.get("x", origin.x), sp.get("y", origin.y))
			rr_idx += 1
		else:
			gs.player_positions[p.id] = origin + Vector2((rr_idx % 4) * 40.0, floor(float(rr_idx) / 4.0) * 40.0)
			rr_idx += 1
		var token: Node2D = _dm_tokens.get(p.id, null) as Node2D
		if token and is_instance_valid(token):
			token.global_position = gs.player_positions[p.id]


func _ensure_spawn_positions() -> void:
	if _spawn_initialized or _map_view == null:
		return
	var map: MapData = _map()
	if map == null:
		return
	var map_size: Vector2 = _map_view.map_image.texture.get_size() if _map_view.map_image and _map_view.map_image.texture else Vector2(1920, 1080)
	var origin: Vector2 = map_size * 0.5

	# If a persisted save is active, positions were already restored — just ensure tokens.
	# Ephemeral sessions (no save_name) have no restored positions.
	var gs := _game_state()
	var has_restored_save: bool = gs != null and gs.active_save != null and not (gs.active_save as GameSaveData).save_name.is_empty()

	# Build spawn point list from MapData (if any).
	var spawn_pts: Array = map.spawn_points if map.spawn_points.size() > 0 else []

	# First pass: build a map of profile_id → spawn point for explicit bindings.
	var bound_profiles: Dictionary = {}
	var bound_spawns: Dictionary = {}
	for sp_idx in range(spawn_pts.size()):
		var sp: Dictionary = spawn_pts[sp_idx] as Dictionary
		var pid: String = str(sp.get("profile_id", ""))
		if not pid.is_empty():
			bound_profiles[pid] = sp
			bound_spawns[sp_idx] = true

	# Collect unbound spawn points for round-robin fallback.
	var unbound_spawns: Array = []
	for sp_idx in range(spawn_pts.size()):
		if not bound_spawns.has(sp_idx):
			unbound_spawns.append(spawn_pts[sp_idx])

	var rr_idx := 0
	for profile in _active_profiles():
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		var current: Vector2 = gs.player_positions.get(p.id, Vector2.ZERO)
		if current == Vector2.ZERO and not has_restored_save:
			# Check for explicit profile_id binding first.
			if bound_profiles.has(p.id):
				var sp: Dictionary = bound_profiles[p.id] as Dictionary
				gs.player_positions[p.id] = Vector2(sp.get("x", origin.x), sp.get("y", origin.y))
			elif unbound_spawns.size() > 0:
				var sp: Dictionary = unbound_spawns[rr_idx % unbound_spawns.size()] as Dictionary
				gs.player_positions[p.id] = Vector2(sp.get("x", origin.x), sp.get("y", origin.y))
				rr_idx += 1
			elif spawn_pts.size() > 0:
				var sp: Dictionary = spawn_pts[rr_idx % spawn_pts.size()] as Dictionary
				gs.player_positions[p.id] = Vector2(sp.get("x", origin.x), sp.get("y", origin.y))
				rr_idx += 1
			else:
				gs.player_positions[p.id] = origin + Vector2((rr_idx % 4) * 40.0, floor(float(rr_idx) / 4.0) * 40.0)
				rr_idx += 1
		_ensure_token(p)
		var token: Node2D = _dm_tokens.get(p.id, null) as Node2D
		if token and is_instance_valid(token):
			token.global_position = gs.player_positions[p.id]
	_spawn_initialized = true


func _ensure_token(profile: PlayerProfile) -> PlayerSprite:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var im: InputManager = registry.input if registry != null and registry.input != null else null
	var dashing: bool = im.is_dashing(profile.id) if im != null else false
	var gs := _game_state()
	var dv_disabled: bool = gs.is_darkvision_disabled() if gs != null else false
	var eff_vision_type: int = PlayerProfile.VisionType.NORMAL if dv_disabled else profile.get_vision_type()
	if _dm_tokens.has(profile.id):
		var existing: PlayerSprite = _dm_tokens[profile.id] as PlayerSprite
		if is_instance_valid(existing):
			existing.apply_from_state({
				"id": profile.id,
				"name": profile.player_name,
				"base_speed": profile.get_speed(),
				"vision_type": eff_vision_type,
				"darkvision_range": profile.get_darkvision_range(),
				"vision_radius_px": _profile_vision_radius_px(profile, _map()),
				"perception_mod": profile.get_passive_perception() - 10,
				"is_dashing": dashing,
				"icon_facing_deg": profile.icon_facing_deg,
				"vision_scale": _vision_scale_for_profile(profile), "indicator_color": profile.indicator_color.to_html(false), "position": {
					"x": _game_state().player_positions.get(profile.id, Vector2.ZERO).x,
					"y": _game_state().player_positions.get(profile.id, Vector2.ZERO).y,
				},
			})
			_apply_profile_icon(existing, profile)
			return existing
		_dm_tokens.erase(profile.id)

	if _map_view == null or PlayerSpriteScene == null:
		return null
	var token: PlayerSprite = PlayerSpriteScene.instantiate() as PlayerSprite
	if token == null:
		return null
	token.name = "DMToken_%s" % profile.id.left(8)
	_map_view.get_token_layer().add_child(token)
	token.set_vision_render_enabled(false)
	token.apply_from_state({
		"id": profile.id,
		"name": profile.player_name,
		"base_speed": profile.get_speed(),
		"vision_type": eff_vision_type,
		"darkvision_range": profile.get_darkvision_range(),
		"vision_radius_px": _profile_vision_radius_px(profile, _map()),
		"perception_mod": profile.get_passive_perception() - 10,
		"is_dashing": dashing,
		"icon_facing_deg": profile.icon_facing_deg,
		"vision_scale": _vision_scale_for_profile(profile),
		"indicator_color": profile.indicator_color.to_html(false),
		"position": {
			"x": _game_state().player_positions.get(profile.id, Vector2.ZERO).x,
			"y": _game_state().player_positions.get(profile.id, Vector2.ZERO).y,
		},
	})
	_apply_profile_icon(token, profile)
	_dm_tokens[profile.id] = token
	return token


func _apply_profile_icon(token: PlayerSprite, profile: PlayerProfile) -> void:
	if profile.icon_image_path.is_empty():
		token.set_custom_icon_texture(null)
		return
	var tex: ImageTexture = TokenIconUtils.get_or_load_circular_texture(profile.icon_image_path)
	token.set_custom_icon_texture(tex)


func _profile_speed_px_per_second(profile: PlayerProfile, map: MapData) -> float:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.movement != null:
		return registry.movement.get_player_speed_px_per_sec(profile, map)
	# Fallback (pre-bootstrap or missing service)
	var px_per_5ft := _pixels_per_5ft(map)
	var speed := (maxf(profile.get_speed(), 5.0) / 5.0) * px_per_5ft / IMovementService.ROUND_DURATION_SEC
	if registry != null and registry.input != null and registry.input.is_dashing(profile.id):
		speed *= 2.0
	return speed


func _profile_vision_radius_px(profile: PlayerProfile, map: MapData) -> float:
	var gs := _game_state()
	var dv_disabled: bool = gs.is_darkvision_disabled() if gs != null else false
	var eff_vision: int = PlayerProfile.VisionType.NORMAL if dv_disabled else profile.get_vision_type()
	var eff_dv: float = profile.get_darkvision_range()
	if map == null:
		return eff_dv if eff_vision == PlayerProfile.VisionType.DARKVISION else 60.0
	var radius_feet := eff_dv if eff_vision == PlayerProfile.VisionType.DARKVISION else NORMAL_VISION_RANGE_FEET
	return (maxf(radius_feet, 5.0) / 5.0) * _pixels_per_5ft(map)


func _pixels_per_5ft(map: MapData) -> float:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.movement != null:
		return registry.movement.pixels_per_5ft(map)
	if map == null:
		return 60.0
	return map.cell_px if map.grid_type == MapData.GridType.SQUARE else map.hex_size * 2.0


func _vision_scale_for_profile(_profile: PlayerProfile) -> float:
	return 1.0


func _token_diameter_px_for_map(map: MapData) -> float:
	return map.cell_px if map.grid_type == MapData.GridType.SQUARE else map.hex_size * 2.0


func _token_diameter_px_for_profile(profile: PlayerProfile, map: MapData) -> float:
	var px_per_5ft: float = _token_diameter_px_for_map(map)
	return profile.get_size_ft() / 5.0 * px_per_5ft


func resize_player_tokens_for_calibration() -> void:
	var map: MapData = _map()
	if map == null:
		return
	for profile in _active_profiles():
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		var token: PlayerSprite = _dm_tokens.get(p.id, null) as PlayerSprite
		if token == null or not is_instance_valid(token):
			continue
		token.set_token_diameter_px(_token_diameter_px_for_profile(p, map))


func _resolve_wall_collision(prev_pos: Vector2, next_pos: Vector2, map: MapData, token_radius_px: float) -> Vector2:
	if _cached_wall_edges.is_empty():
		return next_pos
	if prev_pos.distance_squared_to(next_pos) <= 0.000001:
		return next_pos
	var clearance := maxf(token_radius_px, 0.0)
	if _can_move_between(prev_pos, next_pos, map, clearance):
		return next_pos

	# Deterministic axis-stepped resolution avoids intermittent corner tunneling
	# and keeps movement smooth along wall boundaries.
	var resolved := prev_pos
	var x_step := Vector2(next_pos.x, resolved.y)
	if _can_move_between(resolved, x_step, map, clearance):
		resolved = x_step
	var y_step := Vector2(resolved.x, next_pos.y)
	if _can_move_between(resolved, y_step, map, clearance):
		resolved = y_step
	if resolved != prev_pos:
		return resolved

	var alt := prev_pos
	var y_first := Vector2(alt.x, next_pos.y)
	if _can_move_between(alt, y_first, map, clearance):
		alt = y_first
	var x_second := Vector2(next_pos.x, alt.y)
	if _can_move_between(alt, x_second, map, clearance):
		alt = x_second
	if alt != prev_pos:
		return alt

	return prev_pos


func _can_move_between(a: Vector2, b: Vector2, map: MapData, radius_px: float) -> bool:
	if _segment_hits_any_wall(a, b, radius_px):
		return false
	if map != null and _is_point_blocked_for_radius(b, map, radius_px):
		return false
	return true


func _is_point_blocked_for_radius(pos: Vector2, map: MapData, radius_px: float) -> bool:
	if _point_inside_any_wall(pos, map):
		return true
	if radius_px <= 0.001:
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
		var closest := Geometry2D.get_closest_point_to_segment(pos, av as Vector2, bv as Vector2)
		if pos.distance_to(closest) < radius_px:
			return true
	return false


func _clip_polygon_by_passthroughs(points: PackedVector2Array, pass_rects: Dictionary, pass_polys: Dictionary = {}) -> Array[PackedVector2Array]:
	if pass_rects.is_empty() and pass_polys.is_empty():
		return [points]
	var current: Array[PackedVector2Array] = [points]
	# Subtract AABB rect openings (doors and passage fallback).
	for pass_rect: Variant in pass_rects.values():
		var rect: Rect2 = pass_rect as Rect2
		var clip_poly := PackedVector2Array([
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		])
		var next_frags: Array[PackedVector2Array] = []
		for frag in current:
			var clipped := Geometry2D.clip_polygons(frag, clip_poly)
			for c in clipped:
				if c.size() >= 3:
					next_frags.append(c)
		current = next_frags
		if current.is_empty():
			break
	if current.is_empty():
		return current
	# Subtract passage corridor segment quads (precise polygon clipping).
	for raw_quads: Variant in pass_polys.values():
		if not raw_quads is Array:
			continue
		for raw_q: Variant in raw_quads as Array:
			if not raw_q is PackedVector2Array:
				continue
			var quad: PackedVector2Array = raw_q as PackedVector2Array
			if quad.size() < 3:
				continue
			var next2: Array[PackedVector2Array] = []
			for frag in current:
				var clipped := Geometry2D.clip_polygons(frag, quad)
				for c in clipped:
					if c.size() >= 3:
						next2.append(c)
			current = next2
			if current.is_empty():
				break
		if current.is_empty():
			break
	return current


func _point_inside_any_wall(pos: Vector2, map: MapData) -> bool:
	var pass_rects: Dictionary = _map_view.get_passthrough_rects() if _map_view != null else {}
	var pass_polys: Dictionary = _map_view.get_passthrough_polys() if _map_view != null else {}
	for poly in map.wall_polygons:
		if not poly is Array:
			continue
		var points := PackedVector2Array()
		for p in poly:
			if p is Vector2:
				points.append(p)
		if points.size() < 3:
			continue
		# Clip by open-door passthrough rects and passage corridor quads;
		# check remaining fragments.
		var fragments := _clip_polygon_by_passthroughs(points, pass_rects, pass_polys)
		for frag in fragments:
			if Geometry2D.is_point_in_polygon(pos, frag):
				return true
	# Check closed DOOR token wall quads (rotation-aware).
	var door_quads: Dictionary = _map_view.get_door_wall_quads() if _map_view != null else {}
	for door_quad: Variant in door_quads.values():
		if Geometry2D.is_point_in_polygon(pos, door_quad as PackedVector2Array):
			return true
	return false


func _segment_hits_any_wall(a: Vector2, b: Vector2, radius_px: float = 0.0) -> bool:
	var seg_len := a.distance_to(b)
	if seg_len <= 0.001:
		return false
	if _segment_hits_any_wall_center(a, b):
		return true
	if radius_px <= 0.001:
		return false
	var move_dir := (b - a).normalized()
	if move_dir.length_squared() <= 0.000001:
		return false
	var offset := Vector2(-move_dir.y, move_dir.x) * radius_px
	if _segment_hits_any_wall_center(a + offset, b + offset):
		return true
	if _segment_hits_any_wall_center(a - offset, b - offset):
		return true
	return false


func _segment_hits_any_wall_center(a: Vector2, b: Vector2) -> bool:
	var seg_len := a.distance_to(b)
	if seg_len <= 0.001:
		return false
	var endpoint_epsilon := minf(0.05, seg_len * 0.1)
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
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, av as Vector2, bv as Vector2)
		if not hit is Vector2:
			continue
		var d := a.distance_to(hit as Vector2)
		if d >= endpoint_epsilon and d <= (seg_len - endpoint_epsilon):
			return true
	return false


func _first_wall_hit(a: Vector2, b: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var seg_len := a.distance_to(b)
	if seg_len <= 0.001:
		return best
	var endpoint_epsilon := minf(0.05, seg_len * 0.1)
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
		var pa := av as Vector2
		var pb := bv as Vector2
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, pa, pb)
		if not hit is Vector2:
			continue
		var hp := hit as Vector2
		var d := a.distance_to(hp)
		if d < endpoint_epsilon or d > (seg_len - endpoint_epsilon):
			continue
		if d < best_d:
			best_d = d
			best = {"point": hp, "a": pa, "b": pb}
	return best
