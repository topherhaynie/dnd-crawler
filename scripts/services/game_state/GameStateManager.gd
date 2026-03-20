extends RefCounted
class_name GameStateManager

## Typed manager for the game state service.
## Access via: get_node("/root/ServiceRegistry").game_state.service

var service: IGameState = null
