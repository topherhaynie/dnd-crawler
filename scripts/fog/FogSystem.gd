extends Node2D
class_name FogSystem

const VISION_LAYER_MASK: int = 2
const PLAYER_ALPHA_SCALE: float = 1.00
const DM_HISTORY_ALPHA_SCALE: float = 0.80
const LIVE_LIGHT_ENERGY_GAIN: float = 8.0
const LIVE_LIGHT_MIN_ENERGY: float = 10.0
const LIVE_MASK_GAIN: float = 6.0
const LOS_BAKE_GAIN: float = 4.0
const DEBUG_FOG_TELEMETRY: bool = false
const LOS_BAKE_INTERVAL_MSEC: int = 0
const LIGHT_MOVE_EPSILON_PX: float = 0.0
const MIN_LIGHT_RADIUS_PX: float = 12.0
const MAX_LIGHT_RADIUS_PX: float = 320.0
const DIRTY_REGION_MERGE_PADDING_PX: int = 12
const MAX_DIRTY_REGIONS: int = 12

var _map_size: Vector2 = Vector2(1920, 1080)
var _is_dm: bool = true
var _fog_enabled: bool = false

var _history_image: Image = null
var _history_texture: Texture2D = null
var _history_dirty: bool = false
var _prev_los_data: PackedByteArray = PackedByteArray()
var _prev_los_width: int = 0
var _prev_los_height: int = 0
var _history_seed_cell_px: int = 1
var _history_viewports: Array = []
var _history_merge_rects: Array = []
var _history_active_index: int = 0
var _history_swap_pending: bool = false
var _history_pending_target_index: int = -1
var _history_seed_texture: ImageTexture = null
var _history_gpu_ready: bool = false
var _history_seed_pending: bool = false

var _mask_host: SubViewportContainer = null
var _live_lights_viewport: SubViewport = null
var _live_base_rect: ColorRect = null
var _live_light_rect: ColorRect = null
var _live_occluder_layer: Node2D = null

var _fog_rect: ColorRect = null
var _radial_texture: Texture2D = null

var _live_light_by_token_id: Dictionary = {}
var _live_light_state_by_token_id: Dictionary = {}
var _fallback_black_texture: ImageTexture = null
var _debug_los_bakes_frame: int = 0
var _debug_last_metrics_msec: int = 0
var _los_bake_pending: bool = true
var _last_los_bake_msec: int = 0
var _los_dirty_regions: Array = []


func _fog_service() -> IFogService:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null:
		return null
	if registry.fog == null:
		return null
	return registry.fog.service


func _ready() -> void:
	_build_nodes()
	if _live_lights_viewport:
		_live_lights_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_apply_shader_uniforms()
	_verify_live_viewport_no_camera()
	if DEBUG_FOG_TELEMETRY:
		print("FogSystem: ready (is_dm=%s map_size=%s viewport=%s)" % [
			str(_is_dm),
			str(_map_size),
			str(_live_lights_viewport.size if _live_lights_viewport else Vector2i.ZERO),
		])
	set_process(true)


func _process(_delta: float) -> void:
	if not _fog_enabled:
		return
	if _history_swap_pending and _history_pending_target_index >= 0:
		_history_active_index = _history_pending_target_index
		_history_pending_target_index = -1
		_history_swap_pending = false
		_apply_shader_uniforms()
	if _history_seed_pending:
		_history_seed_pending = false
		_apply_shader_uniforms()
	if _history_dirty:
		_upload_history_texture()
	if _should_bake_los_now():
		_bake_live_los_into_history()
	if DEBUG_FOG_TELEMETRY:
		_log_debug_metrics()


func configure(map_size: Vector2, is_dm: bool, enabled: bool) -> void:
	_map_size = Vector2(maxf(1.0, map_size.x), maxf(1.0, map_size.y))
	_is_dm = is_dm
	_fog_enabled = enabled
	if _mask_host == null:
		_build_nodes()
	_resize_buffers_and_nodes()
	_apply_shader_uniforms()
	if _live_lights_viewport:
		_live_lights_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _fog_enabled else SubViewport.UPDATE_DISABLED
	_queue_los_full_bake()
	if DEBUG_FOG_TELEMETRY:
		print("FogSystem: configure (is_dm=%s fog_enabled=%s map_size=%s viewport=%s)" % [
			str(_is_dm),
			str(_fog_enabled),
			str(_map_size),
			str(_live_lights_viewport.size if _live_lights_viewport else Vector2i.ZERO),
		])

# These are necessary, but I don't know why.
func get_fog_state() -> PackedByteArray:
	if _history_gpu_ready:
		if _history_swap_pending or _history_seed_pending:
			await get_tree().process_frame
			if _history_swap_pending and _history_pending_target_index >= 0:
				_history_active_index = _history_pending_target_index
				_history_pending_target_index = -1
				_history_swap_pending = false
			if _history_seed_pending:
				_history_seed_pending = false
			_apply_shader_uniforms()
		var live_tex := _get_active_history_texture()
		if live_tex:
			var image := live_tex.get_image()
			if image and not image.is_empty():
				image.convert(Image.FORMAT_L8)
				return image.save_png_to_buffer()
	if _history_image == null or _history_image.is_empty():
		return PackedByteArray()
	return _history_image.save_png_to_buffer()


func set_fog_state(data: PackedByteArray) -> bool:
	return apply_fog_snapshot(data)


func apply_fog_snapshot(buffer: PackedByteArray) -> bool:
	if buffer.is_empty():
		return false
	var image := Image.new()
	var err := image.load_png_from_buffer(buffer)
	if err != OK or image.is_empty():
		push_warning("FogSystem: apply_fog_snapshot failed to decode PNG (err=%d bytes=%d)" % [err, buffer.size()])
		return false
	image.convert(Image.FORMAT_L8)
	_ensure_history_storage(_map_size)
	if _history_image == null:
		return false
	if image.get_width() != _history_image.get_width() or image.get_height() != _history_image.get_height():
		image.resize(_history_image.get_width(), _history_image.get_height(), Image.INTERPOLATE_NEAREST)
	_history_image = image
	if _history_gpu_ready:
		_seed_gpu_history_from_image(image)
	else:
		_history_dirty = true
	_prev_los_data = PackedByteArray()
	_prev_los_width = 0
	_prev_los_height = 0
	return true


func reset_history() -> void:
	_ensure_history_storage(_map_size)
	if _history_image == null:
		return
	_history_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	_prev_los_data = PackedByteArray()
	_prev_los_width = 0
	_prev_los_height = 0
	if _history_gpu_ready:
		_seed_gpu_history_from_image(_history_image)
	else:
		_history_dirty = true
	_queue_los_full_bake()


func set_history_seed_from_hidden(cell_px: int, hidden_cells: Dictionary) -> void:
	_ensure_history_storage(_map_size)
	if _history_image == null or _history_image.is_empty():
		return

	var svc := _fog_service()
	if svc == null:
		return
	var res := svc.set_history_seed_from_hidden(_history_image, cell_px, hidden_cells)
	if res.is_empty():
		return
	_history_image = res.get("history_image", _history_image) as Image
	_history_seed_cell_px = int(res.get("seed_cell_px", _history_seed_cell_px))
	_prev_los_data = PackedByteArray()
	_prev_los_width = 0
	_prev_los_height = 0
	if _history_gpu_ready:
		_seed_gpu_history_from_image(_history_image)
	else:
		_history_dirty = true
	_queue_los_full_bake()


func apply_history_seed_delta(revealed_cells: Array, hidden_cells: Array, cell_px: int = -1) -> void:
	_ensure_history_storage(_map_size)
	if _history_image == null or _history_image.is_empty():
		return
	if revealed_cells.is_empty() and hidden_cells.is_empty():
		return

	var safe_cell_px := maxi(1, cell_px if cell_px > 0 else _history_seed_cell_px)
	var svc := _fog_service()
	if svc == null:
		return
	var changed := svc.apply_history_seed_delta(_history_image, revealed_cells, hidden_cells, safe_cell_px)
	if changed:
		_history_dirty = true


func sync_player_revealers(tokens: Array) -> void:
	if _live_lights_viewport == null or not _fog_enabled:
		return
	var seen_ids: Dictionary = {}
	for raw_token in tokens:
		if not raw_token is Node2D:
			continue
		var token := raw_token as Node2D
		if not is_instance_valid(token):
			continue

		var token_id := token.get_instance_id()
		seen_ids[token_id] = true

		var light := _live_light_by_token_id.get(token_id, null) as PointLight2D
		if light == null or not is_instance_valid(light):
			light = PointLight2D.new()
			light.name = "VisionLight_%d" % token_id
			light.enabled = true
			light.shadow_enabled = true
			light.range_item_cull_mask = VISION_LAYER_MASK
			light.shadow_item_cull_mask = VISION_LAYER_MASK
			light.visibility_layer = VISION_LAYER_MASK
			_live_lights_viewport.add_child(light)
			_live_light_by_token_id[token_id] = light

		var src := token.get_node_or_null("PointLight2D") as PointLight2D
		if src:
			if light.texture != src.texture:
				light.texture = src.texture
			if absf(light.texture_scale - src.texture_scale) > 0.0001:
				light.texture_scale = src.texture_scale
			var scaled_energy := maxf(src.energy * LIVE_LIGHT_ENERGY_GAIN, LIVE_LIGHT_MIN_ENERGY)
			if absf(light.energy - scaled_energy) > 0.0001:
				light.energy = scaled_energy
		else:
			if absf(light.energy - LIVE_LIGHT_MIN_ENERGY) > 0.0001:
				light.energy = LIVE_LIGHT_MIN_ENERGY
		# Always bake LOS from additive lights for stable reveal mask intensity.
		if light.blend_mode != Light2D.BLEND_MODE_ADD:
			light.blend_mode = Light2D.BLEND_MODE_ADD
		if not light.shadow_enabled:
			light.shadow_enabled = true
		if light.range_item_cull_mask != VISION_LAYER_MASK:
			light.range_item_cull_mask = VISION_LAYER_MASK
		if light.shadow_item_cull_mask != VISION_LAYER_MASK:
			light.shadow_item_cull_mask = VISION_LAYER_MASK
		if light.visibility_layer != VISION_LAYER_MASK:
			light.visibility_layer = VISION_LAYER_MASK
		if light.texture == null:
			light.texture = _get_or_create_radial_texture()

		var reveal_world := token.global_position
		if token.has_method("get_fog_reveal_position"):
			reveal_world = token.call("get_fog_reveal_position") as Vector2
		var reveal_local := reveal_world
		if token.get_parent() is Node2D:
			reveal_local = (token.get_parent() as Node2D).to_local(reveal_world)
		if light.position.distance_to(reveal_local) > 0.0001:
			light.position = reveal_local
		if absf(light.rotation - token.rotation) > 0.0001:
			light.rotation = token.rotation

		var radius_px := _estimate_light_radius_px(light, src)
		_mark_light_movement_dirty(token_id, reveal_local, radius_px)

	var stale_ids: Array = []
	for token_id in _live_light_by_token_id.keys():
		if seen_ids.has(token_id):
			continue
		stale_ids.append(token_id)
	for token_id in stale_ids:
		var stale = _live_light_by_token_id.get(token_id, null)
		if stale and is_instance_valid(stale):
			stale.queue_free()
		_live_light_by_token_id.erase(token_id)
		_live_light_state_by_token_id.erase(token_id)


func set_wall_polygons(polygons: Array) -> void:
	if _live_occluder_layer == null:
		return
	for child in _live_occluder_layer.get_children():
		child.queue_free()

	for raw_poly in polygons:
		if not raw_poly is Array:
			continue
		var poly := raw_poly as Array
		if poly.size() < 3:
			continue
		var points := PackedVector2Array()
		for raw_point in poly:
			if raw_point is Vector2:
				points.append(raw_point)
		if points.size() < 3:
			continue
		_live_occluder_layer.add_child(_new_occluder(points))

	# Wall topology changes alter LOS shape across the viewport.
	_queue_los_full_bake()


func _build_nodes() -> void:
	if _mask_host != null:
		return

	_mask_host = SubViewportContainer.new()
	_mask_host.name = "FogSystemMaskHost"
	_mask_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask_host.visible = false
	add_child(_mask_host)

	_live_lights_viewport = SubViewport.new()
	_live_lights_viewport.name = "LiveLightsViewport"
	_live_lights_viewport.transparent_bg = false
	_live_lights_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_live_lights_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_live_lights_viewport.disable_3d = true
	_live_lights_viewport.handle_input_locally = false
	_live_lights_viewport.canvas_cull_mask = VISION_LAYER_MASK
	_mask_host.add_child(_live_lights_viewport)

	_live_base_rect = ColorRect.new()
	_live_base_rect.name = "LiveBaseBlack"
	_live_base_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_live_base_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_base_rect.visibility_layer = VISION_LAYER_MASK
	_live_lights_viewport.add_child(_live_base_rect)

	_live_light_rect = ColorRect.new()
	_live_light_rect.name = "LiveLightMask"
	_live_light_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	_live_light_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_light_rect.visibility_layer = VISION_LAYER_MASK
	_live_light_rect.light_mask = VISION_LAYER_MASK
	var light_material := CanvasItemMaterial.new()
	light_material.light_mode = CanvasItemMaterial.LIGHT_MODE_LIGHT_ONLY
	_live_light_rect.material = light_material
	_live_lights_viewport.add_child(_live_light_rect)

	_live_occluder_layer = Node2D.new()
	_live_occluder_layer.name = "LiveOccluderLayer"
	_live_occluder_layer.visibility_layer = VISION_LAYER_MASK
	_live_lights_viewport.add_child(_live_occluder_layer)

	_fog_rect = ColorRect.new()
	_fog_rect.name = "FogCompositeRect"
	_fog_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_rect.visible = false
	add_child(_fog_rect)

	_build_history_gpu_pipeline()

	_resize_buffers_and_nodes()
	reset_history()


func _build_history_gpu_pipeline() -> void:
	_history_viewports.clear()
	_history_merge_rects.clear()
	_history_active_index = 0
	_history_swap_pending = false
	_history_pending_target_index = -1
	_history_gpu_ready = false

	if _mask_host == null:
		return

	var shader := load("res://assets/effects/fog_history_merge.gdshader") as Shader
	# if shader == null:
	# 	push_warning("FogSystem: fog_history_merge shader missing; falling back to CPU history")
	# 	return

	for i in range(2):
		var vp := SubViewport.new()
		vp.name = "HistoryViewport_%d" % i
		vp.transparent_bg = false
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.disable_3d = true
		vp.handle_input_locally = false
		_mask_host.add_child(vp)

		var base := ColorRect.new()
		base.name = "HistoryBase_%d" % i
		base.color = Color(0.0, 0.0, 0.0, 1.0)
		base.position = Vector2.ZERO
		vp.add_child(base)

		var merge := ColorRect.new()
		merge.name = "HistoryMerge_%d" % i
		merge.color = Color(1.0, 1.0, 1.0, 1.0)
		merge.position = Vector2.ZERO
		var mat := ShaderMaterial.new()
		mat.shader = shader
		merge.material = mat
		vp.add_child(merge)

		_history_viewports.append(vp)
		_history_merge_rects.append(merge)

	_history_gpu_ready = _history_viewports.size() == 2 and _history_merge_rects.size() == 2


func _get_active_history_texture() -> Texture2D:
	if not _history_gpu_ready:
		return _history_texture
	if _history_active_index < 0 or _history_active_index >= _history_viewports.size():
		return _history_texture
	var vp := _history_viewports[_history_active_index] as SubViewport
	return vp.get_texture() if vp else _history_texture


func _seed_gpu_history_from_image(image: Image) -> void:
	var svc := _fog_service()
	if svc == null:
		return
	var res := svc.seed_gpu_history_from_image(_history_viewports, _history_merge_rects, image, _history_seed_texture, LOS_BAKE_GAIN)
	if not res.get("ok", false):
		return
	_history_seed_texture = res.get("seed_texture", _history_seed_texture) as ImageTexture
	_history_active_index = int(res.get("active_index", _history_active_index))
	_history_swap_pending = bool(res.get("swap_pending", _history_swap_pending))
	_history_pending_target_index = int(res.get("pending_target_index", _history_pending_target_index))
	_history_seed_pending = bool(res.get("seed_pending", _history_seed_pending))
	_history_texture = res.get("history_texture", _history_texture) as Texture2D
	_apply_shader_uniforms()


func _create_or_update_image_texture(existing: ImageTexture, image: Image) -> ImageTexture:
	if image == null or image.is_empty():
		return existing
	if existing == null:
		return ImageTexture.create_from_image(image)

	var tex_size := existing.get_size()
	if int(tex_size.x) != image.get_width() or int(tex_size.y) != image.get_height():
		return ImageTexture.create_from_image(image)

	existing.update(image)
	return existing


func _resize_buffers_and_nodes() -> void:
	var target_size := Vector2i(maxi(1, roundi(_map_size.x)), maxi(1, roundi(_map_size.y)))
	_ensure_history_storage(_map_size)

	if _live_lights_viewport:
		_live_lights_viewport.size = target_size
	if _live_base_rect:
		_live_base_rect.position = Vector2.ZERO
		_live_base_rect.size = _map_size
	if _live_light_rect:
		_live_light_rect.position = Vector2.ZERO
		_live_light_rect.size = _map_size
	if _fog_rect:
		_fog_rect.position = Vector2.ZERO
		_fog_rect.size = _map_size
		_fog_rect.scale = Vector2.ONE
	if _mask_host:
		_mask_host.position = Vector2.ZERO
		_mask_host.scale = Vector2.ONE
	for vp_raw in _history_viewports:
		var vp := vp_raw as SubViewport
		if vp:
			vp.size = target_size
	for merge_raw in _history_merge_rects:
		var merge := merge_raw as ColorRect
		if merge:
			merge.position = Vector2.ZERO
			merge.size = _map_size
	_queue_los_full_bake()


func _ensure_history_storage(size: Vector2) -> void:
	var target_w := maxi(1, roundi(size.x))
	var target_h := maxi(1, roundi(size.y))
	if _history_image == null or _history_image.is_empty() or _history_image.get_width() != target_w or _history_image.get_height() != target_h:
		_history_image = Image.create(target_w, target_h, false, Image.FORMAT_L8)
		_history_image.fill(Color(0.0, 0.0, 0.0, 1.0))
		if _history_texture == null or not (_history_texture is ImageTexture):
			_history_texture = ImageTexture.create_from_image(_history_image)
		else:
			_history_texture = _create_or_update_image_texture(_history_texture as ImageTexture, _history_image)
		_history_dirty = false
		if DEBUG_FOG_TELEMETRY:
			print("FogSystem: history buffer resized (%dx%d)" % [target_w, target_h])


func _upload_history_texture() -> void:
	var svc := _fog_service()
	if svc == null:
		return
	var res := svc.upload_history_texture(_history_image, _history_gpu_ready, _history_texture as ImageTexture, _history_viewports, _history_merge_rects)
	if not res.get("ok", false):
		return
	_history_texture = res.get("history_texture", _history_texture) as Texture2D
	_history_seed_texture = res.get("seed_texture", _history_seed_texture) as ImageTexture
	_history_dirty = bool(res.get("history_dirty", false))


func _bake_live_los_into_history() -> void:
	if not _fog_enabled:
		return
	if not _los_bake_pending:
		return
	if _live_lights_viewport == null:
		return

	if _history_gpu_ready:
		if _history_viewports.size() < 2 or _history_merge_rects.size() < 2:
			return
		var src_idx := clampi(_history_active_index, 0, 1)
		var dst_idx := 1 - src_idx
		var src_vp := _history_viewports[src_idx] as SubViewport
		var dst_vp := _history_viewports[dst_idx] as SubViewport
		var dst_rect := _history_merge_rects[dst_idx] as ColorRect
		if src_vp == null or dst_vp == null or dst_rect == null:
			return
		var mat := dst_rect.material as ShaderMaterial
		if mat == null:
			return

		mat.set_shader_parameter("seed_mode", false)
		mat.set_shader_parameter("prev_history_tex", src_vp.get_texture())
		mat.set_shader_parameter("live_lights_tex", _live_lights_viewport.get_texture())
		mat.set_shader_parameter("los_bake_gain", LOS_BAKE_GAIN)
		dst_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

		_history_swap_pending = true
		_history_pending_target_index = dst_idx
		_los_bake_pending = false
		_los_dirty_regions.clear()
		_last_los_bake_msec = Time.get_ticks_msec()
		if DEBUG_FOG_TELEMETRY:
			_debug_los_bakes_frame += 1
		return


func _should_bake_los_now() -> bool:
	var svc := _fog_service()
	if svc == null:
		return false
	return svc.should_bake_los_now(_los_bake_pending, _last_los_bake_msec, LOS_BAKE_INTERVAL_MSEC)


func _estimate_light_radius_px(light: PointLight2D, src: PointLight2D) -> float:
	var light_scale := light.texture_scale if light else 1.0
	if src:
		light_scale = src.texture_scale
	var tex := light.texture if light else null
	if tex == null:
		return clampf(light_scale * 128.0, MIN_LIGHT_RADIUS_PX, MAX_LIGHT_RADIUS_PX)
	var tex_size := tex.get_size()
	var radius := maxf(tex_size.x, tex_size.y) * 0.5 * light_scale
	# Pad bounds so dirty-rect capture never clips cone edges/shadow penumbra.
	radius += 8.0
	return clampf(radius, MIN_LIGHT_RADIUS_PX, MAX_LIGHT_RADIUS_PX)


func _mark_light_movement_dirty(token_id: int, position_px: Vector2, radius_px: float) -> void:
	var current_rect := _rect_from_circle(position_px, radius_px)
	var prev_state := _live_light_state_by_token_id.get(token_id, {}) as Dictionary
	if prev_state.is_empty():
		_queue_los_dirty_rect(current_rect)
		_live_light_state_by_token_id[token_id] = {
			"position": position_px,
			"radius": radius_px,
		}
		return

	var prev_pos := prev_state.get("position", position_px) as Vector2
	var prev_radius := float(prev_state.get("radius", radius_px))
	if prev_pos.distance_to(position_px) > LIGHT_MOVE_EPSILON_PX or absf(prev_radius - radius_px) > 0.01:
		var prev_rect := _rect_from_circle(prev_pos, prev_radius)
		_queue_los_dirty_rect(prev_rect.merge(current_rect))

	_live_light_state_by_token_id[token_id] = {
		"position": position_px,
		"radius": radius_px,
	}


func _rect_from_circle(center_px: Vector2, radius_px: float) -> Rect2i:
	var svc := _fog_service()
	if svc == null:
		return Rect2i()
	return svc.rect_from_circle(center_px, radius_px, MIN_LIGHT_RADIUS_PX)


func _queue_los_dirty_rect(rect: Rect2i) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	_los_dirty_regions.append(rect)
	_compact_los_dirty_regions()
	_los_bake_pending = true


func _queue_los_full_bake() -> void:
	if _history_image and not _history_image.is_empty():
		_los_dirty_regions = [Rect2i(0, 0, _history_image.get_width(), _history_image.get_height())]
	else:
		_los_dirty_regions.clear()
	_los_bake_pending = true


func _compact_los_dirty_regions() -> void:
	if _los_dirty_regions.size() <= 1:
		return
	var svc := _fog_service()
	if svc == null:
		return
	_los_dirty_regions = svc.compact_los_dirty_regions(_los_dirty_regions, DIRTY_REGION_MERGE_PADDING_PX, MAX_DIRTY_REGIONS)


func _apply_shader_uniforms() -> void:
	if _fog_rect == null:
		return
	var mat := _fog_rect.material as ShaderMaterial
	if mat == null:
		var shader := load("res://assets/effects/dm_mask_fog.gdshader") as Shader
		mat = ShaderMaterial.new()
		mat.shader = shader
		_fog_rect.material = mat

	var history_tex := _get_active_history_texture()
	if history_tex:
		mat.set_shader_parameter("history_tex", history_tex)
	else:
		mat.set_shader_parameter("history_tex", _get_or_create_fallback_black_texture())
	if _live_lights_viewport:
		mat.set_shader_parameter("live_lights_tex", _live_lights_viewport.get_texture())
	else:
		mat.set_shader_parameter("live_lights_tex", _get_or_create_fallback_black_texture())
	mat.set_shader_parameter("is_dm", _is_dm)
	mat.set_shader_parameter("fog_color", Color(0.0, 0.0, 0.0, 1.0))
	mat.set_shader_parameter("player_alpha_scale", PLAYER_ALPHA_SCALE)
	mat.set_shader_parameter("dm_history_alpha_scale", DM_HISTORY_ALPHA_SCALE)
	mat.set_shader_parameter("live_mask_gain", LIVE_MASK_GAIN)
	_fog_rect.visible = _fog_enabled
	_fog_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _new_occluder(points: PackedVector2Array) -> LightOccluder2D:
	var occ_poly := OccluderPolygon2D.new()
	occ_poly.polygon = points
	var occluder := LightOccluder2D.new()
	occluder.occluder = occ_poly
	occluder.visibility_layer = VISION_LAYER_MASK
	occluder.occluder_light_mask = VISION_LAYER_MASK
	return occluder


func _get_or_create_radial_texture() -> Texture2D:
	if _radial_texture != null:
		return _radial_texture
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	for y in range(size):
		for x in range(size):
			var dist := center.distance_to(Vector2(x, y))
			if dist > radius:
				continue
			var t := 1.0 - (dist / radius)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, t * t))
	_radial_texture = ImageTexture.create_from_image(img)
	return _radial_texture


func _get_or_create_fallback_black_texture() -> Texture2D:
	if _fallback_black_texture != null:
		return _fallback_black_texture
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 1.0))
	_fallback_black_texture = ImageTexture.create_from_image(img)
	return _fallback_black_texture


func _paint_cell_block(cell: Vector2i, cell_px: int, value: float) -> void:
	if _history_image == null:
		return
	var x0 := cell.x * cell_px
	var y0 := cell.y * cell_px
	var x1 := x0 + cell_px
	var y1 := y0 + cell_px
	var w := _history_image.get_width()
	var h := _history_image.get_height()
	if x1 <= 0 or y1 <= 0 or x0 >= w or y0 >= h:
		return
	x0 = maxi(0, x0)
	y0 = maxi(0, y0)
	x1 = mini(w, x1)
	y1 = mini(h, y1)
	for py in range(y0, y1):
		for px in range(x0, x1):
			_history_image.set_pixel(px, py, Color(value, 0.0, 0.0, 1.0))


func _to_cell(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v as Vector2i
	if v is Vector2:
		var p := v as Vector2
		return Vector2i(int(round(p.x)), int(round(p.y)))
	if v is Dictionary:
		return Vector2i(int(v.get("x", -1)), int(v.get("y", -1)))
	if v is Array and (v as Array).size() >= 2:
		var arr := v as Array
		return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i(-1, -1)


func _verify_live_viewport_no_camera() -> void:
	if _live_lights_viewport == null:
		return
	for child in _live_lights_viewport.get_children():
		if child is Camera2D:
			push_warning("FogSystem: Camera2D found in LiveLightsViewport; this can offset LOS cones")


func _log_debug_metrics() -> void:
	var now := Time.get_ticks_msec()
	if _debug_last_metrics_msec == 0:
		_debug_last_metrics_msec = now
		_debug_los_bakes_frame = 0
		return
	if now - _debug_last_metrics_msec < 1000:
		return

	var hist_size := Vector2i.ZERO
	if _history_image and not _history_image.is_empty():
		hist_size = Vector2i(_history_image.get_width(), _history_image.get_height())
	var live_size := Vector2i.ZERO
	if _live_lights_viewport:
		live_size = _live_lights_viewport.size
	var light_count := _live_light_by_token_id.size()

	print("FogSystem metrics: is_dm=%s hist=%s live=%s lights=%d los_bakes_last_sec=%d pending=%s dirty_regions=%d history_dirty=%s" % [
		str(_is_dm),
		str(hist_size),
		str(live_size),
		light_count,
		_debug_los_bakes_frame,
		str(_los_bake_pending),
		_los_dirty_regions.size(),
		str(_history_dirty),
	])

	_debug_los_bakes_frame = 0
	_debug_last_metrics_msec = now
