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

var service: IFogService = null
var model: FogModel = null


func configure(size: Vector2i, is_dm: bool, enabled: bool) -> void:
	## Initialise or resize the history image to match the given map dimensions.
	## Always emits fog_changed so connected renderers re-seed from the model.
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


func reveal_brush(world_pos: Vector2, radius_px: float) -> void:
	if model == null or model.history_image == null or service == null:
		return
	service.apply_history_brush(model.history_image, world_pos, radius_px, true)
	fog_changed.emit()


func hide_brush(world_pos: Vector2, radius_px: float) -> void:
	if model == null or model.history_image == null or service == null:
		return
	service.apply_history_brush(model.history_image, world_pos, radius_px, false)
	fog_changed.emit()


func reveal_rect(a: Vector2, b: Vector2) -> void:
	if model == null or model.history_image == null or service == null:
		return
	service.apply_history_rect(model.history_image, a, b, true)
	fog_changed.emit()


func hide_rect(a: Vector2, b: Vector2) -> void:
	if model == null or model.history_image == null or service == null:
		return
	service.apply_history_rect(model.history_image, a, b, false)
	fog_changed.emit()


func apply_seed_delta(revealed_cells: Array, hidden_cells: Array, cell_px: int) -> void:
	if model == null or model.history_image == null or service == null:
		return
	if revealed_cells.is_empty() and hidden_cells.is_empty():
		return
	var changed := service.apply_history_seed_delta(
			model.history_image, revealed_cells, hidden_cells, maxi(1, cell_px))
	if changed:
		fog_changed.emit()


func seed_from_hidden(cell_px: int, hidden_cells: Dictionary) -> void:
	if model == null or model.history_image == null or service == null:
		return
	var res := service.set_history_seed_from_hidden(model.history_image, maxi(1, cell_px), hidden_cells)
	if res.get("changed", false):
		var updated: Variant = res.get("history_image", null)
		if updated is Image:
			model.history_image = updated as Image
		fog_changed.emit()
