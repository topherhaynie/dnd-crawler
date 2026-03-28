extends Node
class_name IUIThemeService

## Protocol: IUIThemeService
##
## Provides a selectable UI theme (chrome / metallic backgrounds + accent
## colours) for the DM window.  Views connect to `theme_changed` for live
## switching; all method calls go through UIThemeManager.
##
## Public API:
##   get_theme, set_theme, get_available_themes

@warning_ignore("unused_signal")
signal theme_changed(preset: int)


func get_theme() -> int:
	push_error("IUIThemeService.get_theme: not implemented")
	return 0


func set_theme(_preset: int) -> void:
	push_error("IUIThemeService.set_theme: not implemented")


func get_available_themes() -> Array[int]:
	push_error("IUIThemeService.get_available_themes: not implemented")
	return []


func load_persisted() -> void:
	push_error("IUIThemeService.load_persisted: not implemented")
