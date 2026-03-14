extends Node2D
# DM Fog Migration: GPU-based workflow
# In DM mode, FogOverlay renders fog using GPU texture from FogSystem.
# Player mode uses CPU mask logic.

var _map_size: Vector2 = Vector2(1920, 1080)
var _cell_px: int = 32
var _hidden_cells: Dictionary = {}
var _opacity: float = 0.9
var _fog_enabled: bool = true
var _view_world_rect: Rect2 = Rect2()


const MASK_UPLOAD_MIN_INTERVAL_SEC: float = 1.0 / 60.0
const FOG_TINT_DARK: Color = Color(0.07, 0.09, 0.11, 1.0)
const FOG_TINT_DIM: Color = Color(0.06, 0.08, 0.10, 1.0)

var _mask_size: Vector2i = Vector2i(1, 1)
var _mask_image: Image = null
var _mask_texture: ImageTexture = null
var _mask_upload_pending: bool = false
var _mask_last_upload_usec: int = 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_process(true)


func _process(_delta: float) -> void:
	_flush_mask_upload(false)


func configure(
		map_size: Vector2,
		cell_px: int,
		hidden_cells: Dictionary,
		opacity: float,
		enabled: bool,
		_reveal_sources: Array = [],
		viewport_world_rect: Rect2 = Rect2()
	) -> void:
	_map_size = map_size
	_cell_px = maxi(1, cell_px)
	_hidden_cells = hidden_cells
	_opacity = clampf(opacity, 0.0, 1.0)
	_fog_enabled = enabled
	_view_world_rect = viewport_world_rect

	_ensure_mask()
	_rebuild_mask_from_hidden_cells()
	_mark_mask_dirty()
	_flush_mask_upload(true)
	queue_redraw()


func apply_delta(revealed_cells: Array, hidden_cells: Array) -> void:
	var fog_system := get_node_or_null("/root/FogSystem")
	if fog_system and fog_system.has_method("is_dm_mode") and fog_system.is_dm_mode():
		# DM mode: GPU authority, bypass pixel manipulation
		return
	# Player mode: CPU pixel logic
	if _mask_image == null:
		return

	var changed := false
	for raw_cell in revealed_cells:
		var cell := _to_cell(raw_cell)
		if not _in_mask_bounds(cell):
			continue
		_mask_image.set_pixel(cell.x, cell.y, Color(1, 1, 1, 0.0))
		changed = true

	for raw_cell in hidden_cells:
		var cell := _to_cell(raw_cell)
		if not _in_mask_bounds(cell):
			continue
		_mask_image.set_pixel(cell.x, cell.y, Color(1, 1, 1, 1.0))
		changed = true

	if not changed:
		return
	_mark_mask_dirty()
	# Coalesce many delta edits into throttled texture uploads.
	_flush_mask_upload(false)
	queue_redraw()


func _draw() -> void:
	if not _fog_enabled:
		return
	var fog_system := get_node_or_null("/root/FogSystem")
	if fog_system and fog_system.has_method("is_dm_mode") and fog_system.is_dm_mode():
			# DM mode: render GPU fog texture
			var gpu_texture: Texture2D = fog_system.get_history_texture() if fog_system.has_method("get_history_texture") else null
			if gpu_texture:
				var tint_gpu := FOG_TINT_DARK
				if _view_world_rect.size.x > 0.0 and _view_world_rect.size.y > 0.0:
					tint_gpu = FOG_TINT_DIM
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_texture_rect(gpu_texture, Rect2(Vector2.ZERO, _map_size), false, Color(tint_gpu.r, tint_gpu.g, tint_gpu.b, _opacity))
				return
	# Player mode: render CPU mask texture
	if _mask_texture == null:
		return
	var tint := FOG_TINT_DARK
	if _view_world_rect.size.x > 0.0 and _view_world_rect.size.y > 0.0:
		tint = FOG_TINT_DIM
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_texture_rect(_mask_texture, Rect2(Vector2.ZERO, _map_size), false, Color(tint.r, tint.g, tint.b, _opacity))


func _ensure_mask() -> void:
	var grid_w := maxi(1, ceili(_map_size.x / float(_cell_px)))
	var grid_h := maxi(1, ceili(_map_size.y / float(_cell_px)))
	var desired := Vector2i(grid_w, grid_h)
	if _mask_image != null and desired == _mask_size:
		return

	_mask_size = desired
	_mask_image = Image.create(_mask_size.x, _mask_size.y, false, Image.FORMAT_RGBA8)
	_mask_image.fill(Color(1, 1, 1, 0.0))
	_mask_texture = ImageTexture.create_from_image(_mask_image)


func _rebuild_mask_from_hidden_cells() -> void:
	if _mask_image == null:
		return

	_mask_image.fill(Color(1, 1, 1, 0.0))
	for key in _hidden_cells.keys():
		if not key is Vector2i:
			continue
		var cell := key as Vector2i
		if not _in_mask_bounds(cell):
			continue
		_mask_image.set_pixel(cell.x, cell.y, Color(1, 1, 1, 1.0))


func _mark_mask_dirty() -> void:
	_mask_upload_pending = true


func _flush_mask_upload(force: bool) -> void:
	if not _mask_upload_pending:
		return
	var uploaded := false
	if not force:
		var now_usec := Time.get_ticks_usec()
		if _mask_last_upload_usec > 0:
			var elapsed_sec := float(now_usec - _mask_last_upload_usec) / 1000000.0
			if elapsed_sec < MASK_UPLOAD_MIN_INTERVAL_SEC:
				return

	if _mask_texture == null:
		_mask_texture = ImageTexture.create_from_image(_mask_image)
		uploaded = true
	else:
		_mask_texture.update(_mask_image)
	uploaded = true
	_mask_upload_pending = false
	_mask_last_upload_usec = Time.get_ticks_usec()
	if uploaded:
		queue_redraw()


func _in_mask_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _mask_size.x and cell.y < _mask_size.y


func _to_cell(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v as Vector2i
	if v is Array and (v as Array).size() >= 2:
		var arr := v as Array
		return Vector2i(int(arr[0]), int(arr[1]))
	if v is Dictionary:
		return Vector2i(int(v.get("x", -1)), int(v.get("y", -1)))
	return Vector2i(-1, -1)
