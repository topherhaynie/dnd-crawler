extends SceneTree

func _ready() -> void:
    # Load scripts explicitly to avoid class_name dependency during headless runs
    var ServiceRegistryScript: Script = load("res://scripts/core/ServiceRegistry.gd")
    var FogServiceScript: Script = load("res://scripts/services/fog/FogService.gd")

    var registry: Object = ServiceRegistryScript.new()
    registry.name = "ServiceRegistry"
    self.root.call_deferred("add_child", registry)

    var fog: Object = FogServiceScript.new()
    fog.name = "FogService"
    self.root.call_deferred("add_child", fog)

    # No adapter used in smoke test; register FogService directly

    # Register services
    registry.register("Fog", fog, ["reveal_area", "set_fog_enabled", "get_fog_state"])

    # Exercise API
    fog.reveal_area(Vector2(5, 10), 16.0)
    var state = fog.get_fog_state()
    if not state.has("revealed") or state.revealed.size() == 0:
        push_error("smoke_fog: reveal did not record state")
        self.quit(1)
        return

    fog.set_fog_enabled(false)
    var s2 = fog.get_fog_state()
    if s2.get("enabled", true) == true:
        push_error("smoke_fog: set_fog_enabled did not toggle state")
        self.quit(1)
        return

    print("smoke_fog: PASS")
    self.quit(0)
