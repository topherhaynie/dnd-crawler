extends Node
class_name ServiceRegistry

## Service locator with typed manager properties.
##
## Access services via typed manager properties:
##   get_node("/root/ServiceRegistry").fog.service.get_fog_state()
##
## Swap implementations at runtime:
##   registry.fog.service = DebugFogService.new()
##
## Backwards-compat shim: get_service(String) remains available during the
## migration from string-keyed lookups. Once all callers use typed manager
## properties, get_service can be removed.

var fog: FogManager = null
var map: MapManager = null
var network: NetworkManager = null
var game_state: GameStateManager = null
var profile: ProfileManager = null
var persistence: PersistenceManager = null
var input: InputManager = null
var token: TokenManager = null

## Backwards-compat shim — returns the typed service for string-keyed callers.
## @deprecated Use typed manager properties instead.
func get_service(svc_name: String) -> Object:
	match svc_name:
		"Fog":
			return fog.service if fog != null else null
		"Map":
			return map.service if map != null else null
		"Network":
			return network.service if network != null else null
		"GameState":
			return game_state.service if game_state != null else null
		"GameStateAdapter":
			return game_state.service if game_state != null else null
		"Profile":
			return profile.service if profile != null else null
		"Persistence":
			return persistence.service if persistence != null else null
		"Input":
			return input.service if input != null else null
		"Token":
			return token.service if token != null else null
	push_warning("ServiceRegistry.get_service: unknown service key '%s'" % svc_name)
	return null
