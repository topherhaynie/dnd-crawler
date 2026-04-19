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
	## Recursively set font sizes on Label, LineEdit, SpinBox, RichTextLabel,
	## etc.  Controls that carry a "_font_base" meta override use that as
	## their individual base instead of the tree-wide default.  This allows
	## a single call to handle an entire font hierarchy (headers, body,
	## compact labels) without a separate fixup pass.
	_scale_control_fonts_recurse(root_node, base_font_size)


func _scale_control_fonts_recurse(node: Node, default_base: float) -> void:
	for child: Node in node.get_children():
		var base: float = default_base
		if child is Control and (child as Control).has_meta("_font_base"):
			base = float((child as Control).get_meta("_font_base"))
		var fsz: int = scaled(base)
		if child is SpinBox:
			(child as SpinBox).get_line_edit().add_theme_font_size_override("font_size", fsz)
			# Ensure SpinBox height accommodates the scaled font + button arrows
			var sb_min_h: float = float(fsz) + 16.0 * get_scale()
			if (child as SpinBox).custom_minimum_size.y < sb_min_h:
				(child as SpinBox).custom_minimum_size.y = sb_min_h
			# Ensure SpinBox width accommodates arrows beside the text
			var sb_min_w: float = float(fsz) * 4.0 + 16.0 * get_scale()
			if (child as SpinBox).custom_minimum_size.x < sb_min_w:
				(child as SpinBox).custom_minimum_size.x = sb_min_w
		elif child is RichTextLabel:
			(child as RichTextLabel).add_theme_font_size_override("normal_font_size", fsz)
			(child as RichTextLabel).add_theme_font_size_override("bold_font_size", fsz)
		elif child is TabContainer:
			(child as TabContainer).add_theme_font_size_override("font_size", fsz)
		elif child is ItemList:
			(child as ItemList).add_theme_font_size_override("font_size", fsz)
		elif child is Label or child is LineEdit or child is OptionButton \
				or child is CheckBox or child is Button or child is TextEdit:
			(child as Control).add_theme_font_size_override("font_size", fsz)
		# OptionButton popup menu needs its own font size
		if child is OptionButton:
			var ob_popup: PopupMenu = (child as OptionButton).get_popup()
			if ob_popup != null:
				ob_popup.add_theme_font_size_override("font_size", fsz)
		if child is Container and not child is SpinBox:
			_scale_control_fonts_recurse(child, default_base)


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
	dialog.grab_focus()


static func set_font_base(ctrl: Control, base: float) -> void:
	## Tag a control with a per-node font base size.  The next call to
	## scale_control_fonts will use this base instead of the tree-wide
	## default.  Call this once during UI construction.
	ctrl.set_meta("_font_base", base)
