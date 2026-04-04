extends SceneTree

## Unit tests for TokenData creation, size_ft, and serialisation round-trip.

func _ready() -> void:
	_test_create_monster_has_size_ft()
	_test_create_generic_no_size_ft()
	_test_roundtrip_size_ft()
	_test_roundtrip_legacy_no_size_ft()
	print("test_token_data: PASS")
	quit(0)


func _test_create_monster_has_size_ft() -> void:
	var td: TokenData = TokenData.create(TokenData.TokenCategory.MONSTER, Vector2(100.0, 200.0), "Goblin")
	assert(td.size_ft == 5.0, "Monster token should default size_ft=5.0, got %f" % td.size_ft)
	assert(td.category == TokenData.TokenCategory.MONSTER, "Category mismatch")


func _test_create_generic_no_size_ft() -> void:
	var td: TokenData = TokenData.create(TokenData.TokenCategory.GENERIC, Vector2.ZERO)
	assert(td.size_ft == 0.0, "Generic token should default size_ft=0.0, got %f" % td.size_ft)


func _test_roundtrip_size_ft() -> void:
	var td: TokenData = TokenData.create(TokenData.TokenCategory.NPC, Vector2(50.0, 50.0), "Merchant")
	td.size_ft = 10.0
	td.width_px = 128.0
	td.height_px = 128.0
	var d: Dictionary = td.to_dict()
	assert(float(d.get("size_ft", 0.0)) == 10.0, "to_dict should include size_ft=10.0")
	var restored: TokenData = TokenData.from_dict(d)
	assert(restored.size_ft == 10.0, "from_dict should restore size_ft=10.0, got %f" % restored.size_ft)
	assert(restored.width_px == 128.0, "from_dict should restore width_px=128.0")
	assert(restored.height_px == 128.0, "from_dict should restore height_px=128.0")


func _test_roundtrip_legacy_no_size_ft() -> void:
	# Old map.json without size_ft should default to 0.0
	var d: Dictionary = {
		"id": "test_legacy",
		"label": "Old Door",
		"category": TokenData.TokenCategory.DOOR,
		"world_pos": {"x": 10.0, "y": 20.0},
		"width_px": 64.0,
		"height_px": 64.0,
	}
	var td: TokenData = TokenData.from_dict(d)
	assert(td.size_ft == 0.0, "Legacy token without size_ft should default to 0.0, got %f" % td.size_ft)
	assert(td.width_px == 64.0, "Legacy width_px should be preserved")
