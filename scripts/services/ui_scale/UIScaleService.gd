extends IUIScaleService
class_name UIScaleService

## UIScaleService — computes a blended DPI + viewport scale factor.
##
## Blend logic: max(dpi_scale, viewport_scale) where
##   dpi_scale      = clamp(screen_dpi / 96, 1.0, 2.0)
##   viewport_scale = clamp(min(vp.x/1920, vp.y/1080), 1.0, 1.6)
##
## Call refresh() whenever the viewport resizes or DPI changes. The service
## caches the last value and only emits scale_changed when it actually differs.

var _cached_scale: float = 1.0


func _ready() -> void:
	_cached_scale = _compute()


func get_scale() -> float:
	return _cached_scale


func refresh() -> void:
	var s: float = _compute()
	if not is_equal_approx(s, _cached_scale):
		_cached_scale = s
		scale_changed.emit(s)


func _compute() -> float:
	var dpi_scale: float = clampf(DisplayServer.screen_get_dpi() / 96.0, 1.0, 2.0)
	var vp_rect: Rect2 = get_viewport().get_visible_rect() if get_viewport() else Rect2(0, 0, 1920, 1080)
	var vp: Vector2 = vp_rect.size
	var viewport_scale: float = clampf(minf(vp.x / 1920.0, vp.y / 1080.0), 1.0, 1.6)
	return maxf(dpi_scale, viewport_scale)
