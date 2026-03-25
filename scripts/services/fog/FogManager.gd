extends RefCounted
class_name FogManager

## FogManager — domain coordinator for fog-of-war.
##
## Owns FogModel (CPU-side history image) and exposes high-level operations
## that mutate the image via IFogService, then emit fog_changed so connected
## renderers (FogSystem) can re-seed the GPU pipeline.
##
## Access via: get_node("/root/ServiceRegistry").fog


signal fog_changed
signal fog_enabled_changed(is_enabled: bool)
signal fog_stroke_applied(stroke: Dictionary)

var service: IFogService = null
var model: FogModel = null
var _pending_strokes: Array = []


func configure(size: Vector2i, is_dm: bool, enabled: bool) -> void:
	## Initialise or resize the history image to match the given (possibly scaled)
	## map dimensions.
	if model == null:
		model = FogModel.new()
	model.is_dm = is_dm
	var enabled_changed := model.enabled != enabled
	model.enabled = enabled
	var target_size := Vector2i(maxi(1, size.x), maxi(1, size.y))
	if model.history_image == null or model.history_image.is_empty() \
			or model.size != target_size:
		model.history_image = Image.create(target_size.x, target_size.y, false, Image.FORMAT_L8)
		model.history_image.fill(Color(0.0, 0.0, 0.0, 1.0))
		model.size = target_size
	fog_changed.emit()
	if enabled_changed:
		fog_enabled_changed.emit(enabled)


func set_fog_scale(scale: float) -> void:
	## Store the world-to-fog-image ratio so brush/rect operations can
	## convert world coordinates to image coordinates.
	if model == null:
		model = FogModel.new()
	model.fog_scale = scale


func reset() -> void:
	## Fill the history image black (fully hidden) and emit fog_changed.
	if model == null or model.history_image == null:
		return
	model.history_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	fog_changed.emit()


func set_enabled(enabled: bool) -> void:
	if model == null:
		model = FogModel.new()
	if model.enabled == enabled:
		return
	model.enabled = enabled
	fog_enabled_changed.emit(enabled)


func apply_snapshot(buffer: PackedByteArray) -> bool:
	## Decode a PNG fog snapshot, update the model image, and emit fog_changed.
	if buffer.is_empty():
		return false
	if model == null:
		model = FogModel.new()
	var image := Image.new()
	var err := image.load_png_from_buffer(buffer)
	if err != OK or image.is_empty():
		push_warning("FogManager: apply_snapshot failed to decode PNG (err=%d bytes=%d)" % [err, buffer.size()])
		return false
	image.convert(Image.FORMAT_L8)
	if model.history_image != null and not model.history_image.is_empty() \
			and (image.get_width() != model.history_image.get_width() \
			or image.get_height() != model.history_image.get_height()):
		image.resize(model.history_image.get_width(), model.history_image.get_height(), Image.INTERPOLATE_NEAREST)
	model.history_image = image
	model.size = Vector2i(image.get_width(), image.get_height())
	if service != null:
		service.set_fog_state(buffer)
	fog_changed.emit()
	return true


func sync_model_from_gpu(buffer: PackedByteArray) -> void:
	## Update the CPU model image from a GPU readback without emitting
	## fog_changed — prevents a re-seed loop when the DM snapshots its own
	## GPU state for broadcast.
	if buffer.is_empty():
		return
	if model == null:
		model = FogModel.new()
	var image := Image.new()
	var err := image.load_png_from_buffer(buffer)
	if err != OK or image.is_empty():
		return
	image.convert(Image.FORMAT_L8)
	if model.history_image != null and not model.history_image.is_empty() \
			and (image.get_width() != model.history_image.get_width() \
			or image.get_height() != model.history_image.get_height()):
		image.resize(model.history_image.get_width(), model.history_image.get_height(), Image.INTERPOLATE_NEAREST)
	model.history_image = image
	model.size = Vector2i(image.get_width(), image.get_height())


func reveal_brush(world_pos: Vector2, radius_px: float) -> void:
	if model == null or model.history_image == null or service == null:
		return
	var s := model.fog_scale
	service.apply_history_brush(model.history_image, world_pos * s, radius_px * s, true)
	fog_stroke_applied.emit({"type": "brush", "center": world_pos, "radius": radius_px, "reveal": true})


func hide_brush(world_pos: Vector2, radius_px: float) -> void:
	if model == null or model.history_image == null or service == null:
		return
	var s := model.fog_scale
	service.apply_history_brush(model.history_image, world_pos * s, radius_px * s, false)
	fog_stroke_applied.emit({"type": "brush", "center": world_pos, "radius": radius_px, "reveal": false})


func queue_gpu_brush(world_pos: Vector2, radius_px: float, reveal: bool) -> void:
	## Send a brush stroke to the GPU immediately without the CPU pixel loop.
	## Call flush_pending_strokes() when the drag ends to update the CPU model.
	var stroke := {"type": "brush", "center": world_pos, "radius": radius_px, "reveal": reveal}
	_pending_strokes.append(stroke)
	fog_stroke_applied.emit(stroke)


func flush_pending_strokes() -> void:
	## Batch-apply all queued GPU strokes to the CPU history image.
	if model == null or model.history_image == null or service == null:
		_pending_strokes.clear()
		return
	if _pending_strokes.is_empty():
		return
	var s := model.fog_scale
	for raw in _pending_strokes:
		var stroke := raw as Dictionary
		var stype: String = str(stroke.get("type", ""))
		var reveal: bool = bool(stroke.get("reveal", true))
		if stype == "brush":
			var center := stroke.get("center", Vector2.ZERO) as Vector2
			var radius: float = float(stroke.get("radius", 0.0))
			service.apply_history_brush(model.history_image, center * s, radius * s, reveal)
		elif stype == "rect":
			var a := stroke.get("a", Vector2.ZERO) as Vector2
			var b := stroke.get("b", Vector2.ZERO) as Vector2
			service.apply_history_rect(model.history_image, a * s, b * s, reveal)
	_pending_strokes.clear()


func reveal_rect(a: Vector2, b: Vector2) -> void:
	if model == null or model.history_image == null or service == null:
		return
	var s := model.fog_scale
	service.apply_history_rect(model.history_image, a * s, b * s, true)
	fog_stroke_applied.emit({"type": "rect", "a": a, "b": b, "reveal": true})


func hide_rect(a: Vector2, b: Vector2) -> void:
	if model == null or model.history_image == null or service == null:
		return
	var s := model.fog_scale
	service.apply_history_rect(model.history_image, a * s, b * s, false)
	fog_stroke_applied.emit({"type": "rect", "a": a, "b": b, "reveal": false})


func get_fog_state() -> PackedByteArray:
	if service == null:
		return PackedByteArray()
	return service.get_fog_state()


func get_fog_state_size() -> Vector2i:
	if service == null:
		return Vector2i.ZERO
	return service.get_fog_state_size()


func apply_seed_delta(revealed_cells: Array, hidden_cells: Array, cell_px: int) -> void:
	if model == null or model.history_image == null or service == null:
		return
	if revealed_cells.is_empty() and hidden_cells.is_empty():
		return
	# Scale the cell grid pitch into fog-image space.
	var scaled_cell := maxi(1, roundi(float(maxi(1, cell_px)) * model.fog_scale))
	var changed := service.apply_history_seed_delta(
			model.history_image, revealed_cells, hidden_cells, scaled_cell)
	if changed:
		fog_changed.emit()


func seed_from_hidden(cell_px: int, hidden_cells: Dictionary) -> void:
	if model == null or model.history_image == null or service == null:
		return
	var scaled_cell := maxi(1, roundi(float(maxi(1, cell_px)) * model.fog_scale))
	var res := service.set_history_seed_from_hidden(model.history_image, scaled_cell, hidden_cells)
	if res.get("changed", false):
		var updated: Variant = res.get("history_image", null)
		if updated is Image:
			model.history_image = updated as Image
		fog_changed.emit()
