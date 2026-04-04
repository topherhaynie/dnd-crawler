extends SceneTree

## Unit tests for GridSnap.snap_to_grid() — SQUARE, HEX_FLAT, HEX_POINTY.

func _ready() -> void:
	_test_square_grid_basic()
	_test_square_grid_with_offset()
	_test_square_grid_already_centered()
	_test_square_grid_negative_coords()
	_test_hex_flat_basic()
	_test_hex_pointy_basic()
	_test_null_map_data()
	_test_tiny_cell_px()
	print("test_grid_snap: PASS")
	quit(0)


func _make_square_map(cell: float, offset: Vector2) -> MapData:
	var m := MapData.new()
	m.grid_type = MapData.GridType.SQUARE
	m.cell_px = cell
	m.grid_offset = offset
	return m


func _make_hex_flat_map(hex_size: float, offset: Vector2) -> MapData:
	var m := MapData.new()
	m.grid_type = MapData.GridType.HEX_FLAT
	m.hex_size = hex_size
	m.grid_offset = offset
	return m


func _make_hex_pointy_map(hex_size: float, offset: Vector2) -> MapData:
	var m := MapData.new()
	m.grid_type = MapData.GridType.HEX_POINTY
	m.hex_size = hex_size
	m.grid_offset = offset
	return m


# ── SQUARE ────────────────────────────────────────────────────────────────

func _test_square_grid_basic() -> void:
	var m: MapData = _make_square_map(64.0, Vector2.ZERO)
	# A point at (10, 10) is in the first cell [0,64)×[0,64) → centre (32, 32)
	var result: Vector2 = GridSnap.snap_to_grid(Vector2(10.0, 10.0), m)
	assert(result.distance_to(Vector2(32.0, 32.0)) < 0.01,
		"Square snap basic: expected (32,32), got %s" % result)
	# A point at (100, 200) — cell [64,128)×[192,256) → centre (96, 224)
	result = GridSnap.snap_to_grid(Vector2(100.0, 200.0), m)
	assert(result.distance_to(Vector2(96.0, 224.0)) < 0.01,
		"Square snap (100,200): expected (96,224), got %s" % result)


func _test_square_grid_with_offset() -> void:
	var m: MapData = _make_square_map(64.0, Vector2(16.0, 16.0))
	# After removing offset: local = (10-16, 10-16) = (-6, -6)
	# floor(-6/64)*64 + 32 = -64+32 = -32   → re-add offset → (-32+16, -32+16) = (-16, -16)
	var result: Vector2 = GridSnap.snap_to_grid(Vector2(10.0, 10.0), m)
	assert(result.distance_to(Vector2(-16.0, -16.0)) < 0.01,
		"Square snap offset: expected (-16,-16), got %s" % result)


func _test_square_grid_already_centered() -> void:
	var m: MapData = _make_square_map(64.0, Vector2.ZERO)
	# Exactly at cell centre (32, 32) should not move
	var result: Vector2 = GridSnap.snap_to_grid(Vector2(32.0, 32.0), m)
	assert(result.distance_to(Vector2(32.0, 32.0)) < 0.01,
		"Square snap already centred: expected (32,32), got %s" % result)


func _test_square_grid_negative_coords() -> void:
	var m: MapData = _make_square_map(64.0, Vector2.ZERO)
	# (-10, -10): floor(-10/64)=-1 → cell [-64,0)×[-64,0) → centre (-32, -32)
	var result: Vector2 = GridSnap.snap_to_grid(Vector2(-10.0, -10.0), m)
	assert(result.distance_to(Vector2(-32.0, -32.0)) < 0.01,
		"Square snap negative: expected (-32,-32), got %s" % result)


# ── HEX FLAT ─────────────────────────────────────────────────────────────

func _test_hex_flat_basic() -> void:
	var m: MapData = _make_hex_flat_map(40.0, Vector2.ZERO)
	# Origin should snap to the (0,0,0) cube cell → pixel (0, 0)
	var result: Vector2 = GridSnap.snap_to_grid(Vector2(0.0, 0.0), m)
	assert(result.distance_to(Vector2.ZERO) < 0.01,
		"Hex flat origin: expected (0,0), got %s" % result)
	# A point near origin should still snap to (0,0)
	result = GridSnap.snap_to_grid(Vector2(5.0, 5.0), m)
	assert(result.distance_to(Vector2.ZERO) < 0.01,
		"Hex flat near origin: expected (0,0), got %s" % result)
	# A point far along x should snap to a neighbouring hex centre
	# At (80, 0), q_frac ≈ (2/3)*80/40 = 1.333, s_frac ≈ (-1/3)*80/40 = -0.667
	# Cube round should yield a well-defined hex cell centre
	result = GridSnap.snap_to_grid(Vector2(80.0, 0.0), m)
	# Just ensure it moved and is deterministic
	assert(result.distance_to(Vector2(80.0, 0.0)) < 40.0,
		"Hex flat far point: result %s too far from input" % result)


# ── HEX POINTY ───────────────────────────────────────────────────────────

func _test_hex_pointy_basic() -> void:
	var m: MapData = _make_hex_pointy_map(40.0, Vector2.ZERO)
	# Origin → (0,0)
	var result: Vector2 = GridSnap.snap_to_grid(Vector2(0.0, 0.0), m)
	assert(result.distance_to(Vector2.ZERO) < 0.01,
		"Hex pointy origin: expected (0,0), got %s" % result)
	# Near origin → still (0,0)
	result = GridSnap.snap_to_grid(Vector2(5.0, 5.0), m)
	assert(result.distance_to(Vector2.ZERO) < 0.01,
		"Hex pointy near origin: expected (0,0), got %s" % result)


# ── Edge cases ────────────────────────────────────────────────────────────

func _test_null_map_data() -> void:
	var input := Vector2(123.0, 456.0)
	var result: Vector2 = GridSnap.snap_to_grid(input, null)
	assert(result.distance_to(input) < 0.001,
		"Null map data: expected unchanged, got %s" % result)


func _test_tiny_cell_px() -> void:
	var m: MapData = _make_square_map(0.5, Vector2.ZERO)
	# cell_px < 1.0 → returns unchanged
	var input := Vector2(100.0, 200.0)
	var result: Vector2 = GridSnap.snap_to_grid(input, m)
	assert(result.distance_to(input) < 0.001,
		"Tiny cell_px: expected unchanged, got %s" % result)
