extends Node

func _ready() -> void:
    var svc := preload("res://scripts/services/PersistenceService.gd").new()
    var ok := svc.save_game("test_save", {"a": 1, "b": "x"})
    assert(ok)
    var loaded := svc.load_game("test_save")
    assert(loaded is Dictionary)
    assert(int(loaded.get("a", 0)) == 1)
    var saves := svc.list_saves()
    assert(saves.has("test_save"))
    var tmp_export := ProjectSettings.globalize_path("user://data/saves/test_save_export.json")
    var exported := svc.export_to_path("test_save", tmp_export)
    assert(exported)
    # cleanup
    svc.delete_save("test_save")
    print("test_persistence: ok")
    get_tree().quit()
