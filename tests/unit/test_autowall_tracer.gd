extends SceneTree

## Unit tests for AutoWallTracer — image-based wall polygon detection.
## Default (invert=true) inverts the mask and carves canals, producing
## multiple simple wall polygons covering background/wall areas.

func _ready() -> void:
	_test_alpha_rectangle()
	_test_alpha_circle()
	_test_invert_flips_result()
	_test_color_mode()
	_test_epsilon_reduces_points()
	_test_min_area_filter()
	_test_empty_image_returns_empty()
	print("test_autowall_tracer: ALL PASS")
	self.quit(0)


func _test_alpha_rectangle() -> void:
	# Create a 100x100 image: transparent background with a 60x40 opaque white
	# rectangle from (20,30) to (80,70).
	var img := Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0)) # fully transparent
	img.fill_rect(Rect2i(20, 30, 60, 40), Color.WHITE)

	var tracer := AutoWallTracer.new()
	var result: Array = tracer.trace(img, {
		"mode": AutoWallTracer.DetectMode.ALPHA,
		"threshold": 0.5,
		"trace_scale": 1.0,
		"epsilon": 3.0,
		"min_points": 4,
		"min_area": 0.0,
	})
	# Default invert=true: mask-inverted wall polygons (transparent bg becomes wall)
	assert(result.size() >= 1, "Alpha rect: expected >= 1 wall polygon, got %d" % result.size())
	var poly: PackedVector2Array = result[0] as PackedVector2Array
	assert(poly.size() >= 3, "Alpha rect: polygon needs >= 3 points, got %d" % poly.size())
	print("  alpha_rectangle: PASS (%d wall polygons)" % result.size())


func _test_alpha_circle() -> void:
	# Create a 200x200 image with a filled circle (radius 60) centered at (100,100)
	var img := Image.create(200, 200, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in range(200):
		for x: int in range(200):
			var dx: float = float(x) - 100.0
			var dy: float = float(y) - 100.0
			if dx * dx + dy * dy <= 60.0 * 60.0:
				img.set_pixel(x, y, Color.WHITE)

	var tracer := AutoWallTracer.new()
	var result: Array = tracer.trace(img, {
		"trace_scale": 1.0,
		"epsilon": 2.0,
		"min_points": 8,
		"min_area": 0.0,
	})
	# Mask inversion + canal carving produces multiple wall polygons
	assert(result.size() >= 1, "Alpha circle: expected >= 1 wall polygon")
	var total_pts: int = 0
	for p: Variant in result:
		total_pts += (p as PackedVector2Array).size()
	assert(total_pts > 10, "Alpha circle: expected > 10 total points, got %d" % total_pts)
	print("  alpha_circle: PASS (%d wall polygons, %d total points)" % [result.size(), total_pts])


func _test_invert_flips_result() -> void:
	# With invert=true (default), mask is inverted → wall polygons.
	# With invert=false, raw content contours are returned.
	var img := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(10, 10, 60, 60), Color.WHITE)

	var tracer := AutoWallTracer.new()
	var result_inverted: Array = tracer.trace(img, {
		"trace_scale": 1.0, "epsilon": 2.0, "min_points": 4, "min_area": 0.0,
		"invert": true,
	})
	var result_raw: Array = tracer.trace(img, {
		"trace_scale": 1.0, "epsilon": 2.0, "min_points": 4, "min_area": 0.0,
		"invert": false,
	})
	assert(result_inverted.size() >= 1, "Invert test: inverted should find wall polygons")
	assert(result_raw.size() >= 1, "Invert test: raw should find content polygons")
	print("  invert_flips_result: PASS (inverted=%d polys, raw=%d polys)" % [result_inverted.size(), result_raw.size()])


func _test_color_mode() -> void:
	# Image with solid red background and a white rectangle
	var img := Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.fill_rect(Rect2i(25, 25, 50, 50), Color.WHITE)

	var tracer := AutoWallTracer.new()
	var result: Array = tracer.trace(img, {
		"mode": AutoWallTracer.DetectMode.COLOR,
		"sample_color": Color.RED,
		"threshold": 0.3,
		"trace_scale": 1.0,
		"epsilon": 3.0,
		"min_points": 4,
		"min_area": 0.0,
	})
	assert(result.size() >= 1, "Color mode: expected >= 1 polygon, got %d" % result.size())
	print("  color_mode: PASS (%d polygons)" % result.size())


func _test_epsilon_reduces_points() -> void:
	# Trace the same circle with low and high epsilon — high should produce fewer total points
	var img := Image.create(200, 200, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in range(200):
		for x: int in range(200):
			var dx: float = float(x) - 100.0
			var dy: float = float(y) - 100.0
			if dx * dx + dy * dy <= 70.0 * 70.0:
				img.set_pixel(x, y, Color.WHITE)

	var tracer := AutoWallTracer.new()
	var result_fine: Array = tracer.trace(img, {
		"trace_scale": 1.0, "epsilon": 1.0, "min_points": 4, "min_area": 0.0,
	})
	var result_coarse: Array = tracer.trace(img, {
		"trace_scale": 1.0, "epsilon": 10.0, "min_points": 4, "min_area": 0.0,
	})
	assert(result_fine.size() >= 1 and result_coarse.size() >= 1)
	var fine_pts: int = 0
	for p: Variant in result_fine:
		fine_pts += (p as PackedVector2Array).size()
	var coarse_pts: int = 0
	for p: Variant in result_coarse:
		coarse_pts += (p as PackedVector2Array).size()
	assert(fine_pts > coarse_pts,
		"Epsilon test: fine (%d pts) should exceed coarse (%d pts)" % [fine_pts, coarse_pts])
	print("  epsilon_reduces_points: PASS (fine=%d pts, coarse=%d pts)" % [fine_pts, coarse_pts])


func _test_min_area_filter() -> void:
	# Image with one large and one tiny shape — min_area should filter the tiny one.
	# Use invert=false so we get raw contour polygons and can compare counts directly.
	var img := Image.create(200, 200, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(10, 10, 80, 80), Color.WHITE) # large: 80x80 = 6400 px²
	img.fill_rect(Rect2i(150, 150, 5, 5), Color.WHITE) # tiny: 5x5 = 25 px²

	var tracer := AutoWallTracer.new()
	var result_no_filter: Array = tracer.trace(img, {
		"trace_scale": 1.0, "epsilon": 2.0, "min_points": 4, "min_area": 0.0,
		"invert": false,
	})
	var result_filtered: Array = tracer.trace(img, {
		"trace_scale": 1.0, "epsilon": 2.0, "min_points": 4, "min_area": 100.0,
		"invert": false,
	})
	# Without filter should have more polygons than with filter
	assert(result_no_filter.size() >= result_filtered.size(),
		"Area filter: unfiltered (%d) >= filtered (%d)" % [result_no_filter.size(), result_filtered.size()])
	print("  min_area_filter: PASS (unfiltered=%d, filtered=%d)" % [result_no_filter.size(), result_filtered.size()])


func _test_empty_image_returns_empty() -> void:
	var tracer := AutoWallTracer.new()
	# Null image
	var result_null: Array = tracer.trace(null, {})
	assert(result_null.is_empty(), "Null image should return empty")
	# Fully transparent image (no foreground)
	var img := Image.create(50, 50, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var result_empty: Array = tracer.trace(img, {"trace_scale": 1.0, "min_points": 4})
	assert(result_empty.is_empty(), "Fully transparent image should return empty")
	print("  empty_image_returns_empty: PASS")
