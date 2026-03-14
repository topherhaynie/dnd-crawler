extends SceneTree

func _initialize() -> void:
	randomize()
	var FogTruthCodecScript: Script = load("res://scripts/tools/FogTruthCodec.gd")
	if FogTruthCodecScript == null:
		printerr("FogTruthCodecTest: failed to load codec")
		quit(2)
		return

	var map_size := Vector2(1920, 1080)
	var cell_px := 4
	var trials := 12
	var exact_failures := 0
	var sampled_failures := 0
	var blurred_failures := 0
	var max_blur_mismatch := 0
	var max_offset_mismatch := 0

	for t in range(trials):
		var hidden := _random_hidden(map_size, cell_px, 0.58)
		var grid_img: Image = FogTruthCodecScript.call("hidden_to_grid_image", map_size, cell_px, hidden)
		var roundtrip: Dictionary = FogTruthCodecScript.call("grid_image_to_hidden", grid_img, 0.5)
		var mismatch_exact: int = int(FogTruthCodecScript.call("hidden_mismatch_count", hidden, roundtrip))
		if mismatch_exact != 0:
			exact_failures += 1

		# Build a full-res mask exactly like a seeded truth texture stretched to map size.
		var full_res := grid_img.duplicate()
		full_res.resize(int(map_size.x), int(map_size.y), Image.INTERPOLATE_NEAREST)
		var sampled_roundtrip: Dictionary = FogTruthCodecScript.call("sampled_mask_to_hidden", full_res, map_size, cell_px, 0.5)
		var mismatch_sampled: int = int(FogTruthCodecScript.call("hidden_mismatch_count", hidden, sampled_roundtrip))
		if mismatch_sampled != 0:
			sampled_failures += 1

		# Simulate lossy filter path (linear shrink+expand) to expose info loss risk.
		var blurred := full_res.duplicate()
		blurred.resize(int(map_size.x / 2.0), int(map_size.y / 2.0), Image.INTERPOLATE_BILINEAR)
		blurred.resize(int(map_size.x), int(map_size.y), Image.INTERPOLATE_BILINEAR)
		var blurred_roundtrip: Dictionary = FogTruthCodecScript.call("sampled_mask_to_hidden", blurred, map_size, cell_px, 0.5)
		var mismatch_blur: int = int(FogTruthCodecScript.call("hidden_mismatch_count", hidden, blurred_roundtrip))
		if mismatch_blur != 0:
			blurred_failures += 1
			max_blur_mismatch = maxi(max_blur_mismatch, mismatch_blur)

		# Simulate UV/pixel alignment drift by sampling half a cell to the right.
		var offset_roundtrip: Dictionary = FogTruthCodecScript.call(
			"sampled_mask_to_hidden_with_offset",
			full_res,
			map_size,
			cell_px,
			Vector2(float(cell_px) * 0.5, 0.0),
			0.5
		)
		var mismatch_offset: int = int(FogTruthCodecScript.call("hidden_mismatch_count", hidden, offset_roundtrip))
		max_offset_mismatch = maxi(max_offset_mismatch, mismatch_offset)

	var checker_hidden := _checker_hidden(map_size, cell_px)
	var checker_grid: Image = FogTruthCodecScript.call("hidden_to_grid_image", map_size, cell_px, checker_hidden)
	var checker_full := checker_grid.duplicate()
	checker_full.resize(int(map_size.x), int(map_size.y), Image.INTERPOLATE_BILINEAR)
	var checker_center: Dictionary = FogTruthCodecScript.call("sampled_mask_to_hidden", checker_full, map_size, cell_px, 0.5)
	var checker_center_mismatch: int = int(FogTruthCodecScript.call("hidden_mismatch_count", checker_hidden, checker_center))
	var checker_offset: Dictionary = FogTruthCodecScript.call(
		"sampled_mask_to_hidden_with_offset",
		checker_full,
		map_size,
		cell_px,
		Vector2(float(cell_px) * 0.5, 0.0),
		0.5
	)
	var checker_offset_mismatch: int = int(FogTruthCodecScript.call("hidden_mismatch_count", checker_hidden, checker_offset))

	print("FogTruthCodecTest results:")
	print("- exact grid roundtrip failures: %d / %d" % [exact_failures, trials])
	print("- nearest full-res sampled failures: %d / %d" % [sampled_failures, trials])
	print("- bilinear-filtered sampled failures: %d / %d" % [blurred_failures, trials])
	print("- max mismatch after bilinear filter: %d" % max_blur_mismatch)
	print("- max mismatch with +0.5 cell x offset: %d" % max_offset_mismatch)
	print("- checker mismatch (center sample): %d" % checker_center_mismatch)
	print("- checker mismatch (+0.5 cell x offset): %d" % checker_offset_mismatch)
	quit(0)


func _random_hidden(map_size: Vector2, cell_px: int, hide_ratio: float) -> Dictionary:
	var out: Dictionary = {}
	var safe_cell := maxi(1, cell_px)
	var gw := maxi(1, ceili(map_size.x / float(safe_cell)))
	var gh := maxi(1, ceili(map_size.y / float(safe_cell)))
	for y in range(gh):
		for x in range(gw):
			if randf() < hide_ratio:
				out[Vector2i(x, y)] = true
	return out


func _checker_hidden(map_size: Vector2, cell_px: int) -> Dictionary:
	var out: Dictionary = {}
	var safe_cell := maxi(1, cell_px)
	var gw := maxi(1, ceili(map_size.x / float(safe_cell)))
	var gh := maxi(1, ceili(map_size.y / float(safe_cell)))
	for y in range(gh):
		for x in range(gw):
			if ((x + y) % 2) == 0:
				out[Vector2i(x, y)] = true
	return out
