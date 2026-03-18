extends Node

func _ready() -> void:
    # Load service scripts explicitly to avoid analyzer scope issues during headless/test runs.
    var ServiceRegistryScript: Script = load("res://scripts/registry/ServiceRegistry.gd")
    var FogServiceScript: Script = load("res://scripts/services/FogService.gd")
    var MapServiceScript: Script = load("res://scripts/services/MapService.gd")
    var NetworkServiceScript: Script = load("res://scripts/services/NetworkService.gd")
    var GameStateServiceScript: Script = load("res://scripts/services/GameStateService.gd")
    var ProfileServiceScript: Script = load("res://scripts/services/ProfileService.gd")
    var PersistenceServiceScript: Script = load("res://scripts/services/PersistenceService.gd")
    var InputServiceScript: Script = load("res://scripts/services/InputService.gd")

    var registry: ServiceRegistry = ServiceRegistryScript.new() as ServiceRegistry
    registry.name = "ServiceRegistry"
    get_tree().root.call_deferred("add_child", registry)

    var fog: FogService = FogServiceScript.new() as FogService
    fog.name = "FogService"
    get_tree().root.call_deferred("add_child", fog)

    var map: MapService = MapServiceScript.new() as MapService
    map.name = "MapService"
    get_tree().root.call_deferred("add_child", map)

    # Adapters removed: services are now authoritative implementations.

    var net: Node = NetworkServiceScript.new() as Node
    net.name = "NetworkService"
    get_tree().root.call_deferred("add_child", net)

    # Network adapter removed

    var gs: Node = GameStateServiceScript.new() as Node
    gs.name = "GameStateService"
    get_tree().root.call_deferred("add_child", gs)

    # GameState adapter removed

    var ps: Node = ProfileServiceScript.new() as Node
    ps.name = "ProfileService"
    get_tree().root.call_deferred("add_child", ps)

    # Profile adapter removed

    var persistence = PersistenceServiceScript.new()
    persistence.name = "PersistenceService"
    get_tree().root.call_deferred("add_child", persistence)

    # Persistence adapter removed

    var input = InputServiceScript.new()
    input.name = "InputService"
    get_tree().root.call_deferred("add_child", input)

    # Register with runtime conformance checks (required methods list mirrors IFogService)
    registry.register("Fog", fog, ["reveal_area", "set_fog_enabled", "get_fog_state", "get_fog_state_size", "set_fog_state"])
    registry.register("Map", map, ["get_map", "load_map", "load_map_from_bundle"])
    registry.register("Network", net, ["start_server", "stop_server", "broadcast_to_displays", "send_to_display"])
    registry.register("GameState", gs, ["get_profile_by_id"])
    registry.register("Profile", ps, ["get_profiles", "get_profile_by_id", "save_profiles", "load_profiles"])
    registry.register("Persistence", persistence, ["save_game", "load_game", "list_saves", "delete_save", "export_to_path", "copy_file"])
    registry.register("Input", input, ["get_vector", "set_network_vector", "set_gamepad_vector", "set_dm_vector", "bind_gamepad", "unbind_gamepad", "bind_peer", "clear_all_bindings", "get_gamepad_bindings", "has_gamepad_binding"])

    print("ServiceBootstrap: registered Fog service and adapter")
