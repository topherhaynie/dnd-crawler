extends Node
class_name ITokenService

# ---------------------------------------------------------------------------
# ITokenService — protocol (interface) for the token domain service.
#
# All public methods are declared here with push_error stubs so that
# concrete implementations must override them.  Signals are also declared
# here; concrete services must NOT redeclare them.
# ---------------------------------------------------------------------------

# --- Signals ---------------------------------------------------------------
@warning_ignore("unused_signal")
signal token_added(data: TokenData)
@warning_ignore("unused_signal")
signal token_removed(id: String)
@warning_ignore("unused_signal")
signal token_moved(id: String, new_pos: Vector2)
@warning_ignore("unused_signal")
signal token_updated(data: TokenData)
@warning_ignore("unused_signal")
signal token_visibility_changed(id: String, is_visible: bool)
@warning_ignore("unused_signal")
signal tokens_reloaded


# --- Mutation --------------------------------------------------------------

func add_token(_data: TokenData) -> void:
	push_error("ITokenService.add_token: not implemented")


func remove_token(_id: String) -> void:
	push_error("ITokenService.remove_token: not implemented")


func move_token(_id: String, _new_pos: Vector2) -> void:
	push_error("ITokenService.move_token: not implemented")


func update_token(_data: TokenData) -> void:
	push_error("ITokenService.update_token: not implemented")


func set_token_visibility(_id: String, _is_visible: bool) -> void:
	push_error("ITokenService.set_token_visibility: not implemented")


# --- Bulk ------------------------------------------------------------------

## Replace the entire token collection from an array of serialised dicts.
func load_tokens(_dicts: Array) -> void:
	push_error("ITokenService.load_tokens: not implemented")


func clear_tokens() -> void:
	push_error("ITokenService.clear_tokens: not implemented")


# --- Query -----------------------------------------------------------------

func get_all_tokens() -> Array:
	push_error("ITokenService.get_all_tokens: not implemented")
	return []


## Returns only tokens where is_visible_to_players == true.
func get_visible_tokens() -> Array:
	push_error("ITokenService.get_visible_tokens: not implemented")
	return []


## Returns the TokenData for the given id, or null if not found.
func get_token_by_id(_id: String) -> TokenData:
	push_error("ITokenService.get_token_by_id: not implemented")
	return null

## Auto-reveals tokens whose perception DC is met by nearby players.
## Returns an Array of token ids that were newly revealed.
func check_perception_proximity(_player_positions: Array, _player_perceptions: Array) -> Array:
	push_error("ITokenService.check_perception_proximity: not implemented")
	return []


## Returns player_ids of players within any autopause token's trigger_radius_px.
func check_autopause_proximity(_positions: Array, _player_ids: Array) -> Array:
	push_error("ITokenService.check_autopause_proximity: not implemented")
	return []


## Returns token IDs of pause_on_interact tokens within trigger_radius_px of pos.
func check_interact_proximity(_pos: Vector2) -> Array:
	push_error("ITokenService.check_interact_proximity: not implemented")
	return []


## Returns token IDs where a player is within trigger_radius_px but
## passive perception < perception_dc (sensed but not identified).
func check_detection_proximity(_positions: Array, _player_ids: Array, _perceptions: Array) -> Array:
	push_error("ITokenService.check_detection_proximity: not implemented")
	return []
