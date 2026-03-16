extends Node

func _ready() -> void:
    # Load service scripts explicitly to avoid analyzer scope issues during headless/test runs.
    var ServiceRegistryScript: Script = load("res://scripts/registry/ServiceRegistry.gd")
    var FogServiceScript: Script = load("res://scripts/services/FogService.gd")
    var FogAdapterScript: Script = load("res://scripts/registry/FogAdapter.gd")
    var NetworkServiceScript: Script = load("res://scripts/services/NetworkService.gd")
    var NetworkAdapterScript: Script = load("res://scripts/registry/NetworkAdapter.gd")
    var GameStateServiceScript: Script = load("res://scripts/services/GameStateService.gd")
    var GameStateAdapterScript: Script = load("res://scripts/registry/GameStateAdapter.gd")

    var registry: ServiceRegistry = ServiceRegistryScript.new() as ServiceRegistry
    registry.name = "ServiceRegistry"
    get_tree().root.call_deferred("add_child", registry)

    var fog: FogService = FogServiceScript.new() as FogService
    fog.name = "FogService"
    get_tree().root.call_deferred("add_child", fog)

    var adapter: FogAdapter = FogAdapterScript.new() as FogAdapter
    adapter.name = "FogAdapter"
    if adapter.has_method("set_service"):
        adapter.set_service(fog)
    get_tree().root.call_deferred("add_child", adapter)

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

    # Register with runtime conformance checks (required methods list mirrors IFogService)
    registry.register("Fog", fog, ["reveal_area", "set_fog_enabled", "get_fog_state"])
    registry.register("FogAdapter", adapter)
    registry.register("Network", net, ["start_server", "stop_server", "broadcast_to_displays", "send_to_display"])
    registry.register("NetworkAdapter", net_adapter)
    registry.register("GameState", gs, ["get_profile_by_id"])
    registry.register("GameStateAdapter", gs_adapter)

    print("ServiceBootstrap: registered Fog service and adapter")
