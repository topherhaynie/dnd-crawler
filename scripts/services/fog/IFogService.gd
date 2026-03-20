extends Node
class_name IFogService

## Protocol: IFogService
##
## Base class for fog-of-war services. Extend this class and override all
## methods; stubs push_error so missing overrides surface at runtime.
##
## Public API (DMWindow, MapView, PlayerWindow):
##   reveal_area, set_fog_enabled, get_fog_state, get_fog_state_size,
##   set_fog_state, capture_fog_state
##
## FogManager delegation contract (image mutation, called from FogManager):
##   apply_history_brush, apply_history_rect, apply_history_seed_delta,
##   set_history_seed_from_hidden
##
## FogSystem GPU delegation contract (called from FogSystem renderer only):
##   rect_from_circle, compact_los_dirty_regions, should_bake_los_now,
##   seed_gpu_history_from_image, upload_history_texture

@warning_ignore("unused_signal")
signal fog_updated(state: Dictionary)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func reveal_area(_pos: Vector2, _radius: float) -> void:
	push_error("IFogService.reveal_area: not implemented")

func set_fog_enabled(_enabled: bool) -> void:
	push_error("IFogService.set_fog_enabled: not implemented")

func get_fog_state() -> PackedByteArray:
	push_error("IFogService.get_fog_state: not implemented")
	return PackedByteArray()

func get_fog_state_size() -> Vector2i:
	push_error("IFogService.get_fog_state_size: not implemented")
	return Vector2i.ZERO

func set_fog_state(_data: PackedByteArray) -> bool:
	push_error("IFogService.set_fog_state: not implemented")
	return false

func capture_fog_state(_viewport: SubViewport) -> PackedByteArray:
	push_error("IFogService.capture_fog_state: not implemented")
	return PackedByteArray()

# ---------------------------------------------------------------------------
# FogSystem delegation contract
# ---------------------------------------------------------------------------

func rect_from_circle(_center_px: Vector2, _radius_px: float, _min_radius_px: float) -> Rect2i:
	push_error("IFogService.rect_from_circle: not implemented")
	return Rect2i()

func compact_los_dirty_regions(_dirty_regions: Array, _merge_padding: int, _max_dirty: int) -> Array:
	push_error("IFogService.compact_los_dirty_regions: not implemented")
	return []

func should_bake_los_now(_los_bake_pending: bool, _last_msec: int, _interval_msec: int) -> bool:
	push_error("IFogService.should_bake_los_now: not implemented")
	return false

func seed_gpu_history_from_image(_history_viewports: Array, _history_merge_rects: Array, _history_image: Image, _existing_seed_texture: ImageTexture, _los_bake_gain: float) -> Dictionary:
	push_error("IFogService.seed_gpu_history_from_image: not implemented")
	return {}

func upload_history_texture(_history_image: Image, _history_gpu_ready: bool, _existing_history_texture: ImageTexture, _history_viewports: Array, _history_merge_rects: Array, _los_bake_gain: float = 1.0) -> Dictionary:
	push_error("IFogService.upload_history_texture: not implemented")
	return {}

func set_history_seed_from_hidden(_history_image: Image, _cell_px: int, _hidden_cells: Dictionary) -> Dictionary:
	push_error("IFogService.set_history_seed_from_hidden: not implemented")
	return {}

func apply_history_seed_delta(_history_image: Image, _revealed_cells: Array, _hidden_cells: Array, _cell_px: int) -> bool:
	push_error("IFogService.apply_history_seed_delta: not implemented")
	return false

func apply_history_brush(_history_image: Image, _world_pos: Vector2, _radius_px: float, _reveal: bool) -> bool:
	push_error("IFogService.apply_history_brush: not implemented")
	return false

func apply_history_rect(_history_image: Image, _a: Vector2, _b: Vector2, _reveal: bool) -> bool:
	push_error("IFogService.apply_history_rect: not implemented")
	return false
