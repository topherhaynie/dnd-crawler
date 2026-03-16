extends SceneTree

func _ready() -> void:
    var FogScript: Script = load("res://scripts/services/FogService.gd")
    assert(FogScript != null)
    var fog: Object = FogScript.new()
    # initial state
    var s: Dictionary = fog.get_fog_state()
    assert(s.has("enabled"))

    # reveal area should record a reveal
    fog.reveal_area(Vector2(10, 20), 32.0)
    s = fog.get_fog_state() as Dictionary
    assert(s.has("revealed"))
    assert(s.revealed.size() == 1)

    # toggle enabled
    fog.set_fog_enabled(false)
    s = fog.get_fog_state() as Dictionary
    assert(s.enabled == false)

    print("test_fog_service: PASS")
    # Quit with success code
    self.quit(0)
