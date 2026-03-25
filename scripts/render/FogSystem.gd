extends Node2D
class_name FogSystem

# === Constants ===

const FogPaintCanvasScript := preload("res://scripts/render/FogPaintCanvas.gd")

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
## Maximum fog-texture dimension (pixels on the longest axis).
## SubViewports for fog history, LOS, and paint are capped to this limit.
## The fog overlay is rendered at world size and UV-mapped, so visual quality
## degrades gracefully while VRAM stays bounded.
const MAX_FOG_DIM: int = 4096
## Maximum world-space padding around the player's visible area for
## viewport-local fog SubViewports.  Scaled down for small maps so the
## viewport covers the entire map and avoids constant re-seeding.
const VIEWPORT_MARGIN_PX_MAX: float = 256.0

# === State ===

var _map_size: Vector2 = Vector2(1920, 1080)
var _is_dm: bool = true
var _fog_enabled: bool = false
## Ratio between fog-texture pixels and world (map) pixels.  Computed in
## configure() as  min(1.0, MAX_FOG_DIM / max(map_w, map_h)).
var _fog_scale: float = 1.0
## Fog-texture target size (may be smaller than _map_size when capped).
var _fog_size: Vector2i = Vector2i(1920, 1080)
## When true, fog SubViewports cover only the camera's visible area + margin
## instead of the entire map.  Enabled automatically for the player renderer.
var _viewport_local: bool = false
## World-space rectangle that viewport-local SubViewports currently cover.
var _fog_world_rect: Rect2 = Rect2()
## Raw world-space wall polygons, stored so they can be re-transformed when
## _fog_world_rect changes in viewport-local mode.
var _raw_wall_polygons: Array = []

# --- GPU history ping-pong ---
var _history_texture: Texture2D = null
var _prev_los_data: PackedByteArray = PackedByteArray()
var _prev_los_width: int = 0
var _prev_los_height: int = 0
var _history_viewports: Array = []
var _history_merge_rects: Array = []
var _history_active_index: int = 0
var _history_swap_pending: bool = false
var _history_pending_target_index: int = -1
var _history_seed_texture: ImageTexture = null
var _history_gpu_ready: bool = false
var _history_seed_pending: bool = false

# --- GPU paint canvas ---
var _paint_canvas: FogPaintCanvasScript = null
var _paint_viewport: SubViewport = null
var _paint_merge_pending: bool = false
var _paint_clear_pending: bool = false
# Set in _apply_gpu_stroke; cleared in _process to ensure paint viewport
# renders before the bake samples its texture (input + _process run before rendering).
var _paint_bake_deferred: bool = false

# --- Scene nodes ---
var _mask_host: SubViewportContainer = null
var _live_lights_viewport: SubViewport = null
var _live_base_rect: ColorRect = null
var _live_light_rect: ColorRect = null
var _live_occluder_layer: Node2D = null

var _fog_rect: ColorRect = null
var _radial_texture: Texture2D = null

# --- Light tracking ---
var _live_light_by_token_id: Dictionary = {}
var _live_light_state_by_token_id: Dictionary = {}
var _live_light_config_by_token_id: Dictionary = {}
var _fallback_black_texture: ImageTexture = null
var _debug_los_bakes_frame: int = 0
var _debug_last_metrics_msec: int = 0
var _los_bake_pending: bool = true
var _last_los_bake_msec: int = 0
var _los_dirty_regions: Array = []
## Set after a LOS bake has occurred — cleared after _writeback_gpu_history_to_model()
## so we only do the expensive GPU→CPU readback when the GPU history has actually changed.
var _gpu_history_dirty: bool = false
var _fog_overlay_texture: Texture2D = null
var _fog_overlay_enabled: bool = false


# === Registry Helpers ===

func _fog_service() -> IFogService:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null:
		return null
	if registry.fog == null:
		return null
	return registry.fog.service


func _fog_manager() -> FogManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null:
		return null
	return registry.fog


func _fog_model() -> FogModel:
	var mgr := _fog_manager()
	if mgr == null:
		return null
	return mgr.model


# === Signal Handlers ===

func _on_fog_model_changed() -> void:
	var model := _fog_model()
	if model == null or model.history_image == null or model.history_image.is_empty():
		return
	_prev_los_data = PackedByteArray()
	_prev_los_width = 0
	_prev_los_height = 0
	if _history_gpu_ready:
		_seed_gpu_history_from_image(model.history_image)
	_queue_los_full_bake()


func _on_fog_stroke_applied(stroke: Dictionary) -> void:
	if not _fog_enabled or not _history_gpu_ready:
		return
	# Use the GPU paint canvas so we compose on top of the existing GPU history.
	# This preserves LOS-accumulated reveals that only exist in GPU memory and
	# never in the CPU history_image.
	_apply_gpu_stroke(stroke)


# === GPU Paint Pipeline ===

func _apply_gpu_stroke(stroke: Dictionary) -> void:
	if _paint_canvas == null or _paint_viewport == null:
		return
	# Transform the stroke from world-space to fog-texture-space.
	var scaled_stroke := stroke.duplicate()
	var stype: Variant = stroke.get("type", "")
	if _fog_scale < 1.0:
		if str(stype) == "brush":
			scaled_stroke["center"] = (stroke.get("center", Vector2.ZERO) as Vector2) * _fog_scale
			scaled_stroke["radius"] = float(stroke.get("radius", 0.0)) * _fog_scale
		elif str(stype) == "rect":
			scaled_stroke["a"] = (stroke.get("a", Vector2.ZERO) as Vector2) * _fog_scale
			scaled_stroke["b"] = (stroke.get("b", Vector2.ZERO) as Vector2) * _fog_scale
	_paint_canvas.queue_stroke(scaled_stroke)
	_paint_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not _paint_merge_pending:
		_paint_bake_deferred = true
	_paint_merge_pending = true


# === Lifecycle ===

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
		if _paint_clear_pending:
			# Only clear the canvas if no new strokes arrived after the last bake.
			# If _paint_merge_pending is true, new strokes are queued and will be
			# included in the next bake — clearing now would silently discard them.
			if _paint_canvas != null and not _paint_merge_pending:
				_paint_canvas.clear_strokes()
			_paint_clear_pending = false
		_apply_shader_uniforms()
	if _history_seed_pending:
		_history_seed_pending = false
		_apply_shader_uniforms()
		# Seed viewport(s) just queued UPDATE_ONCE — they haven't rendered yet.
		# Defer the bake by one frame so the seed texture is ready before the
		# merge shader reads from it.
		_los_bake_pending = true
		return
	# Paint-deferred: the paint viewport queued an UPDATE_ONCE this frame but
	# hasn't rendered yet (rendering follows _process). Mark the LOS bake pending
	# and return — the bake will fire next frame with a fresh paint texture.
	if _paint_bake_deferred:
		_paint_bake_deferred = false
		_los_bake_pending = true
		return
	if _should_bake_los_now():
		_bake_live_los_into_history()
	if DEBUG_FOG_TELEMETRY:
		_log_debug_metrics()


func configure(map_size: Vector2, is_dm: bool, enabled: bool) -> void:
	_map_size = Vector2(maxf(1.0, map_size.x), maxf(1.0, map_size.y))
	_is_dm = is_dm
	_fog_enabled = enabled
	# Compute fog resolution cap — all fog SubViewports use _fog_size.
	var longest := maxf(_map_size.x, _map_size.y)
	var base_fog_scale := minf(1.0, float(MAX_FOG_DIM) / longest) if longest > 0.0 else 1.0
	var base_fog_size := Vector2i(
		maxi(1, roundi(_map_size.x * base_fog_scale)),
		maxi(1, roundi(_map_size.y * base_fog_scale)))
	_viewport_local = false
	_fog_world_rect = Rect2()
	_fog_scale = base_fog_scale
	_fog_size = base_fog_size
	if _mask_host == null:
		_build_nodes()
	_resize_buffers_and_nodes()
	_apply_shader_uniforms()
	if _live_lights_viewport:
		_live_lights_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _fog_enabled else SubViewport.UPDATE_DISABLED
	# Connect FogManager signal and configure model after GPU pipeline is resized.
	# FogManager always uses the *base* capped scale and size so that
	# model.history_image stays at the full-map capped resolution regardless
	# of whether FogSystem is in viewport-local mode.
	var mgr := _fog_manager()
	if mgr != null:
		if not mgr.fog_changed.is_connected(_on_fog_model_changed):
			mgr.fog_changed.connect(_on_fog_model_changed)
		if not mgr.fog_stroke_applied.is_connected(_on_fog_stroke_applied):
			mgr.fog_stroke_applied.connect(_on_fog_stroke_applied)
		mgr.set_fog_scale(base_fog_scale)
		mgr.configure(base_fog_size, _is_dm, _fog_enabled)
	if DEBUG_FOG_TELEMETRY:
		print("FogSystem: configure (is_dm=%s fog_enabled=%s map_size=%s fog_size=%s fog_scale=%.3f viewport_local=%s)" % [
			str(_is_dm),
			str(_fog_enabled),
			str(_map_size),
			str(_fog_size),
			_fog_scale,
			str(_viewport_local),
		])

## Lightweight visibility toggle — avoids full pipeline reconfiguration.
## Use this when only the DM fog overlay needs to appear/disappear without
## changing map size, fog scale, or viewport-local mode.  The GPU history
## viewports retain their content across the toggle, so no re-seed is needed.
func set_display_enabled(enabled: bool) -> void:
	if _fog_enabled == enabled:
		return
	_fog_enabled = enabled
	if _live_lights_viewport:
		_live_lights_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _fog_enabled else SubViewport.UPDATE_DISABLED
	var mgr := _fog_manager()
	if mgr != null:
		mgr.set_enabled(_fog_enabled)
	_apply_shader_uniforms()
	if _fog_enabled:
		_queue_los_full_bake()


func set_fog_overlay_enabled(enabled: bool) -> void:
	_fog_overlay_enabled = enabled
	if _fog_overlay_enabled and _fog_overlay_texture == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.012
		noise.fractal_octaves = 4
		noise.fractal_lacunarity = 2.0
		noise.fractal_gain = 0.5
		var noise_tex := NoiseTexture2D.new()
		noise_tex.noise = noise
		noise_tex.width = 512
		noise_tex.height = 512
		noise_tex.seamless = true
		noise_tex.normalize = true
		_fog_overlay_texture = noise_tex
	_apply_shader_uniforms()

# === Public API ===

func get_fog_state() -> PackedByteArray:
	# When fog rendering is disabled the GPU history is stale — _process,
	# _on_fog_stroke_applied, and _bake_live_los_into_history all skip — so
	# fall back to the CPU model which always receives brush strokes.
	if not _fog_enabled:
		var cpu_model := _fog_model()
		if cpu_model != null and cpu_model.history_image != null and not cpu_model.history_image.is_empty():
			return cpu_model.history_image.save_png_to_buffer()
		return PackedByteArray()
	# Read from GPU to capture both manual reveals AND LOS accumulation.
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
	var model := _fog_model()
	if model == null or model.history_image == null or model.history_image.is_empty():
		return PackedByteArray()
	return model.history_image.save_png_to_buffer()


func set_fog_state(data: PackedByteArray) -> bool:
	return apply_fog_snapshot(data)


func apply_fog_snapshot(buffer: PackedByteArray) -> bool:
	var mgr := _fog_manager()
	if mgr == null:
		return false
	return mgr.apply_snapshot(buffer)


func reset_history() -> void:
	var mgr := _fog_manager()
	if mgr != null:
		mgr.reset()


func set_history_seed_from_hidden(cell_px: int, hidden_cells: Dictionary) -> void:
	var mgr := _fog_manager()
	if mgr != null:
		mgr.seed_from_hidden(cell_px, hidden_cells)


func apply_history_seed_delta(revealed_cells: Array, hidden_cells: Array, cell_px: int = -1) -> void:
	var mgr := _fog_manager()
	if mgr == null:
		return
	var safe_cell_px := maxi(1, cell_px if cell_px > 0 else 1)
	mgr.apply_seed_delta(revealed_cells, hidden_cells, safe_cell_px)


# === Viewport-Local Fog ===


func _viewport_margin_px() -> float:
	## Adaptive margin: use up to 256 px, but cap at 25% of the smallest map
	## dimension.  For small maps this makes the fog viewport cover the entire
	## map, eliminating viewport-rect thrashing and expensive re-seeds.
	return minf(VIEWPORT_MARGIN_PX_MAX, minf(_map_size.x, _map_size.y) * 0.25)


func update_viewport_rect(_camera_pos: Vector2, _zoom: float, _screen_size: Vector2, _rotation_deg: int = 0) -> void:
	## No-op — both DM and player now run full-resolution fog SubViewports.
	## Kept for API compatibility with MapView._process().
	return


func _writeback_gpu_history_to_model() -> void:
	## Read the active GPU history texture and write it back into the CPU
	## model's history_image.  Used for save, sync, and undo serialization.
	if not _history_gpu_ready:
		return
	var model := _fog_model()
	if model == null or model.history_image == null or model.history_image.is_empty():
		return
	var gpu_tex := _get_active_history_texture()
	if gpu_tex == null:
		return
	var gpu_img := gpu_tex.get_image()
	if gpu_img == null or gpu_img.is_empty():
		return
	gpu_img.convert(Image.FORMAT_L8)
	var dest := model.history_image
	var dw := dest.get_width()
	var dh := dest.get_height()
	if dw < 1 or dh < 1:
		return
	# Resize GPU image to match CPU model dimensions if needed.
	if gpu_img.get_width() != dw or gpu_img.get_height() != dh:
		gpu_img.resize(dw, dh, Image.INTERPOLATE_BILINEAR)
	# Merge using byte-level max() — never darken already-revealed pixels.
	var gpu_data := gpu_img.get_data()
	var cpu_data := dest.get_data()
	var count := mini(gpu_data.size(), cpu_data.size())
	var merged := PackedByteArray()
	merged.resize(count)
	var any_change := false
	for i in range(count):
		var g := gpu_data[i]
		var c := cpu_data[i]
		if g > c:
			merged[i] = g
			any_change = true
		else:
			merged[i] = c
	if any_change:
		model.history_image = Image.create_from_data(dw, dh, false, Image.FORMAT_L8, merged)
	_gpu_history_dirty = false


func _crop_and_seed_from_model_history() -> void:
	## Crop the viewport-local region from the FogManager's history image
	## and seed the GPU history SubViewports with the cropped result.
	if not _history_gpu_ready:
		return
	var model := _fog_model()
	var source: Image = null
	if model != null and model.history_image != null and not model.history_image.is_empty():
		source = model.history_image
	if source == null:
		return
	var sh_w := source.get_width()
	var sh_h := source.get_height()
	if sh_w < 1 or sh_h < 1:
		return
	# Map _fog_world_rect (world space) to pixel coords in the source image.
	var scale_x := float(sh_w) / _map_size.x
	var scale_y := float(sh_h) / _map_size.y
	var src_x := clampi(roundi(_fog_world_rect.position.x * scale_x), 0, sh_w - 1)
	var src_y := clampi(roundi(_fog_world_rect.position.y * scale_y), 0, sh_h - 1)
	var src_w := clampi(roundi(_fog_world_rect.size.x * scale_x), 1, sh_w - src_x)
	var src_h := clampi(roundi(_fog_world_rect.size.y * scale_y), 1, sh_h - src_y)
	var src_rect := Rect2i(src_x, src_y, src_w, src_h)
	var cropped := source.get_region(src_rect)
	if cropped == null or cropped.is_empty():
		return
	# Up-scale the crop to match the SubViewport dimensions so the seeded
	# history is pixel-aligned with subsequent LOS bakes and avoids the
	# blocky appearance that nearest-neighbour UV stretch would produce.
	if cropped.get_width() != _fog_size.x or cropped.get_height() != _fog_size.y:
		cropped.resize(_fog_size.x, _fog_size.y, Image.INTERPOLATE_BILINEAR)
	_seed_gpu_history_from_image(cropped)


# === Light / Token Management ===

func sync_player_revealers(tokens: Array) -> void:
	if _live_lights_viewport == null or not _fog_enabled:
		return
	var seen_ids: Dictionary = {}
	for raw_token in tokens:
		if not raw_token is PlayerSprite:
			continue
		var token := raw_token as PlayerSprite
		if not is_instance_valid(token):
			continue

		var token_id := token.get_instance_id()
		seen_ids[token_id] = true

		var light := _sync_or_create_vision_light(token_id)
		var src := token.get_node_or_null("PointLight2D") as PointLight2D

		# Fast-path: skip full _configure_vision_light when nothing changed.
		var reveal_world := token.get_fog_reveal_position()
		var reveal_local: Vector2 = reveal_world * _fog_scale
		var src_energy: float = src.energy if src != null else -1.0
		var prev_cfg: Dictionary = _live_light_config_by_token_id.get(token_id, {}) as Dictionary
		var cfg_changed: bool = prev_cfg.is_empty() \
			or light.position.distance_to(reveal_local) > 0.5 \
			or absf(light.rotation - token.rotation) > 0.001 \
			or absf(prev_cfg.get("energy", -999.0) as float - src_energy) > 0.001
		if cfg_changed:
			_configure_vision_light(light, src, token)
			_live_light_config_by_token_id[token_id] = {
				"position": reveal_local,
				"energy": src_energy,
				"rotation": token.rotation,
			}

		var radius_px := _estimate_light_radius_px(light, src)
		_mark_light_movement_dirty(token_id, light.position, radius_px)

	_remove_stale_lights(seen_ids)


func _sync_or_create_vision_light(token_id: int) -> PointLight2D:
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
	return light


func _configure_vision_light(light: PointLight2D, src: PointLight2D, token: PlayerSprite) -> void:
	if src != null:
		if light.texture != src.texture:
			light.texture = src.texture
		# Scale texture_scale into fog-texture space so the light covers the
		# correct proportional area of the (possibly downscaled) viewport.
		var target_tex_scale := src.texture_scale * _fog_scale
		if absf(light.texture_scale - target_tex_scale) > 0.0001:
			light.texture_scale = target_tex_scale
		# When source energy is zero (e.g. light suppressed during drag/move),
		# honour that and disable the fog light entirely.
		var suppressed: bool = src.energy < 0.001
		var scaled_energy := 0.0 if suppressed else maxf(src.energy * LIVE_LIGHT_ENERGY_GAIN, LIVE_LIGHT_MIN_ENERGY)
		if absf(light.energy - scaled_energy) > 0.0001:
			light.energy = scaled_energy
		if light.enabled == suppressed:
			light.enabled = not suppressed
			if light.enabled:
				_los_bake_pending = true
	else:
		if absf(light.energy - LIVE_LIGHT_MIN_ENERGY) > 0.0001:
			light.energy = LIVE_LIGHT_MIN_ENERGY
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

	var reveal_world := token.get_fog_reveal_position()
	# Map world position into fog-texture space.
	var reveal_local: Vector2 = reveal_world * _fog_scale
	if light.position.distance_to(reveal_local) > 0.0001:
		light.position = reveal_local
	if absf(light.rotation - token.rotation) > 0.0001:
		light.rotation = token.rotation


func _remove_stale_lights(seen_ids: Dictionary) -> void:
	var stale_ids: Array = []
	for token_id in _live_light_by_token_id.keys():
		if seen_ids.has(token_id):
			continue
		stale_ids.append(token_id)
	for token_id in stale_ids:
		var stale: Variant = _live_light_by_token_id.get(token_id, null)
		if stale and is_instance_valid(stale):
			(stale as Node).queue_free()
		_live_light_by_token_id.erase(token_id)
		_live_light_state_by_token_id.erase(token_id)
		_live_light_config_by_token_id.erase(token_id)


# === Wall / Occluder Management ===


# === DM Reveal Sources ===

func set_dm_reveals(_sources: Array) -> void:
	# Placeholder for DM-placed static reveal sources (from map.dm_reveal_objects).
	# Each element is a {position: Vector2, radius: float} dict.
	# Currently unused by the GPU pipeline; provided so typed call sites
	# can invoke this without a has_method guard.
	pass


# === Wall / Occluder Management ===

func set_wall_polygons(polygons: Array) -> void:
	_raw_wall_polygons = polygons.duplicate()
	_refresh_wall_occluders()


func _refresh_wall_occluders() -> void:
	if _live_occluder_layer == null:
		return
	for child in _live_occluder_layer.get_children():
		child.queue_free()

	for raw_poly in _raw_wall_polygons:
		if not raw_poly is Array:
			continue
		var poly := raw_poly as Array
		if poly.size() < 3:
			continue
		var points := PackedVector2Array()
		for raw_point in poly:
			if raw_point is Vector2:
				var world_pt := raw_point as Vector2
				points.append(world_pt * _fog_scale)
		if points.size() < 3:
			continue
		_live_occluder_layer.add_child(_new_occluder(points))

	# Wall topology changes alter LOS shape across the viewport.
	_queue_los_full_bake()


# === Scene Construction ===

func _build_nodes() -> void:
	if _mask_host != null:
		return

	_mask_host = SubViewportContainer.new()
	_mask_host.name = "FogSystemMaskHost"
	_mask_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask_host.visible = false
	add_child(_mask_host)

	_build_live_los_viewport()
	_build_fog_composite_rect()
	_build_history_gpu_pipeline()
	_build_paint_viewport()

	_resize_buffers_and_nodes()


func _build_live_los_viewport() -> void:
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


func _build_fog_composite_rect() -> void:
	_fog_rect = ColorRect.new()
	_fog_rect.name = "FogCompositeRect"
	_fog_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_rect.visible = false
	add_child(_fog_rect)


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


func _build_paint_viewport() -> void:
	if _mask_host == null:
		return
	_paint_viewport = SubViewport.new()
	_paint_viewport.name = "FogPaintViewport"
	_paint_viewport.transparent_bg = true
	_paint_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_paint_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_paint_viewport.disable_3d = true
	_paint_viewport.handle_input_locally = false
	_mask_host.add_child(_paint_viewport)

	_paint_canvas = FogPaintCanvasScript.new()
	_paint_canvas.name = "FogPaintCanvas"
	_paint_viewport.add_child(_paint_canvas)


# === GPU Bake Pipeline ===

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
	# Fog SubViewports use the capped _fog_size; the fog overlay rect covers
	# the full world _map_size.  Because the shader samples via UV [0,1],
	# the downscaled texture maps correctly onto the world-space overlay.
	var fog_target := _fog_size
	var fog_world := Vector2(_fog_size)

	if _live_lights_viewport:
		_live_lights_viewport.size = fog_target
	if _live_base_rect:
		_live_base_rect.position = Vector2.ZERO
		_live_base_rect.size = fog_world
	if _live_light_rect:
		_live_light_rect.position = Vector2.ZERO
		_live_light_rect.size = fog_world
	if _fog_rect:
		# Full-map: overlay covers the entire map, UV-mapped to fog textures.
		_fog_rect.position = Vector2.ZERO
		_fog_rect.size = _map_size
		_fog_rect.scale = Vector2.ONE
	if _mask_host:
		_mask_host.position = Vector2.ZERO
		_mask_host.scale = Vector2.ONE
	for vp_raw in _history_viewports:
		var vp := vp_raw as SubViewport
		if vp:
			vp.size = fog_target
	for merge_raw in _history_merge_rects:
		var merge := merge_raw as ColorRect
		if merge:
			merge.position = Vector2.ZERO
			merge.size = fog_world
	if _paint_viewport:
		_paint_viewport.size = fog_target
	_queue_los_full_bake()


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
		if _paint_merge_pending and _paint_viewport != null:
			mat.set_shader_parameter("has_paint_tex", true)
			mat.set_shader_parameter("paint_tex", _paint_viewport.get_texture())
			_paint_merge_pending = false
			_paint_clear_pending = true
		else:
			mat.set_shader_parameter("has_paint_tex", false)
		dst_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

		_history_swap_pending = true
		_history_pending_target_index = dst_idx
		_los_bake_pending = false
		_gpu_history_dirty = true
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
		return clampf(light_scale * 128.0 * _fog_scale, MIN_LIGHT_RADIUS_PX, MAX_LIGHT_RADIUS_PX)
	var tex_size := tex.get_size()
	var radius := maxf(tex_size.x, tex_size.y) * 0.5 * light_scale * _fog_scale
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
	_los_dirty_regions = [Rect2i(Vector2i.ZERO, _fog_size)]
	_los_bake_pending = true


func _compact_los_dirty_regions() -> void:
	if _los_dirty_regions.size() <= 1:
		return
	var svc := _fog_service()
	if svc == null:
		return
	_los_dirty_regions = svc.compact_los_dirty_regions(_los_dirty_regions, DIRTY_REGION_MERGE_PADDING_PX, MAX_DIRTY_REGIONS)


# === Shader Uniforms ===

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
	mat.set_shader_parameter("fog_overlay_enabled", _fog_overlay_enabled)
	if _fog_overlay_texture != null:
		mat.set_shader_parameter("fog_overlay_tex", _fog_overlay_texture)
	_fog_rect.visible = _fog_enabled
	_fog_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


# === Helpers ===

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
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var grad_tex := GradientTexture2D.new()
	grad_tex.width = 256
	grad_tex.height = 256
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)
	grad_tex.gradient = gradient
	_radial_texture = grad_tex
	return _radial_texture


func _get_or_create_fallback_black_texture() -> Texture2D:
	if _fallback_black_texture != null:
		return _fallback_black_texture
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 1.0))
	_fallback_black_texture = ImageTexture.create_from_image(img)
	return _fallback_black_texture


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
	var dbg_model := _fog_model()
	if dbg_model != null and dbg_model.history_image != null and not dbg_model.history_image.is_empty():
		hist_size = dbg_model.size
	var live_size := Vector2i.ZERO
	if _live_lights_viewport:
		live_size = _live_lights_viewport.size
	var light_count := _live_light_by_token_id.size()

	print("FogSystem metrics: is_dm=%s hist=%s live=%s fog_scale=%.3f lights=%d los_bakes_last_sec=%d pending=%s dirty_regions=%d vp_local=%s" % [
		str(_is_dm),
		str(hist_size),
		str(live_size),
		_fog_scale,
		light_count,
		_debug_los_bakes_frame,
		str(_los_bake_pending),
		_los_dirty_regions.size(),
		str(_viewport_local),
	])

	_debug_los_bakes_frame = 0
	_debug_last_metrics_msec = now
