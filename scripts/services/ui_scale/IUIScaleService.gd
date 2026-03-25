extends Node
class_name IUIScaleService

## Protocol: IUIScaleService
##
## Provides DPI-aware UI scale factor that blends display DPI with viewport
## dimensions.  Any node that builds or sizes UI controls should query
## get_scale() and connect to scale_changed to stay current on resize/DPI
## changes.
##
## Public API:
##   get_scale, refresh

@warning_ignore("unused_signal")
signal scale_changed(new_scale: float)


func get_scale() -> float:
	push_error("IUIScaleService.get_scale: not implemented")
	return 1.0


func refresh() -> void:
	push_error("IUIScaleService.refresh: not implemented")
