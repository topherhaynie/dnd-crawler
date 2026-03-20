extends Node

## ServiceBootstrap — instantiates all services, wires them into typed managers,
## and registers them via ServiceRegistry.
##
## All add_child calls are deferred so that service _ready() methods run after
## the scene tree is stable. The registry object is fully configured before
## it enters the tree.

func _ready() -> void:
	# --- Instantiate services ---
	var fog_svc := FogService.new()
	fog_svc.name = "FogService"

	var map_svc := MapService.new()
	map_svc.name = "MapService"

	var net_svc := NetworkService.new()
	net_svc.name = "NetworkService"

	var gs_svc := GameStateService.new()
	gs_svc.name = "GameStateService"

	var ps_svc := ProfileService.new()
	ps_svc.name = "ProfileService"

	var persistence_svc := PersistenceService.new()
	persistence_svc.name = "PersistenceService"

	var input_svc := InputService.new()
	input_svc.name = "InputService"

	# --- Build registry and wire managers ---
	var registry := ServiceRegistry.new()
	registry.name = "ServiceRegistry"

	var fog_mgr := FogManager.new()
	fog_mgr.service = fog_svc
	registry.fog = fog_mgr

	var map_mgr := MapManager.new()
	map_mgr.service = map_svc
	registry.map = map_mgr

	var net_mgr := NetworkManager.new()
	net_mgr.service = net_svc
	registry.network = net_mgr

	var gs_mgr := GameStateManager.new()
	gs_mgr.service = gs_svc
	registry.game_state = gs_mgr

	var ps_mgr := ProfileManager.new()
	ps_mgr.service = ps_svc
	registry.profile = ps_mgr

	var persistence_mgr := PersistenceManager.new()
	persistence_mgr.service = persistence_svc
	registry.persistence = persistence_mgr

	var input_mgr := InputManager.new()
	input_mgr.service = input_svc
	registry.input = input_mgr

	# --- Add to scene tree (deferred to avoid ready-order races) ---
	var root := get_tree().root
	root.call_deferred("add_child", registry)
	root.call_deferred("add_child", fog_svc)
	root.call_deferred("add_child", map_svc)
	root.call_deferred("add_child", net_svc)
	root.call_deferred("add_child", gs_svc)
	root.call_deferred("add_child", ps_svc)
	root.call_deferred("add_child", persistence_svc)
	root.call_deferred("add_child", input_svc)

	print("ServiceBootstrap: all services registered")
