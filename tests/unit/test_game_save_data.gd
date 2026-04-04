extends SceneTree

## Unit tests for GameSaveData serialisation round-trip, focusing on active_profile_ids.

const _GameSaveDataClass = preload("res://scripts/services/game_state/models/GameSaveData.gd")


func _ready() -> void:
	_test_roundtrip_active_profile_ids()
	_test_roundtrip_empty_active_profile_ids()
	_test_roundtrip_player_positions_and_locks()
	print("test_game_save_data: PASS")
	quit(0)


func _test_roundtrip_active_profile_ids() -> void:
	var s: GameSaveData = _GameSaveDataClass.new()
	s.save_name = "test_session"
	s.active_profile_ids = ["p1", "p2", "p3"]
	s.player_positions = {"p1": Vector2(100.0, 200.0), "p2": Vector2(300.0, 400.0)}
	s.player_locked = {"p1": true, "p2": false}

	var d: Dictionary = s.to_dict()
	var restored: GameSaveData = _GameSaveDataClass.from_dict(d)

	assert(restored.active_profile_ids.size() == 3,
		"Expected 3 active profile ids, got %d" % restored.active_profile_ids.size())
	assert(restored.active_profile_ids[0] == "p1", "First id should be p1")
	assert(restored.active_profile_ids[1] == "p2", "Second id should be p2")
	assert(restored.active_profile_ids[2] == "p3", "Third id should be p3")


func _test_roundtrip_empty_active_profile_ids() -> void:
	var s: GameSaveData = _GameSaveDataClass.new()
	s.save_name = "empty_session"

	var d: Dictionary = s.to_dict()
	var restored: GameSaveData = _GameSaveDataClass.from_dict(d)

	assert(restored.active_profile_ids.is_empty(),
		"Empty active_profile_ids should stay empty after round-trip")


func _test_roundtrip_player_positions_and_locks() -> void:
	var s: GameSaveData = _GameSaveDataClass.new()
	s.active_profile_ids = ["p1"]
	s.player_positions = {"p1": Vector2(50.0, 75.0)}
	s.player_locked = {"p1": true}
	s.player_camera_position = Vector2(500.0, 600.0)
	s.player_camera_zoom = 2.5
	s.player_camera_rotation = 90

	var d: Dictionary = s.to_dict()
	var restored: GameSaveData = _GameSaveDataClass.from_dict(d)

	var pos: Variant = restored.player_positions.get("p1", null)
	assert(pos is Vector2, "Restored position should be Vector2")
	assert((pos as Vector2).is_equal_approx(Vector2(50.0, 75.0)),
		"Position mismatch: got %s" % str(pos))
	assert(restored.player_locked.get("p1", false) == true, "Lock should be true")
	assert(restored.player_camera_zoom == 2.5, "Zoom mismatch")
	assert(restored.player_camera_rotation == 90, "Rotation mismatch")
