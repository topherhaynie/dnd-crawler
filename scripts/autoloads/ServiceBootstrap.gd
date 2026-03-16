extends Node

func _ready() -> void:
    # Load service scripts explicitly to avoid analyzer scope issues during headless/test runs.
    var ServiceRegistryScript: Script = load("res://scripts/registry/ServiceRegistry.gd")
    var FogServiceScript: Script = load("res://scripts/services/FogService.gd")
    var FogAdapterScript: Script = load("res://scripts/registry/FogAdapter.gd")

    var registry: ServiceRegistry = ServiceRegistryScript.new() as ServiceRegistry
    registry.name = "ServiceRegistry"
    get_tree().root.add_child(registry)

    var fog: FogService = FogServiceScript.new() as FogService
    fog.name = "FogService"
    get_tree().root.add_child(fog)

    var adapter: FogAdapter = FogAdapterScript.new() as FogAdapter
    adapter.name = "FogAdapter"
    if adapter.has_method("set_service"):
        adapter.set_service(fog)
    get_tree().root.add_child(adapter)

    # Register with runtime conformance checks (required methods list mirrors IFogService)
    registry.register("Fog", fog, ["reveal_area", "set_fog_enabled", "get_fog_state"])
    registry.register("FogAdapter", adapter)

    print("ServiceBootstrap: registered Fog service and adapter")
