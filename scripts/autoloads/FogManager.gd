extends Node

# ---------------------------------------------------------------------------
# FogManager — shared fog/vision sync helper.
#
# Stores the latest fog-state image (captured from the Fog SubViewport) and
# per-player vision scales so both DM and Player windows use the same values.
# ---------------------------------------------------------------------------

var _fog_state_image: Image = null
var _fog_state_png: PackedByteArray = PackedByteArray()
var _fog_state_size: Vector2i = Vector2i.ZERO
var _vision_scale_by_player_id: Dictionary = {}
const DEBUG_SAVE_CAPTURE_PNG: bool = false


func get_fog_state() -> PackedByteArray:
	return _fog_state_png.duplicate()


func set_fog_state(data: PackedByteArray) -> bool:
	if data.is_empty():
		_fog_state_image = null
		_fog_state_png = PackedByteArray()
		_fog_state_size = Vector2i.ZERO
		return false
	var image := Image.new()
	var err := image.load_png_from_buffer(data)
	if err != OK or image.is_empty():
		push_warning("FogManager: could not decode fog state PNG (err=%d bytes=%d)" % [err, data.size()])
		return false
	_fog_state_image = image
	_fog_state_png = data.duplicate()
	_fog_state_size = Vector2i(image.get_width(), image.get_height())
	return true


func capture_fog_state(viewport: SubViewport) -> PackedByteArray:
	return await get_compressed_fog_snapshot(viewport)


func get_compressed_fog_snapshot(viewport: SubViewport) -> PackedByteArray:
	if viewport == null:
		return PackedByteArray()
	# Cook phase: force the viewport to render this frame before readback.
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().process_frame
	var tex := viewport.get_texture()
	if tex == null:
		return PackedByteArray()
	var image := tex.get_image()
	if image == null or image.is_empty():
		return PackedByteArray()
	if DEBUG_SAVE_CAPTURE_PNG:
		# Optional debug capture for visual verification of DM-side snapshot readback.
		var save_err := image.save_png("user://last_captured_fog.png")
		if save_err != OK:
			push_warning("FogManager: failed to save debug capture user://last_captured_fog.png (err=%d)" % save_err)
	image.convert(Image.FORMAT_L8)
	_fog_state_image = image
	_fog_state_png = image.save_png_to_buffer()
	_fog_state_size = Vector2i(image.get_width(), image.get_height())
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return _fog_state_png.duplicate()


func get_fog_state_size() -> Vector2i:
	return _fog_state_size


func set_vision_scale(player_id: String, scale: float) -> float:
	var clamped := clampf(scale, 0.1, 4.0)
	if player_id.is_empty():
		return clamped
	_vision_scale_by_player_id[player_id] = clamped
	return clamped


func get_vision_scale(player_id: String, default_scale: float = 1.0) -> float:
	if player_id.is_empty():
		return clampf(default_scale, 0.1, 4.0)
	return clampf(float(_vision_scale_by_player_id.get(player_id, default_scale)), 0.1, 4.0)


func compute_dash_vision_scale(is_dashing: bool) -> float:
	return 0.5 if is_dashing else 1.0
