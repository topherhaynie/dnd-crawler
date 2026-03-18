extends Node

func _ready() -> void:
    # Load service scripts explicitly to avoid analyzer scope issues during headless/test runs.
    var ServiceRegistryScript: Script = load("res://scripts/registry/ServiceRegistry.gd")
    var FogServiceScript: Script = load("res://scripts/services/FogService.gd")
    var FogAdapterScript: Script = load("res://scripts/registry/FogAdapter.gd")
    var MapServiceScript: Script = load("res://scripts/services/MapService.gd")
    var MapAdapterScript: Script = load("res://scripts/registry/MapAdapter.gd")
    var NetworkServiceScript: Script = load("res://scripts/services/NetworkService.gd")
    var NetworkAdapterScript: Script = load("res://scripts/registry/NetworkAdapter.gd")
    var GameStateServiceScript: Script = load("res://scripts/services/GameStateService.gd")
    var GameStateAdapterScript: Script = load("res://scripts/registry/GameStateAdapter.gd")
    var ProfileServiceScript: Script = load("res://scripts/services/ProfileService.gd")
    var ProfileAdapterScript: Script = load("res://scripts/registry/ProfileAdapter.gd")
    var PersistenceServiceScript: Script = load("res://scripts/services/PersistenceService.gd")
    var PersistenceAdapterScript: Script = load("res://scripts/registry/PersistenceAdapter.gd")

    var registry: ServiceRegistry = ServiceRegistryScript.new() as ServiceRegistry
    registry.name = "ServiceRegistry"
    get_tree().root.call_deferred("add_child", registry)

    var fog: FogService = FogServiceScript.new() as FogService
    fog.name = "FogService"
    get_tree().root.call_deferred("add_child", fog)

    var map: MapService = MapServiceScript.new() as MapService
    map.name = "MapService"
    get_tree().root.call_deferred("add_child", map)

    var adapter: FogAdapter = FogAdapterScript.new() as FogAdapter
    adapter.name = "FogAdapter"
    if adapter.has_method("set_service"):
        adapter.set_service(fog)
    get_tree().root.call_deferred("add_child", adapter)

    var map_adapter: MapAdapter = MapAdapterScript.new() as MapAdapter
    map_adapter.name = "MapAdapter"
    if map_adapter.has_method("set_service"):
        map_adapter.set_service(map)
    get_tree().root.call_deferred("add_child", map_adapter)

    var net: Node = NetworkServiceScript.new() as Node
    net.name = "NetworkService"
    get_tree().root.call_deferred("add_child", net)

    var net_adapter: Node = NetworkAdapterScript.new() as Node
    net_adapter.name = "NetworkAdapter"
    if net_adapter.has_method("set_service"):
        net_adapter.set_service(net)
    get_tree().root.call_deferred("add_child", net_adapter)

    var gs: Node = GameStateServiceScript.new() as Node
    gs.name = "GameStateService"
    get_tree().root.call_deferred("add_child", gs)

    var gs_adapter: Node = GameStateAdapterScript.new() as Node
    gs_adapter.name = "GameStateAdapter"
    if gs_adapter.has_method("set_service"):
        gs_adapter.set_service(gs)
    get_tree().root.call_deferred("add_child", gs_adapter)

    var ps: Node = ProfileServiceScript.new() as Node
    ps.name = "ProfileService"
    get_tree().root.call_deferred("add_child", ps)

    var ps_adapter: Node = ProfileAdapterScript.new() as Node
    ps_adapter.name = "ProfileAdapter"
    if ps_adapter.has_method("set_service"):
        ps_adapter.set_service(ps)
    get_tree().root.call_deferred("add_child", ps_adapter)

    var persistence = PersistenceServiceScript.new()
    persistence.name = "PersistenceService"
    get_tree().root.call_deferred("add_child", persistence)

    var persistence_adapter = PersistenceAdapterScript.new()
    persistence_adapter.name = "PersistenceAdapter"
    if persistence_adapter.has_method("set_service"):
        persistence_adapter.set_service(persistence)
    get_tree().root.call_deferred("add_child", persistence_adapter)

    # Register with runtime conformance checks (required methods list mirrors IFogService)
    registry.register("Fog", fog, ["reveal_area", "set_fog_enabled", "get_fog_state"])
    registry.register("FogAdapter", adapter)
    registry.register("Map", map, ["get_map", "load_map", "load_map_from_bundle"])
    registry.register("MapAdapter", map_adapter)
    registry.register("Network", net, ["start_server", "stop_server", "broadcast_to_displays", "send_to_display"])
    registry.register("NetworkAdapter", net_adapter)
    registry.register("GameState", gs, ["get_profile_by_id"])
    registry.register("GameStateAdapter", gs_adapter)
    registry.register("Profile", ps, ["get_profiles", "get_profile_by_id", "save_profiles", "load_profiles"])
    registry.register("ProfileAdapter", ps_adapter)
    registry.register("Persistence", persistence, ["save_game", "load_game", "list_saves", "delete_save", "export_to_path", "copy_file"])
    registry.register("PersistenceAdapter", persistence_adapter)

    print("ServiceBootstrap: registered Fog service and adapter")
