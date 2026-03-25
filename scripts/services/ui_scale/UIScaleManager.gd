extends RefCounted
class_name UIScaleManager

## UIScaleManager — typed manager for the UI scale subsystem.
##
## Access via: registry.ui_scale  (ServiceRegistry)
## Or early via: (get_node("/root/ServiceBootstrap") as Node).registry.ui_scale

var service: IUIScaleService = null


func get_scale() -> float:
	if service != null and service.is_inside_tree():
		return service.get_scale()
	# Fallback before service enters the scene tree.
	var dpi_scale: float = clampf(DisplayServer.screen_get_dpi() / 96.0, 1.0, 2.0)
	var screen: Vector2i = DisplayServer.screen_get_size()
	var viewport_scale: float = clampf(minf(float(screen.x) / 1920.0, float(screen.y) / 1080.0), 1.0, 1.6)
	return maxf(dpi_scale, viewport_scale)


func refresh() -> void:
	if service != null:
		service.refresh()


# ---------------------------------------------------------------------------
# Convenience helpers — keep scale math out of view code
# ---------------------------------------------------------------------------

func scaled(base: float) -> int:
	## Return base * scale, rounded to int.
	return roundi(base * get_scale())


func scale_button(btn: BaseButton, base_w: float = 100.0, base_h: float = 30.0, base_font: float = 13.0) -> void:
	## Size a dialog / action button consistently.
	if btn == null:
		return
	btn.custom_minimum_size = Vector2(scaled(base_w), scaled(base_h))
	btn.add_theme_font_size_override("font_size", scaled(base_font))


func scale_control_fonts(root_node: Control, base_font_size: float = 14.0) -> void:
	## Recursively set font sizes on Label, LineEdit, SpinBox, etc.
	var fsz: int = scaled(base_font_size)
	for child: Node in root_node.get_children():
		if child is SpinBox:
			(child as SpinBox).get_line_edit().add_theme_font_size_override("font_size", fsz)
		elif child is Label or child is LineEdit or child is OptionButton \
				or child is CheckBox or child is Button or child is TextEdit:
			(child as Control).add_theme_font_size_override("font_size", fsz)
		if child is Container and not child is SpinBox:
			scale_control_fonts(child as Control, base_font_size)


func popup_fitted(dialog: Window, base_min_w: float = 0.0, base_min_h: float = 0.0) -> void:
	## Popup the window, auto-sized to content. Optional minimum base dims.
	## Sets wrap_controls so the window queries child minimum sizes, calls
	## reset_size() to shrink to content, then centres on screen.
	dialog.wrap_controls = true
	if base_min_w > 0.0 or base_min_h > 0.0:
		dialog.min_size = Vector2i(
			scaled(base_min_w) if base_min_w > 0.0 else 0,
			scaled(base_min_h) if base_min_h > 0.0 else 0)
	dialog.reset_size()
	dialog.popup_centered()
