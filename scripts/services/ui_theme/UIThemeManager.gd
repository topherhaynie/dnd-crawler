extends RefCounted
class_name UIThemeManager

## UIThemeManager — typed manager for the UI theme subsystem.
##
## Access via: registry.ui_theme  (ServiceRegistry)
##
## Provides:
##   • Static shader chrome for the full-window background (modes 1-4)
##   • Flat-Dark mode uses plain ColorRect (no shader)
##   • Theme-aware panel, button, and window StyleBoxFlat styling
##   • Live theme switching (re-styles all tracked items)

const _THEME_META: String = "ui_theme_styled"
const _BTN_META: String = "ui_theme_btn"
const _TREE_META: String = "ui_theme_tree"
const _CHROME_SHADER: String = "res://assets/effects/chrome_ui.gdshader"
## Public — set on controls that should be skipped by theme_control_tree.
const SKIP_AUTO_THEME: String = "ui_theme_skip_auto"
const _INPUT_META: String = "ui_theme_input"
const _POPUP_META: String = "ui_theme_popup"

var service: IUIThemeService = null

## Tracked items for live theme switching.
var _styled_panels: Array = [] ## Array of WeakRef → PanelContainer
var _styled_buttons: Array = [] ## Array of WeakRef → BaseButton
var _bg_rects: Array = [] ## Array of WeakRef → ColorRect (standalone bgs)
var _styled_windows: Array = [] ## Array of WeakRef → Window
var _themed_trees: Array = [] ## Array of { "ref": WeakRef → Node, "scale": float }
var _styled_inputs: Array = [] ## Array of WeakRef → LineEdit
var _styled_popups: Array = [] ## Array of WeakRef → PopupMenu


# ---------------------------------------------------------------------------
# Passthrough API — views call these, never service directly
# ---------------------------------------------------------------------------

func get_theme() -> int:
	if service != null:
		return service.get_theme()
	return UIThemeData.ThemePreset.FLAT_DARK


func set_theme(preset: int) -> void:
	if service != null:
		service.set_theme(preset)


func get_available_themes() -> Array[int]:
	if service != null:
		return service.get_available_themes()
	return UIThemeData.get_all_presets()


func get_accent_palette() -> Dictionary:
	return UIThemeData.get_accent_palette(get_theme())


# ---------------------------------------------------------------------------
# Panel theming — set a themed StyleBoxFlat on PanelContainers
# ---------------------------------------------------------------------------

func apply_chrome(panel: PanelContainer) -> void:
	## Apply a themed StyleBoxFlat background to a PanelContainer.  Idempotent.
	if panel == null:
		return
	if panel.has_meta(_THEME_META):
		return
	panel.set_meta(_THEME_META, true)
	_styled_panels.append(weakref(panel))
	_apply_panel_style(panel)


func _apply_panel_style(panel: PanelContainer) -> void:
	var palette: Dictionary = get_accent_palette()
	var bg: Color = palette.get("panel_bg", Color(0.18, 0.18, 0.18)) as Color
	var border: Color = palette.get("panel_border", Color(0.3, 0.3, 0.3)) as Color
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", sb)


# ---------------------------------------------------------------------------
# Button style factory
# ---------------------------------------------------------------------------

func create_button_styles(scale: float) -> Dictionary:
	## Returns { "normal": StyleBoxFlat, "hover": StyleBoxFlat,
	##           "pressed": StyleBoxFlat, "disabled": StyleBoxFlat }
	## using the current theme's accent palette.
	var palette: Dictionary = get_accent_palette()
	var corner: int = roundi(6.0 * scale)
	var pad: int = roundi(4.0 * scale)
	var border_col: Color = palette.get("panel_border", Color(0.3, 0.3, 0.3)) as Color

	var normal := StyleBoxFlat.new()
	normal.bg_color = palette.get("normal_bg", Color(0.22, 0.22, 0.22)) as Color
	normal.set_content_margin_all(pad)
	normal.set_corner_radius_all(corner)
	normal.set_border_width_all(1)
	normal.border_color = border_col

	var hover := StyleBoxFlat.new()
	hover.bg_color = palette.get("hover_bg", Color(0.28, 0.28, 0.28)) as Color
	hover.set_content_margin_all(pad)
	hover.set_corner_radius_all(corner)
	hover.set_border_width_all(1)
	hover.border_color = border_col.lightened(0.3)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = palette.get("pressed_bg", Color(0.3, 0.55, 0.9, 0.35)) as Color
	pressed.border_color = palette.get("pressed_border", Color(0.4, 0.65, 1.0, 0.7)) as Color
	pressed.set_border_width_all(1)
	pressed.border_width_left = roundi(2.0 * scale)
	pressed.set_corner_radius_all(corner)
	pressed.set_content_margin_all(pad)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = palette.get("disabled_bg", Color(0.18, 0.18, 0.18)) as Color
	disabled.set_content_margin_all(pad)
	disabled.set_corner_radius_all(corner)
	disabled.set_border_width_all(1)
	disabled.border_color = border_col.darkened(0.3)

	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"disabled": disabled,
	}


func apply_button_style(btn: BaseButton, scale: float) -> void:
	## Apply themed StyleBoxes to a button and track it for live switching.
	if btn == null:
		return
	var styles: Dictionary = create_button_styles(scale)
	btn.add_theme_stylebox_override("normal", styles["normal"] as StyleBox)
	btn.add_theme_stylebox_override("hover", styles["hover"] as StyleBox)
	btn.add_theme_stylebox_override("pressed", styles["pressed"] as StyleBox)
	btn.add_theme_stylebox_override("disabled", styles["disabled"] as StyleBox)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# Font colour from theme palette
	var palette: Dictionary = get_accent_palette()
	var font_col: Color = palette.get("label_tint", Color(0.7, 0.7, 0.7)) as Color
	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_hover_color", font_col.lightened(0.15))
	btn.add_theme_color_override("font_pressed_color", font_col.lightened(0.25))
	btn.add_theme_color_override("font_disabled_color", font_col.darkened(0.4))

	if not btn.has_meta(_BTN_META):
		btn.set_meta(_BTN_META, true)
		_styled_buttons.append(weakref(btn))


func apply_check_style(btn: BaseButton, scale: float) -> void:
	## Style a CheckBox or CheckButton with transparent backgrounds so only font
	## colour and hover/pressed tints apply — the toggle icon remains visible.
	if btn == null:
		return
	var palette: Dictionary = get_accent_palette()
	var font_col: Color = palette.get("label_tint", Color(0.7, 0.7, 0.7)) as Color

	# Transparent backgrounds so the check icon remains the visual focus
	var corner: int = roundi(4.0 * scale)
	var pad: int = roundi(2.0 * scale)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	normal.set_content_margin_all(pad)
	normal.set_corner_radius_all(corner)

	var hover := StyleBoxFlat.new()
	hover.bg_color = palette.get("hover_bg", Color(0.28, 0.28, 0.28)) as Color
	hover.bg_color.a = 0.3
	hover.set_content_margin_all(pad)
	hover.set_corner_radius_all(corner)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	pressed.set_content_margin_all(pad)
	pressed.set_corner_radius_all(corner)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	disabled.set_content_margin_all(pad)
	disabled.set_corner_radius_all(corner)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_hover_color", font_col.lightened(0.15))
	btn.add_theme_color_override("font_pressed_color", font_col.lightened(0.25))
	btn.add_theme_color_override("font_disabled_color", font_col.darkened(0.4))

	if not btn.has_meta(_BTN_META):
		btn.set_meta(_BTN_META, true)
		_styled_buttons.append(weakref(btn))


func create_pressed_style(scale: float) -> StyleBoxFlat:
	## Convenience — just the pressed/active indicator StyleBox from the current theme.
	var palette: Dictionary = get_accent_palette()
	var sb := StyleBoxFlat.new()
	sb.bg_color = palette.get("pressed_bg", Color(0.3, 0.55, 0.9, 0.35)) as Color
	sb.border_color = palette.get("pressed_border", Color(0.4, 0.65, 1.0, 0.7)) as Color
	sb.set_border_width_all(1)
	sb.border_width_left = roundi(2.0 * scale)
	sb.set_corner_radius_all(roundi(6.0 * scale))
	sb.set_content_margin_all(roundi(4.0 * scale))
	return sb


# ---------------------------------------------------------------------------
# Input control theming  (LineEdit, SpinBox)
# ---------------------------------------------------------------------------

func _apply_input_style(input: LineEdit, scale: float) -> void:
	## Apply themed StyleBoxFlat to a LineEdit and track for live refresh.
	if input == null:
		return
	var palette: Dictionary = get_accent_palette()
	var bg: Color = (palette.get("panel_bg", Color(0.18, 0.18, 0.18)) as Color).darkened(0.15)
	var border_col: Color = palette.get("panel_border", Color(0.3, 0.3, 0.3)) as Color
	var font_col: Color = palette.get("label_tint", Color(0.7, 0.7, 0.7)) as Color
	var corner: int = roundi(4.0 * scale)
	var pad: int = roundi(4.0 * scale)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_corner_radius_all(corner)
	normal.set_content_margin_all(pad)
	normal.set_border_width_all(1)
	normal.border_color = border_col

	var focus := StyleBoxFlat.new()
	focus.bg_color = bg.lightened(0.05)
	focus.set_corner_radius_all(corner)
	focus.set_content_margin_all(pad)
	focus.set_border_width_all(1)
	focus.border_color = palette.get("pressed_border", Color(0.4, 0.65, 1.0, 0.7)) as Color

	input.add_theme_stylebox_override("normal", normal)
	input.add_theme_stylebox_override("focus", focus)
	input.add_theme_stylebox_override("read_only", normal)
	input.add_theme_color_override("font_color", font_col)
	input.add_theme_color_override("font_placeholder_color", font_col.darkened(0.35))
	input.add_theme_color_override("caret_color", font_col)
	input.add_theme_color_override("selection_color", palette.get("pressed_bg", Color(0.3, 0.55, 0.9, 0.35)) as Color)

	if not input.has_meta(_INPUT_META):
		input.set_meta(_INPUT_META, true)
		_styled_inputs.append(weakref(input))


func get_label_tint() -> Color:
	var palette: Dictionary = get_accent_palette()
	return palette.get("label_tint", Color(0.7, 0.7, 0.7)) as Color


func get_header_tint() -> Color:
	var tint: Color = get_label_tint()
	return tint.darkened(0.2)


# ---------------------------------------------------------------------------
# Standalone background rect (e.g. behind MapView in the main window)
# ---------------------------------------------------------------------------

func create_background_chrome() -> ColorRect:
	## Create a full-rect ColorRect with the chrome shader (or plain bg for FLAT_DARK).
	## The caller adds it to the scene tree.  Tracked for live switching.
	var cr := ColorRect.new()
	cr.name = "WindowChromeBG"
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	_apply_bg_material(cr)
	_bg_rects.append(weakref(cr))
	return cr


func _apply_bg_material(cr: ColorRect) -> void:
	## Set or update the material/color on a background ColorRect.
	var preset: int = get_theme()
	var shader_mode: int = UIThemeData.get_shader_mode(preset)
	if shader_mode == 0:
		# FLAT_DARK — plain solid colour, no shader
		cr.material = null
		var palette: Dictionary = get_accent_palette()
		cr.color = palette.get("panel_bg", Color(0.12, 0.12, 0.14)) as Color
		return
	# Shader mode — create or reuse ShaderMaterial
	var shader: Shader = load(_CHROME_SHADER) as Shader
	if shader == null:
		var palette: Dictionary = get_accent_palette()
		cr.color = palette.get("panel_bg", Color(0.12, 0.12, 0.14)) as Color
		return
	var mat: ShaderMaterial = null
	if cr.material is ShaderMaterial:
		mat = cr.material as ShaderMaterial
	else:
		mat = ShaderMaterial.new()
		mat.shader = shader
		cr.material = mat
	# White base so the shader controls all colour
	cr.color = Color.WHITE
	var colors: Dictionary = UIThemeData.get_shader_colors(preset)
	var base: Color = colors.get("base", Color(0.05, 0.06, 0.08)) as Color
	var highlight: Color = colors.get("highlight", Color(0.52, 0.58, 0.68)) as Color
	var edge_glow: Color = colors.get("edge_glow", Color(0.28, 0.42, 0.65)) as Color
	mat.set_shader_parameter("theme_mode", shader_mode)
	mat.set_shader_parameter("base_color", Vector3(base.r, base.g, base.b))
	mat.set_shader_parameter("highlight_color", Vector3(highlight.r, highlight.g, highlight.b))
	mat.set_shader_parameter("edge_glow_color", Vector3(edge_glow.r, edge_glow.g, edge_glow.b))


# ---------------------------------------------------------------------------
# Window theming
# ---------------------------------------------------------------------------

func apply_window_chrome(win: Window) -> void:
	## Apply theme-coloured embedded_border StyleBox to a Window.  Idempotent.
	if win == null:
		return
	if win.has_meta(_THEME_META):
		return
	win.set_meta(_THEME_META, true)
	_styled_windows.append(weakref(win))
	_apply_window_style(win)


func _apply_window_style(win: Window) -> void:
	var palette: Dictionary = get_accent_palette()
	var bg: Color = palette.get("panel_bg", Color(0.15, 0.15, 0.15)) as Color
	var border: Color = palette.get("panel_border", Color(0.3, 0.3, 0.3)) as Color
	# embedded_border — effective when embed_subwindows is true
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	win.add_theme_stylebox_override("embedded_border", sb)
	if win is AcceptDialog:
		# AcceptDialog (and ConfirmationDialog) calls draw_style_box("panel", …)
		# in NOTIFICATION_DRAW — before any children are rendered.  Override that
		# stylebox directly so the background is correct without a ColorRect child.
		# A ColorRect child would be rendered AFTER the internal label/button
		# container (INTERNAL_MODE_FRONT children), visually covering the text.
		var panel_sb := StyleBoxFlat.new()
		panel_sb.bg_color = bg
		panel_sb.set_border_width_all(0)
		panel_sb.set_corner_radius_all(0)
		panel_sb.set_content_margin_all(8)
		win.add_theme_stylebox_override("panel", panel_sb)
		# Remove any ColorRect previously inserted by the old code path.
		var old_bg: ColorRect = win.get_node_or_null("_ThemeBG") as ColorRect
		if old_bg != null:
			old_bg.queue_free()
	else:
		# For plain Window nodes, insert a full-rect ColorRect background.
		_ensure_window_bg_rect(win)


func _ensure_window_bg_rect(win: Window) -> void:
	## Add or update a full-rect background ColorRect behind window content.
	var existing: ColorRect = win.get_node_or_null("_ThemeBG") as ColorRect
	if existing != null:
		_apply_bg_material(existing)
		return
	var bg := ColorRect.new()
	bg.name = "_ThemeBG"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	win.move_child(bg, 0)
	_apply_bg_material(bg)
	_bg_rects.append(weakref(bg))


func apply_dialog_panel_style(dialog: Window) -> void:
	## Convenience alias — same as apply_window_chrome for dialogs.
	## Kept for backward compatibility with existing call sites.
	apply_window_chrome(dialog)


# ---------------------------------------------------------------------------
# PopupMenu theming
# ---------------------------------------------------------------------------

func apply_popup_style(popup: PopupMenu, scale: float) -> void:
	## Apply themed panel + font styling to a PopupMenu.  Idempotent.
	if popup == null:
		return
	var palette: Dictionary = get_accent_palette()
	var bg: Color = palette.get("panel_bg", Color(0.15, 0.15, 0.15)) as Color
	var border: Color = palette.get("panel_border", Color(0.3, 0.3, 0.3)) as Color
	var font_col: Color = palette.get("label_tint", Color(0.7, 0.7, 0.7)) as Color
	var hover_bg: Color = palette.get("hover_bg", Color(0.28, 0.28, 0.28)) as Color

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(roundi(4.0 * scale))
	popup.add_theme_stylebox_override("panel", sb)

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = hover_bg
	hover_sb.set_corner_radius_all(3)
	hover_sb.set_content_margin_all(roundi(4.0 * scale))
	popup.add_theme_stylebox_override("hover", hover_sb)

	popup.add_theme_color_override("font_color", font_col)
	popup.add_theme_color_override("font_hover_color", font_col.lightened(0.15))
	popup.add_theme_color_override("font_disabled_color", font_col.darkened(0.4))
	popup.add_theme_color_override("font_separator_color", font_col.darkened(0.3))
	popup.add_theme_font_size_override("font_size", roundi(14.0 * scale))
	popup.add_theme_constant_override("v_separation", roundi(6 * scale))
	popup.add_theme_constant_override("h_separation", roundi(12 * scale))

	if not popup.has_meta(_POPUP_META):
		popup.set_meta(_POPUP_META, true)
		_styled_popups.append(weakref(popup))


# ---------------------------------------------------------------------------
# Recursive tree theming — style every button/panel/window in a subtree
# ---------------------------------------------------------------------------

func theme_control_tree(root: Node, scale: float) -> void:
	## Walk `root` and all descendants, applying themed styles to every
	## BaseButton, PanelContainer, and Window found.  Idempotent per node
	## (uses meta tags to skip already-styled items).
	## The tree is tracked so `on_theme_changed` re-themes it automatically.
	if root == null:
		return
	_theme_node_recursive(root, scale)
	# Track for live refresh (skip duplicates)
	if not root.has_meta(_TREE_META):
		root.set_meta(_TREE_META, true)
		_themed_trees.append({"ref": weakref(root), "scale": scale})


func _theme_node_recursive(node: Node, scale: float) -> void:
	# Skip nodes explicitly opted out of automatic theming
	var skip_style: bool = node is Control and (node as Control).has_meta(SKIP_AUTO_THEME)

	if not skip_style:
		# Buttons
		if node is CheckBox or node is CheckButton:
			apply_check_style(node as BaseButton, scale)
		elif node is OptionButton:
			apply_button_style(node as BaseButton, scale)
			# Theme the internal dropdown popup
			var ob_popup: PopupMenu = (node as OptionButton).get_popup()
			if ob_popup != null:
				apply_popup_style(ob_popup, scale)
		elif node is BaseButton:
			apply_button_style(node as BaseButton, scale)
		# Input controls
		if node is SpinBox:
			var sb_edit: LineEdit = (node as SpinBox).get_line_edit()
			if sb_edit != null:
				_apply_input_style(sb_edit, scale)
		elif node is LineEdit:
			_apply_input_style(node as LineEdit, scale)
		# Labels — ensure text is readable against dark themed backgrounds
		if node is Label:
			var label_palette: Dictionary = get_accent_palette()
			var label_col: Color = label_palette.get("label_tint", Color(0.7, 0.7, 0.7)) as Color
			(node as Label).add_theme_color_override("font_color", label_col)
		# Panels
		if node is PanelContainer:
			apply_chrome(node as PanelContainer)
		# PopupMenu — style panel + font; do NOT insert bg ColorRect
		if node is PopupMenu:
			apply_popup_style(node as PopupMenu, scale)
		elif node is Window:
			apply_window_chrome(node as Window)

	# Always recurse into children — include internal for Windows so we
	# reach AcceptDialog OK/Cancel buttons.
	var include_internal: bool = node is Window
	for child: Node in node.get_children(include_internal):
		_theme_node_recursive(child, scale)


# ---------------------------------------------------------------------------
# Live theme switching — called when service emits theme_changed
# ---------------------------------------------------------------------------

func on_theme_changed(_preset: int) -> void:
	_refresh_panels()
	_refresh_bg_rects()
	_refresh_windows()
	_refresh_styled_buttons()
	_refresh_inputs()
	_refresh_popups()
	_refresh_themed_trees()


func _refresh_panels() -> void:
	var live: Array = []
	for wr: WeakRef in _styled_panels:
		var panel: PanelContainer = wr.get_ref() as PanelContainer
		if panel == null or not is_instance_valid(panel):
			continue
		live.append(wr)
		_apply_panel_style(panel)
	_styled_panels = live


func _refresh_bg_rects() -> void:
	var live: Array = []
	for wr: WeakRef in _bg_rects:
		var cr: ColorRect = wr.get_ref() as ColorRect
		if cr == null or not is_instance_valid(cr):
			continue
		live.append(wr)
		_apply_bg_material(cr)
	_bg_rects = live


func _refresh_windows() -> void:
	var live: Array = []
	for wr: WeakRef in _styled_windows:
		var win: Window = wr.get_ref() as Window
		if win == null or not is_instance_valid(win):
			continue
		live.append(wr)
		_apply_window_style(win)
	_styled_windows = live


func _refresh_styled_buttons() -> void:
	var live: Array = []
	var palette: Dictionary = get_accent_palette()
	var font_col: Color = palette.get("label_tint", Color(0.7, 0.7, 0.7)) as Color
	for wr: WeakRef in _styled_buttons:
		var btn: BaseButton = wr.get_ref() as BaseButton
		if btn == null or not is_instance_valid(btn):
			continue
		live.append(wr)
		if btn.has_meta(SKIP_AUTO_THEME):
			continue
		# CheckBox / CheckButton get transparent-background style
		if btn is CheckBox or btn is CheckButton:
			var existing_c: Variant = btn.get_theme_stylebox("normal")
			var cs: float = 1.0
			if existing_c is StyleBoxFlat:
				var cm_c: int = roundi((existing_c as StyleBoxFlat).content_margin_left)
				if cm_c > 0:
					cs = float(cm_c) / 2.0
			apply_check_style(btn, cs)
			continue
		var existing: Variant = btn.get_theme_stylebox("normal")
		var scale: float = 1.0
		if existing is StyleBoxFlat:
			var cm: int = roundi((existing as StyleBoxFlat).content_margin_left)
			if cm > 0:
				scale = float(cm) / 4.0
		var styles: Dictionary = create_button_styles(scale)
		btn.add_theme_stylebox_override("normal", styles["normal"] as StyleBox)
		btn.add_theme_stylebox_override("hover", styles["hover"] as StyleBox)
		btn.add_theme_stylebox_override("pressed", styles["pressed"] as StyleBox)
		btn.add_theme_stylebox_override("disabled", styles["disabled"] as StyleBox)
		btn.add_theme_color_override("font_color", font_col)
		btn.add_theme_color_override("font_hover_color", font_col.lightened(0.15))
		btn.add_theme_color_override("font_pressed_color", font_col.lightened(0.25))
		btn.add_theme_color_override("font_disabled_color", font_col.darkened(0.4))
	_styled_buttons = live


func _refresh_popups() -> void:
	var live: Array = []
	for wr: WeakRef in _styled_popups:
		var popup: PopupMenu = wr.get_ref() as PopupMenu
		if popup == null or not is_instance_valid(popup):
			continue
		live.append(wr)
		var existing: Variant = popup.get_theme_stylebox("panel")
		var scale: float = 1.0
		if existing is StyleBoxFlat:
			var cm: int = roundi((existing as StyleBoxFlat).content_margin_left)
			if cm > 0:
				scale = float(cm) / 4.0
		apply_popup_style(popup, scale)
	_styled_popups = live


func _refresh_inputs() -> void:
	var live: Array = []
	for wr: WeakRef in _styled_inputs:
		var input: LineEdit = wr.get_ref() as LineEdit
		if input == null or not is_instance_valid(input):
			continue
		live.append(wr)
		var existing: Variant = input.get_theme_stylebox("normal")
		var scale: float = 1.0
		if existing is StyleBoxFlat:
			var cm: int = roundi((existing as StyleBoxFlat).content_margin_left)
			if cm > 0:
				scale = float(cm) / 4.0
		_apply_input_style(input, scale)
	_styled_inputs = live


func _refresh_themed_trees() -> void:
	var live: Array = []
	for entry: Variant in _themed_trees:
		var d: Dictionary = entry as Dictionary
		var wr: WeakRef = d["ref"] as WeakRef
		var node: Node = wr.get_ref() as Node
		if node == null or not is_instance_valid(node):
			continue
		live.append(d)
		# Re-walk — apply_button_style / apply_chrome are idempotent on meta,
		# but _refresh_styled_buttons already updated existing buttons.
		# This catches dynamically-added children since last pass.
		var scale: float = d.get("scale", 1.0) as float
		_theme_node_recursive(node, scale)
	_themed_trees = live
