extends ITokenService
class_name TokenService

# ---------------------------------------------------------------------------
# TokenService — concrete token domain service.
#
# Owns the canonical in-memory token collection (_tokens: Dictionary).
# All state mutations go through this service; callers receive change
# notifications via the signals declared in ITokenService.
# ---------------------------------------------------------------------------

## id (String) → TokenData
var _tokens: Dictionary = {}


# ---------------------------------------------------------------------------
# Mutation
# ---------------------------------------------------------------------------

func add_token(data: TokenData) -> void:
	if data == null or data.id.is_empty():
		push_error("TokenService.add_token: data is null or has empty id")
		return
	_tokens[data.id] = data
	token_added.emit(data)


func remove_token(id: String) -> void:
	if not _tokens.has(id):
		return
	_tokens.erase(id)
	token_removed.emit(id)


func move_token(id: String, new_pos: Vector2) -> void:
	var data: TokenData = _tokens.get(id, null) as TokenData
	if data == null:
		return
	data.world_pos = new_pos
	token_moved.emit(id, new_pos)


func update_token(data: TokenData) -> void:
	if data == null or data.id.is_empty():
		push_error("TokenService.update_token: data is null or has empty id")
		return
	_tokens[data.id] = data
	token_updated.emit(data)


func set_token_visibility(id: String, is_visible: bool) -> void:
	var data: TokenData = _tokens.get(id, null) as TokenData
	if data == null:
		return
	if data.is_visible_to_players == is_visible:
		return
	data.is_visible_to_players = is_visible
	token_visibility_changed.emit(id, is_visible)
	token_updated.emit(data)


# ---------------------------------------------------------------------------
# Bulk
# ---------------------------------------------------------------------------

func load_tokens(dicts: Array) -> void:
	_tokens.clear()
	for raw in dicts:
		if raw is Dictionary:
			var d := raw as Dictionary
			var token: TokenData = TokenData.from_dict(d)
			_tokens[token.id] = token
	tokens_reloaded.emit()


func clear_tokens() -> void:
	_tokens.clear()
	tokens_reloaded.emit()


# ---------------------------------------------------------------------------
# Query
# ---------------------------------------------------------------------------

func get_all_tokens() -> Array:
	return _tokens.values()


func get_visible_tokens() -> Array:
	var out: Array = []
	for raw in _tokens.values():
		var data: TokenData = raw as TokenData
		if data != null and data.is_visible_to_players:
			out.append(data)
	return out


func get_token_by_id(id: String) -> TokenData:
	return _tokens.get(id, null) as TokenData


# ---------------------------------------------------------------------------
# Perception proximity (Phase 6)
# ---------------------------------------------------------------------------

## Check whether any hidden tokens with a perception_dc set should be
## auto-revealed given the current player positions and perception modifiers.
##
## player_positions  — Array of Vector2 world positions (one per player token)
## player_perceptions — Array of int passive-perception modifiers (same order)
## Returns Array of token IDs that were newly revealed.
func check_perception_proximity(
		player_positions: Array, player_perceptions: Array) -> Array:
	var newly_revealed: Array = []
	for raw in _tokens.values():
		var data: TokenData = raw as TokenData
		if data == null or data.is_visible_to_players or data.perception_dc < 0:
			continue
		if not data.auto_reveal:
			continue
		for i in range(player_positions.size()):
			var pp: Vector2 = player_positions[i] as Vector2
			if data.world_pos.distance_to(pp) > data.trigger_radius_px:
				continue
			var mod: int = 0
			if i < player_perceptions.size():
				mod = int(player_perceptions[i])
			if mod >= data.perception_dc:
				data.is_visible_to_players = true
				token_visibility_changed.emit(data.id, true)
				token_updated.emit(data)
				newly_revealed.append(data.id)
				break
	return newly_revealed


# ---------------------------------------------------------------------------
# Autopause proximity (legacy — kept for non-collision tokens)
# ---------------------------------------------------------------------------

func check_autopause_proximity(positions: Array, player_ids: Array) -> Array:
	var triggered: Array = []
	for raw in _tokens.values():
		var data: TokenData = raw as TokenData
		if data == null or not data.autopause:
			continue
		if data.autopause_max_triggers > 0 and data._trigger_count >= data.autopause_max_triggers:
			continue
		var radius: float = data.trigger_radius_px
		if data.autopause_on_collision:
			radius = maxf(data.width_px, data.height_px) * 0.5
		for i in range(positions.size()):
			var pp: Vector2 = positions[i] as Vector2
			if data.world_pos.distance_to(pp) > radius:
				continue
			var pid: String = str(player_ids[i]) if i < player_ids.size() else ""
			if pid.is_empty() or triggered.has(pid):
				continue
			triggered.append(pid)
			data._trigger_count += 1
			if data.autopause_max_triggers > 0 and data._trigger_count >= data.autopause_max_triggers:
				break
	return triggered


# ---------------------------------------------------------------------------
# Autopause collision — swept-path aware
# ---------------------------------------------------------------------------

## Swept-path autopause check.  For tokens with autopause_on_collision,
## tests whether the movement segment (prev→curr) intersects the effective
## collision disc (trap body + player_radius).  Collision always pauses
## regardless of visibility — the DM must manually disable autopause.
## Hidden collision-mode tokens are also auto-revealed on trigger.
## For other autopause tokens uses the larger trigger_radius_px with a
## simple point-in-circle test on the current position.
##
## Returns Dictionary {"player_ids": Array[String], "revealed_token_ids": Array[String]}.
func check_autopause_collision(
		prev_positions: Array, curr_positions: Array,
		player_ids: Array, player_radius: float) -> Dictionary:
	var triggered: Array = []
	var revealed: Array = []
	for raw in _tokens.values():
		var data: TokenData = raw as TokenData
		if data == null or not data.autopause:
			continue
		if data.autopause_max_triggers > 0 and data._trigger_count >= data.autopause_max_triggers:
			continue

		var use_collision: bool = data.autopause_on_collision

		for i in range(curr_positions.size()):
			var hit: bool = false
			if use_collision:
				var prev: Vector2 = prev_positions[i] as Vector2 if i < prev_positions.size() else curr_positions[i] as Vector2
				var curr: Vector2 = curr_positions[i] as Vector2
				if data.token_shape == TokenData.TokenShape.RECTANGLE:
					hit = _segment_intersects_obb(prev, curr,
							data.world_pos, data.width_px, data.height_px,
							data.rotation_deg, player_radius)
				else:
					# Ellipse — approximate as circle using average of half-extents.
					var body_r: float = (data.width_px + data.height_px) * 0.25
					hit = _segment_intersects_circle(prev, curr,
							data.world_pos, body_r + player_radius)
			else:
				var curr: Vector2 = curr_positions[i] as Vector2
				hit = data.world_pos.distance_to(curr) <= data.trigger_radius_px

			if not hit:
				continue
			var pid: String = str(player_ids[i]) if i < player_ids.size() else ""
			if pid.is_empty() or triggered.has(pid):
				continue
			triggered.append(pid)
			data._trigger_count += 1
			# Collision-mode: reveal the hidden token (trap sprung).
			if use_collision and not data.is_visible_to_players:
				data.is_visible_to_players = true
				token_visibility_changed.emit(data.id, true)
				token_updated.emit(data)
				if not revealed.has(data.id):
					revealed.append(data.id)
			if data.autopause_max_triggers > 0 and data._trigger_count >= data.autopause_max_triggers:
				break
	return {"player_ids": triggered, "revealed_token_ids": revealed}


## Returns true when movement segment AB passes within `radius` of `center`.
static func _segment_intersects_circle(
		a: Vector2, b: Vector2, center: Vector2, radius: float) -> bool:
	var d: Vector2 = b - a
	var f: Vector2 = a - center
	var seg_len_sq: float = d.length_squared()
	# Degenerate segment — point-in-circle test.
	if seg_len_sq < 0.0001:
		return f.length_squared() <= radius * radius
	# Parameter t of closest point on infinite line, clamped to [0,1].
	var t: float = clampf(-f.dot(d) / seg_len_sq, 0.0, 1.0)
	var closest: Vector2 = a + d * t
	return closest.distance_squared_to(center) <= radius * radius


## Returns true when segment AB intersects a rotated rectangle (OBB) expanded
## outward by `margin` (the player body radius).  The rectangle is centred at
## `center` with full size `w` x `h` and rotation `rot_deg` degrees.
static func _segment_intersects_obb(
		a: Vector2, b: Vector2, center: Vector2,
		w: float, h: float, rot_deg: float, margin: float) -> bool:
	# Transform segment endpoints into the OBB's local frame so the box is
	# axis-aligned and centred at the origin.
	var angle: float = deg_to_rad(-rot_deg)
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	var la: Vector2 = _rotate_point(a - center, cos_a, sin_a)
	var lb: Vector2 = _rotate_point(b - center, cos_a, sin_a)
	# Half-extents expanded by the player radius.
	var hx: float = w * 0.5 + margin
	var hy: float = h * 0.5 + margin
	# Now test segment la→lb against axis-aligned rect [-hx,hx] x [-hy,hy].
	return _segment_intersects_aabb(la, lb, hx, hy)


## Rotate a 2D point by precomputed cos/sin values.
static func _rotate_point(p: Vector2, cos_a: float, sin_a: float) -> Vector2:
	return Vector2(p.x * cos_a - p.y * sin_a, p.x * sin_a + p.y * cos_a)


## Segment vs axis-aligned box [-hx,hx] x [-hy,hy] using slab intersection.
static func _segment_intersects_aabb(
		a: Vector2, b: Vector2, hx: float, hy: float) -> bool:
	# Check if either endpoint is inside the box (common fast path).
	if absf(a.x) <= hx and absf(a.y) <= hy:
		return true
	if absf(b.x) <= hx and absf(b.y) <= hy:
		return true
	var d: Vector2 = b - a
	var t_min: float = 0.0
	var t_max: float = 1.0
	# X slab
	if absf(d.x) > 0.0001:
		var inv: float = 1.0 / d.x
		var t1: float = (-hx - a.x) * inv
		var t2: float = (hx - a.x) * inv
		if t1 > t2:
			var tmp: float = t1; t1 = t2; t2 = tmp
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return false
	elif absf(a.x) > hx:
		return false # Parallel and outside X slab
	# Y slab
	if absf(d.y) > 0.0001:
		var inv: float = 1.0 / d.y
		var t1: float = (-hy - a.y) * inv
		var t2: float = (hy - a.y) * inv
		if t1 > t2:
			var tmp: float = t1; t1 = t2; t2 = tmp
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return false
	elif absf(a.y) > hy:
		return false # Parallel and outside Y slab
	return true


# ---------------------------------------------------------------------------
# Interact proximity
# ---------------------------------------------------------------------------

func check_interact_proximity(pos: Vector2) -> Array:
	var result: Array = []
	for raw in _tokens.values():
		var data: TokenData = raw as TokenData
		if data == null or not data.pause_on_interact:
			continue
		if data.world_pos.distance_to(pos) <= data.trigger_radius_px:
			result.append(data.id)
	return result


# ---------------------------------------------------------------------------
# Detection proximity
# ---------------------------------------------------------------------------

func check_detection_proximity(positions: Array, _player_ids: Array, perceptions: Array) -> Array:
	var detected_ids: Array = []
	for raw in _tokens.values():
		var data: TokenData = raw as TokenData
		if data == null or data.is_visible_to_players or data.perception_dc < 0:
			continue
		for i in range(positions.size()):
			var pp: Vector2 = positions[i] as Vector2
			if data.world_pos.distance_to(pp) > data.trigger_radius_px:
				continue
			var mod: int = 0
			if i < perceptions.size():
				mod = int(perceptions[i])
			# Player is in range — show detection indicator if not auto-revealed.
			# Tokens with auto_reveal=true that meet DC are revealed (not detected);
			# all others in range get the "!" indicator.
			if not detected_ids.has(data.id):
				if data.auto_reveal and mod >= data.perception_dc:
					break # will be auto-revealed, skip detection
				detected_ids.append(data.id)
	return detected_ids
