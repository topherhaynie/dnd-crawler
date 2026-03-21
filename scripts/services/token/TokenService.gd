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
	const PERCEPTION_RANGE_PX: float = 192.0
	var newly_revealed: Array = []
	for raw in _tokens.values():
		var data: TokenData = raw as TokenData
		if data == null or data.is_visible_to_players or data.perception_dc < 0:
			continue
		for i in range(player_positions.size()):
			var pp: Vector2 = player_positions[i] as Vector2
			if data.world_pos.distance_to(pp) > PERCEPTION_RANGE_PX:
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
