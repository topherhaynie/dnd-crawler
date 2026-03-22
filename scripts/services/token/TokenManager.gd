extends RefCounted
class_name TokenManager

# ---------------------------------------------------------------------------
# TokenManager — typed coordinator for the token domain.
#
# Owned by ServiceRegistry.token.  All callers access token operations
# through manager methods — never via `registry.token.service` directly.
# ---------------------------------------------------------------------------

var service: ITokenService = null


func get_token_by_id(id: String) -> TokenData:
	if service == null:
		return null
	return service.get_token_by_id(id)


func update_token(data: TokenData) -> void:
	if service == null:
		return
	service.update_token(data)


func get_visible_tokens() -> Array:
	if service == null:
		return []
	return service.get_visible_tokens()


func get_all_tokens() -> Array:
	if service == null:
		return []
	return service.get_all_tokens()


func set_token_visibility(id: String, is_visible: bool) -> void:
	if service == null:
		return
	service.set_token_visibility(id, is_visible)


func add_token(data: TokenData) -> void:
	if service == null:
		return
	service.add_token(data)


func remove_token(id: String) -> void:
	if service == null:
		return
	service.remove_token(id)


func move_token(id: String, new_pos: Vector2) -> void:
	if service == null:
		return
	service.move_token(id, new_pos)


func check_perception_proximity(player_positions: Array, player_perceptions: Array) -> Array:
	if service == null:
		return []
	return service.check_perception_proximity(player_positions, player_perceptions)


func load_tokens(dicts: Array) -> void:
	if service == null:
		return
	service.load_tokens(dicts)


func clear_tokens() -> void:
	if service == null:
		return
	service.clear_tokens()
