extends PanelContainer
class_name ToolPalette

# ---------------------------------------------------------------------------
# ToolPalette — Photoshop-style vertical tool palette.
#
# Provides:
#   • Stacked tool buttons (right-click / long-press reveals sub-tool popup)
#   • Toggle groups (Interaction, Map Tools) with exclusive selection
#   • Action stacks (DM Camera, Player View) remember last-used action
#   • Flyout options panel beside the toolbar for tool-specific settings
#   • Section header labels between logical tool clusters
#   • Active-tool highlight styling
# ---------------------------------------------------------------------------

signal tool_activated(tool_key: String)
signal action_fired(action_key: String)
signal fog_mode_changed(fog_id: int, brush_size: float)
signal wall_mode_changed(index: int)
signal spawn_profile_selected(item_idx: int)
signal spawn_auto_assign_requested()
signal move_to_spawns_requested()
signal play_mode_toggled(active: bool)
signal dm_fog_visible_toggled(enabled: bool)
signal flashlights_only_toggled(enabled: bool)
signal effect_tool_activated(effect_type: int)

# ── Public references (DMWindow reads these for state queries) ───────────────
var select_btn: Button = null
var pan_btn: Button = null
var fog_btn: Button = null
var fog_visible_check: CheckBox = null
var play_mode_btn: Button = null
var fog_tool_option: OptionButton = null
var fog_brush_spin: SpinBox = null
var wall_mode_option: OptionButton = null
var spawn_profile_option: OptionButton = null
var spawn_auto_assign_btn: Button = null
var move_to_spawns_btn: Button = null
var token_btn: Button = null
var undock_btn: Button = null

# ── Internal ─────────────────────────────────────────────────────────────────
var _flyout: PanelContainer = null
var _flyout_vbox: VBoxContainer = null
var _tool_group: ButtonGroup = null
var _active_tool_key: String = "select"
var _ui_scale_mgr: UIScaleManager = null ## set by DMWindow during setup
var _ui_theme_mgr: UIThemeManager = null ## set by DMWindow during setup
var _flyout_anchor_node: Control = null ## the button the flyout should align to

# Stacked button state
var _dm_cam_stack_btn: Button = null
var _dm_cam_popup: PopupMenu = null
var _player_view_stack_btn: Button = null
var _player_view_popup: PopupMenu = null
var _wall_stack_btn: Button = null
var _wall_popup: PopupMenu = null
var _effect_stack_btn: Button = null
var _effect_popup: PopupMenu = null
var _selected_effect_type: int = 0 ## EffectData.EffectType value

# Long-press tracking
var _long_press_timer: Timer = null
var _long_press_target: Button = null
var _long_press_activated: bool = false

# Button styles
var _pressed_stylebox: StyleBoxFlat = null
var _compact_btn_styles: Array = [] ## [normal, hover, disabled]

# Fog context widgets
var _fog_context: VBoxContainer = null
# Spawn context widgets
var _spawn_context: VBoxContainer = null

const _LONG_PRESS_SEC: float = 0.4
const _BTN_SIZE: float = 24.0
const _FONT_SIZE: float = 18.0
const _SMALL_FONT: float = 11.0
const _HEADER_FONT: float = 8.0


func setup(ui_scale_mgr: UIScaleManager = null, ui_theme_mgr: UIThemeManager = null) -> void:
	_ui_scale_mgr = ui_scale_mgr
	_ui_theme_mgr = ui_theme_mgr
	_build()


func refresh_theme() -> void:
	## Update all button/panel styles when the active theme changes.
	if _ui_theme_mgr == null:
		return
	var palette: Dictionary = _ui_theme_mgr.get_accent_palette()
	# Panel background
	var panel_sb: Variant = get_theme_stylebox("panel")
	if panel_sb is StyleBoxFlat:
		(panel_sb as StyleBoxFlat).bg_color = palette.get("panel_bg", Color(0.18, 0.18, 0.18)) as Color
	# Rebuild shared button styles from the manager
	var s := _s()
	var new_styles: Dictionary = _ui_theme_mgr.create_button_styles(s)
	if _compact_btn_styles.size() >= 4:
		_compact_btn_styles[0] = new_styles["normal"]
		_compact_btn_styles[1] = new_styles["hover"]
		_compact_btn_styles[2] = new_styles["disabled"]
		_compact_btn_styles[3] = new_styles["pressed"]
	# Update the shared pressed indicator
	if _pressed_stylebox != null:
		var new_pressed: StyleBoxFlat = _ui_theme_mgr.create_pressed_style(s)
		_pressed_stylebox.bg_color = new_pressed.bg_color
		_pressed_stylebox.border_color = new_pressed.border_color
	# Re-apply styles to all buttons in the palette
	_ui_theme_mgr.theme_control_tree(self , s)
	# Re-apply pressed stylebox to toggle buttons (theme_control_tree sets
	# the standard pressed style, but toggles need the shared indicator)
	for btn: Variant in [select_btn, pan_btn, fog_btn, _wall_stack_btn, token_btn, _effect_stack_btn]:
		if btn is Button:
			(btn as Button).add_theme_stylebox_override("pressed", _pressed_stylebox)
	# Section header label tints
	var hdr_tint: Color = _ui_theme_mgr.get_header_tint()
	for child: Node in get_children():
		_refresh_labels_recursive(child, hdr_tint)


func _s() -> float:
	if _ui_scale_mgr != null:
		return _ui_scale_mgr.get_scale()
	return 1.0


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build() -> void:
	var s := _s()

	# Override PanelContainer's own panel stylebox to remove built-in padding
	var panel_style := StyleBoxFlat.new()
	var _palette_accent: Dictionary = UIThemeData.get_accent_palette(
		_ui_theme_mgr.get_theme() if _ui_theme_mgr != null else 0)
	panel_style.bg_color = _palette_accent.get("panel_bg", Color(0.18, 0.18, 0.18, 1.0)) as Color
	panel_style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", panel_style)

	# Constrain palette width (keep in sync with DMWindow._apply_palette_size)
	var palette_w := roundi(34.0 * s)
	custom_minimum_size = Vector2(palette_w, 0)

	# Button StyleBoxes from theme manager (or fallback to defaults)
	if _ui_theme_mgr != null:
		var _theme_styles: Dictionary = _ui_theme_mgr.create_button_styles(s)
		var _compact_normal_sb: StyleBoxFlat = _theme_styles["normal"] as StyleBoxFlat
		var _compact_hover_sb: StyleBoxFlat = _theme_styles["hover"] as StyleBoxFlat
		var _compact_disabled_sb: StyleBoxFlat = _theme_styles["disabled"] as StyleBoxFlat
		var _compact_pressed_sb: StyleBoxFlat = _theme_styles["pressed"] as StyleBoxFlat
		_compact_btn_styles = [_compact_normal_sb, _compact_hover_sb, _compact_disabled_sb, _compact_pressed_sb]
		_pressed_stylebox = _ui_theme_mgr.create_pressed_style(s)
	else:
		var _compact_normal := StyleBoxFlat.new()
		_compact_normal.bg_color = Color(0.22, 0.22, 0.22, 1.0)
		_compact_normal.set_content_margin_all(roundi(4.0 * s))
		_compact_normal.set_corner_radius_all(roundi(6.0 * s))

		var _compact_hover := StyleBoxFlat.new()
		_compact_hover.bg_color = Color(0.28, 0.28, 0.28, 1.0)
		_compact_hover.set_content_margin_all(roundi(4.0 * s))
		_compact_hover.set_corner_radius_all(roundi(6.0 * s))

		var _compact_disabled := StyleBoxFlat.new()
		_compact_disabled.bg_color = Color(0.18, 0.18, 0.18, 1.0)
		_compact_disabled.set_content_margin_all(roundi(4.0 * s))
		_compact_disabled.set_corner_radius_all(roundi(6.0 * s))

		var _compact_pressed := StyleBoxFlat.new()
		_compact_pressed.bg_color = Color(0.3, 0.55, 0.9, 0.35)
		_compact_pressed.set_content_margin_all(roundi(4.0 * s))
		_compact_pressed.set_corner_radius_all(roundi(6.0 * s))

		_compact_btn_styles = [_compact_normal, _compact_hover, _compact_disabled, _compact_pressed]

		_pressed_stylebox = StyleBoxFlat.new()
		_pressed_stylebox.bg_color = Color(0.3, 0.55, 0.9, 0.35)
		_pressed_stylebox.border_color = Color(0.4, 0.65, 1.0, 0.7)
		_pressed_stylebox.border_width_left = roundi(2.0 * s)
		_pressed_stylebox.set_corner_radius_all(roundi(6.0 * s))
		_pressed_stylebox.set_content_margin_all(roundi(4.0 * s))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", roundi(1.0 * s))
	margin.add_theme_constant_override("margin_right", roundi(1.0 * s))
	margin.add_theme_constant_override("margin_top", roundi(1.0 * s))
	margin.add_theme_constant_override("margin_bottom", roundi(1.0 * s))
	add_child(margin)

	var palette_vbox := VBoxContainer.new()
	palette_vbox.add_theme_constant_override("separation", roundi(1.0 * s))
	margin.add_child(palette_vbox)

	# Undock button
	undock_btn = Button.new()
	undock_btn.text = "⇲"
	undock_btn.focus_mode = Control.FOCUS_NONE
	undock_btn.tooltip_text = "Detach / re-dock palette"
	undock_btn.custom_minimum_size = Vector2(0, roundi(10.0 * s))
	undock_btn.add_theme_font_size_override("font_size", roundi(8.0 * s))
	_apply_compact_style(undock_btn)
	palette_vbox.add_child(undock_btn)

	palette_vbox.add_child(HSeparator.new())

	# Tool toggle group (Select / Pan / Fog / Wall / Spawn / Token)
	_tool_group = ButtonGroup.new()

	# Long-press timer
	_long_press_timer = Timer.new()
	_long_press_timer.one_shot = true
	_long_press_timer.wait_time = _LONG_PRESS_SEC
	_long_press_timer.timeout.connect(_on_long_press_timeout)
	add_child(_long_press_timer)

	# ── Section: Interaction ─────────────────────────────────────────────
	_add_section_header(palette_vbox, "INTERACT")

	select_btn = _make_toggle_btn("↖", "Select tool", _tool_group)
	select_btn.button_pressed = true
	select_btn.pressed.connect(func() -> void: _activate_tool("select"))
	select_btn.add_theme_stylebox_override("pressed", _pressed_stylebox)
	palette_vbox.add_child(select_btn)

	pan_btn = _make_toggle_btn("✋", "Pan tool — left-drag to pan", _tool_group)
	pan_btn.pressed.connect(func() -> void: _activate_tool("pan"))
	pan_btn.add_theme_stylebox_override("pressed", _pressed_stylebox)
	palette_vbox.add_child(pan_btn)

	palette_vbox.add_child(HSeparator.new())

	# ── Section: DM Camera (stacked) ────────────────────────────────────
	_add_section_header(palette_vbox, "CAMERA")

	_dm_cam_stack_btn = _make_action_btn("+", "Zoom in (scroll up)")
	palette_vbox.add_child(_dm_cam_stack_btn)

	# Small triangle indicator for stack
	var cam_stack_indicator := _make_stack_indicator()
	_dm_cam_stack_btn.add_child(cam_stack_indicator)

	_dm_cam_popup = PopupMenu.new()
	_dm_cam_popup.add_item("+ Zoom In", 0)
	_dm_cam_popup.add_item("− Zoom Out", 1)
	_dm_cam_popup.add_item("⌂ Reset View", 2)
	_dm_cam_popup.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_dm_cam_popup.id_pressed.connect(_on_dm_cam_popup_selected)
	add_child(_dm_cam_popup)

	_dm_cam_stack_btn.gui_input.connect(func(ev: InputEvent) -> void:
		_handle_stack_input(ev, _dm_cam_stack_btn, _dm_cam_popup))

	palette_vbox.add_child(HSeparator.new())

	# ── Section: Player View (stacked) ──────────────────────────────────
	_add_section_header(palette_vbox, "PLAYER")

	_player_view_stack_btn = _make_action_btn("▣+", "Zoom player viewport in")
	palette_vbox.add_child(_player_view_stack_btn)

	var pv_indicator := _make_stack_indicator()
	_player_view_stack_btn.add_child(pv_indicator)

	_player_view_popup = PopupMenu.new()
	_player_view_popup.add_item("▣+ PV Zoom In", 0)
	_player_view_popup.add_item("▣− PV Zoom Out", 1)
	_player_view_popup.add_item("◎ Sync to DM", 2)
	_player_view_popup.add_item("↺ Rotate CCW", 3)
	_player_view_popup.add_item("↻ Rotate CW", 4)
	_player_view_popup.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_player_view_popup.id_pressed.connect(_on_player_view_popup_selected)
	add_child(_player_view_popup)

	_player_view_stack_btn.gui_input.connect(func(ev: InputEvent) -> void:
		_handle_stack_input(ev, _player_view_stack_btn, _player_view_popup))

	palette_vbox.add_child(HSeparator.new())

	# ── Section: Map Tools ──────────────────────────────────────────────
	_add_section_header(palette_vbox, "TOOLS")

	fog_btn = _make_toggle_btn("☁", "Fog tool (activate to paint fog)", _tool_group)
	fog_btn.pressed.connect(func() -> void: _activate_tool("fog"))
	fog_btn.add_theme_stylebox_override("pressed", _pressed_stylebox)
	palette_vbox.add_child(fog_btn)

	fog_visible_check = CheckBox.new()
	fog_visible_check.text = "🔦"
	fog_visible_check.button_pressed = true
	fog_visible_check.focus_mode = Control.FOCUS_NONE
	fog_visible_check.tooltip_text = "Show/hide DM fog overlay"
	fog_visible_check.custom_minimum_size = Vector2(0, roundi(_BTN_SIZE * s))
	fog_visible_check.add_theme_font_size_override("font_size", roundi(_SMALL_FONT * s))
	fog_visible_check.toggled.connect(func(enabled: bool) -> void: dm_fog_visible_toggled.emit(enabled))
	if _ui_theme_mgr != null:
		_ui_theme_mgr.apply_check_style(fog_visible_check, s)
	palette_vbox.add_child(fog_visible_check)

	var flashlights_check := CheckBox.new()
	flashlights_check.text = "⚡"
	flashlights_check.button_pressed = false
	flashlights_check.focus_mode = Control.FOCUS_NONE
	flashlights_check.tooltip_text = "Flashlights only — disable LOS history, show only live vision cones"
	flashlights_check.custom_minimum_size = Vector2(0, roundi(_BTN_SIZE * s))
	flashlights_check.add_theme_font_size_override("font_size", roundi(_SMALL_FONT * s))
	flashlights_check.toggled.connect(func(on: bool) -> void: flashlights_only_toggled.emit(on))
	if _ui_theme_mgr != null:
		_ui_theme_mgr.apply_check_style(flashlights_check, s)
	palette_vbox.add_child(flashlights_check)

	var fog_reset_btn := _make_action_btn("↺", "Reset fog to fully hidden (covers entire map)")
	fog_reset_btn.pressed.connect(func() -> void: action_fired.emit("fog_reset"))
	palette_vbox.add_child(fog_reset_btn)

	# Wall (stacked — right-click/hold selects Rect or Poly)
	_wall_stack_btn = _make_toggle_btn("▭", "Wall tool — Rectangle", _tool_group)
	_wall_stack_btn.pressed.connect(func() -> void: _activate_wall_tool())
	_wall_stack_btn.add_theme_stylebox_override("pressed", _pressed_stylebox)
	palette_vbox.add_child(_wall_stack_btn)

	var wall_indicator := _make_stack_indicator()
	_wall_stack_btn.add_child(wall_indicator)

	_wall_popup = PopupMenu.new()
	_wall_popup.add_item("▭ Rectangle", 0)
	_wall_popup.add_item("▲ Polygon", 1)
	_wall_popup.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_wall_popup.id_pressed.connect(_on_wall_popup_selected)
	add_child(_wall_popup)

	_wall_stack_btn.gui_input.connect(func(ev: InputEvent) -> void:
		_handle_stack_input(ev, _wall_stack_btn, _wall_popup))

	var spawn_btn := _make_toggle_btn("⚑", "Spawn point tool — click to place, drag to move, right-click to remove", _tool_group)
	spawn_btn.pressed.connect(func() -> void: _activate_tool("spawn_point"))
	spawn_btn.add_theme_stylebox_override("pressed", _pressed_stylebox)
	palette_vbox.add_child(spawn_btn)

	token_btn = _make_toggle_btn("✦", "Token tool — click to place, click existing to select, right-click to edit", _tool_group)
	token_btn.pressed.connect(func() -> void: _activate_tool("token"))
	token_btn.add_theme_stylebox_override("pressed", _pressed_stylebox)
	palette_vbox.add_child(token_btn)

	# Effect (stacked — right-click/hold selects effect type)
	_effect_stack_btn = _make_toggle_btn("FX", "Magic effect tool — %s" % EffectData.EFFECT_LABELS[0], _tool_group)
	_effect_stack_btn.pressed.connect(func() -> void: _activate_effect_tool())
	_effect_stack_btn.add_theme_stylebox_override("pressed", _pressed_stylebox)
	palette_vbox.add_child(_effect_stack_btn)

	var fx_indicator := _make_stack_indicator()
	_effect_stack_btn.add_child(fx_indicator)

	_effect_popup = PopupMenu.new()
	for idx in EffectData.EFFECT_LABELS.size():
		_effect_popup.add_item(EffectData.EFFECT_LABELS[idx], idx)
	_effect_popup.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_effect_popup.id_pressed.connect(_on_effect_popup_selected)
	add_child(_effect_popup)

	_effect_stack_btn.gui_input.connect(func(ev: InputEvent) -> void:
		_handle_stack_input(ev, _effect_stack_btn, _effect_popup))

	palette_vbox.add_child(HSeparator.new())

	# ── Section: Session ────────────────────────────────────────────────
	_add_section_header(palette_vbox, "SESSION")

	play_mode_btn = Button.new()
	play_mode_btn.text = "▶"
	play_mode_btn.toggle_mode = true
	play_mode_btn.focus_mode = Control.FOCUS_NONE
	play_mode_btn.tooltip_text = "Launch the Player display window"
	play_mode_btn.custom_minimum_size = Vector2(0, roundi(_BTN_SIZE * s))
	play_mode_btn.add_theme_font_size_override("font_size", roundi(_FONT_SIZE * s))
	_apply_compact_style(play_mode_btn)
	play_mode_btn.pressed.connect(func() -> void: play_mode_toggled.emit(play_mode_btn.button_pressed))
	palette_vbox.add_child(play_mode_btn)

	move_to_spawns_btn = _make_action_btn("⚑▶", "Move all players to their assigned spawn points")
	move_to_spawns_btn.pressed.connect(func() -> void: move_to_spawns_requested.emit())
	palette_vbox.add_child(move_to_spawns_btn)

	# ── Build context widgets (not yet parented) ────────────────────────
	_build_fog_context()

	_build_spawn_context()

	# ── Flyout panel (initially hidden) ─────────────────────────────────
	_flyout = PanelContainer.new()
	_flyout.name = "ToolFlyout"
	_flyout.visible = false

	_flyout_vbox = VBoxContainer.new()
	_flyout_vbox.add_theme_constant_override("separation", roundi(4.0 * s))
	var flyout_margin := MarginContainer.new()
	flyout_margin.add_theme_constant_override("margin_left", roundi(6.0 * s))
	flyout_margin.add_theme_constant_override("margin_right", roundi(6.0 * s))
	flyout_margin.add_theme_constant_override("margin_top", roundi(6.0 * s))
	flyout_margin.add_theme_constant_override("margin_bottom", roundi(6.0 * s))
	flyout_margin.add_child(_flyout_vbox)
	_flyout.add_child(flyout_margin)


# ---------------------------------------------------------------------------
# Flyout management
# ---------------------------------------------------------------------------

## Call this after adding the flyout to the scene tree (DMWindow adds it to _ui_layer).
func get_flyout() -> PanelContainer:
	return _flyout


func show_flyout_for_tool(tool_key: String, anchor: Control) -> void:
	_flyout_anchor_node = anchor
	# Detach old flyout content
	for child in _flyout_vbox.get_children():
		_flyout_vbox.remove_child(child)

	var ctx: Control = _get_context_for_tool(tool_key)
	if ctx == null:
		_flyout.visible = false
		return

	_flyout_vbox.add_child(ctx)
	_flyout.visible = true
	_position_flyout()


func hide_flyout() -> void:
	for child in _flyout_vbox.get_children():
		_flyout_vbox.remove_child(child)
	_flyout.visible = false


func _position_flyout() -> void:
	if _flyout_anchor_node == null or not _flyout.visible:
		return
	# Place flyout to the right of the toolbar
	var toolbar_rect := get_global_rect()
	var anchor_rect := _flyout_anchor_node.get_global_rect()
	var s := _s()
	_flyout.position = Vector2(
		toolbar_rect.position.x + toolbar_rect.size.x + roundi(4.0 * s),
		anchor_rect.position.y
	)
	# Ensure flyout doesn't go off-screen bottom
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var vp_size := get_viewport().get_visible_rect().size
	if _flyout.position.y + _flyout.size.y > vp_size.y:
		_flyout.position.y = vp_size.y - _flyout.size.y - roundi(8.0 * s)


func _get_context_for_tool(tool_key: String) -> Control:
	match tool_key:
		"fog":
			return _fog_context
		"spawn_point":
			return _spawn_context
		_:
			return null


# ---------------------------------------------------------------------------
# Context widgets (built once, reparented into flyout on demand)
# ---------------------------------------------------------------------------

func _build_fog_context() -> void:
	var s := _s()
	_fog_context = VBoxContainer.new()
	_fog_context.add_theme_constant_override("separation", roundi(4.0 * s))

	var mode_label := Label.new()
	mode_label.text = "Mode"
	mode_label.add_theme_font_size_override("font_size", roundi(_HEADER_FONT * s))
	var _lbl_tint: Color = _ui_theme_mgr.get_label_tint() if _ui_theme_mgr != null else Color(0.7, 0.7, 0.7)
	mode_label.add_theme_color_override("font_color", _lbl_tint)
	_fog_context.add_child(mode_label)

	fog_tool_option = OptionButton.new()
	fog_tool_option.focus_mode = Control.FOCUS_NONE
	fog_tool_option.add_item("R◯ Reveal Brush", 1)
	fog_tool_option.add_item("H◯ Hide Brush", 2)
	fog_tool_option.add_item("R▭ Reveal Rect", 3)
	fog_tool_option.add_item("H▭ Hide Rect", 4)
	fog_tool_option.custom_minimum_size = Vector2(roundi(120.0 * s), roundi(28.0 * s))
	fog_tool_option.add_theme_font_size_override("font_size", roundi(_SMALL_FONT * s))
	fog_tool_option.tooltip_text = "Fog mode: R◯=Reveal brush  H◯=Hide brush  R▭=Reveal rect  H▭=Hide rect"
	fog_tool_option.item_selected.connect(_on_fog_tool_selected)
	_fog_context.add_child(fog_tool_option)

	var brush_label := Label.new()
	brush_label.text = "Brush"
	brush_label.add_theme_font_size_override("font_size", roundi(_HEADER_FONT * s))
	var _brush_tint: Color = _ui_theme_mgr.get_label_tint() if _ui_theme_mgr != null else Color(0.7, 0.7, 0.7)
	brush_label.add_theme_color_override("font_color", _brush_tint)
	_fog_context.add_child(brush_label)

	fog_brush_spin = SpinBox.new()
	fog_brush_spin.min_value = 8
	fog_brush_spin.max_value = 512
	fog_brush_spin.step = 8
	fog_brush_spin.value = 64
	fog_brush_spin.suffix = " px"
	fog_brush_spin.custom_minimum_size = Vector2(roundi(100.0 * s), roundi(28.0 * s))
	fog_brush_spin.add_theme_font_size_override("font_size", roundi(13.0 * s))
	fog_brush_spin.value_changed.connect(_on_fog_brush_changed)
	_fog_context.add_child(fog_brush_spin)


func _build_spawn_context() -> void:
	var s := _s()
	_spawn_context = VBoxContainer.new()
	_spawn_context.add_theme_constant_override("separation", roundi(4.0 * s))

	var profile_label := Label.new()
	profile_label.text = "Profile"
	profile_label.add_theme_font_size_override("font_size", roundi(_HEADER_FONT * s))
	var _prof_tint: Color = _ui_theme_mgr.get_label_tint() if _ui_theme_mgr != null else Color(0.7, 0.7, 0.7)
	profile_label.add_theme_color_override("font_color", _prof_tint)
	_spawn_context.add_child(profile_label)

	spawn_profile_option = OptionButton.new()
	spawn_profile_option.focus_mode = Control.FOCUS_NONE
	spawn_profile_option.tooltip_text = "Assign a player profile to the selected spawn point"
	spawn_profile_option.custom_minimum_size = Vector2(roundi(120.0 * s), roundi(28.0 * s))
	spawn_profile_option.add_theme_font_size_override("font_size", roundi(12.0 * s))
	spawn_profile_option.item_selected.connect(func(idx: int) -> void: spawn_profile_selected.emit(idx))
	_spawn_context.add_child(spawn_profile_option)

	spawn_auto_assign_btn = Button.new()
	spawn_auto_assign_btn.text = "Auto-assign"
	spawn_auto_assign_btn.focus_mode = Control.FOCUS_NONE
	spawn_auto_assign_btn.tooltip_text = "Round-robin assign all profiles to spawn points"
	spawn_auto_assign_btn.custom_minimum_size = Vector2(roundi(120.0 * s), roundi(26.0 * s))
	spawn_auto_assign_btn.add_theme_font_size_override("font_size", roundi(12.0 * s))
	spawn_auto_assign_btn.pressed.connect(func() -> void: spawn_auto_assign_requested.emit())
	_apply_compact_style(spawn_auto_assign_btn)
	_spawn_context.add_child(spawn_auto_assign_btn)


# ---------------------------------------------------------------------------
# Fog / wall context signal forwarders
# ---------------------------------------------------------------------------

func _on_fog_tool_selected(index: int) -> void:
	if fog_tool_option == null:
		return
	var fog_id := fog_tool_option.get_item_id(index)
	var brush := fog_brush_spin.value if fog_brush_spin else 64.0
	fog_mode_changed.emit(fog_id, brush)


func _on_fog_brush_changed(value: float) -> void:
	if fog_tool_option == null:
		return
	var fog_id := fog_tool_option.get_item_id(fog_tool_option.selected)
	fog_mode_changed.emit(fog_id, value)


# ---------------------------------------------------------------------------
# Tool activation
# ---------------------------------------------------------------------------

func _activate_tool(tool_key: String) -> void:
	_active_tool_key = tool_key
	tool_activated.emit(tool_key)
	# Show/hide flyout
	var ctx := _get_context_for_tool(tool_key)
	if ctx != null:
		var anchor := _get_anchor_for_tool(tool_key)
		show_flyout_for_tool(tool_key, anchor)
	else:
		hide_flyout()


func _get_anchor_for_tool(tool_key: String) -> Control:
	match tool_key:
		"fog":
			return fog_btn
		"spawn_point":
			return spawn_profile_option.get_parent().get_parent() if spawn_profile_option else null
		_:
			return null


func get_active_tool() -> String:
	return _active_tool_key


# ---------------------------------------------------------------------------
# Stacked button helpers
# ---------------------------------------------------------------------------

func _handle_stack_input(ev: InputEvent, btn: Button, popup: PopupMenu) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_show_stack_popup(btn, popup)
			btn.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_long_press_activated = false
			_long_press_target = btn
			_long_press_timer.start(_LONG_PRESS_SEC)
			# Consume the press for ALL stack buttons. For toggle buttons this
			# prevents false DRAW_PRESSED highlight during the hold window. For
			# action buttons this also prevents the button getting stuck in
			# DRAW_PRESSED when the popup opens and grabs input (so mouse-up
			# never arrives back through gui_input).
			btn.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_long_press_timer.stop()
			if _long_press_activated:
				# Popup was shown — native handling already suppressed by
				# consuming the press; nothing more to do.
				pass
			else:
				# Quick click — press was consumed, so fire the action manually.
				_fire_stack_quick_action(btn)
			_long_press_activated = false
			_long_press_target = null


func _on_long_press_timeout() -> void:
	# Set flag before showing popup so the arriving mouse-up event is
	# suppressed and doesn't spuriously toggle the button state.
	_long_press_activated = true
	if _long_press_target == _dm_cam_stack_btn:
		_show_stack_popup(_dm_cam_stack_btn, _dm_cam_popup)
	elif _long_press_target == _player_view_stack_btn:
		_show_stack_popup(_player_view_stack_btn, _player_view_popup)
	elif _long_press_target == _wall_stack_btn:
		_show_stack_popup(_wall_stack_btn, _wall_popup)
	elif _long_press_target == _effect_stack_btn:
		_show_stack_popup(_effect_stack_btn, _effect_popup)
	_long_press_target = null


func _show_stack_popup(btn: Button, popup: PopupMenu) -> void:
	var btn_rect := btn.get_global_rect()
	popup.position = Vector2i(
		roundi(btn_rect.position.x + btn_rect.size.x + 2.0),
		roundi(btn_rect.position.y)
	)
	popup.popup()


# ── DM Camera stack ─────────────────────────────────────────────────────────

var _dm_cam_action_keys: Array[String] = ["dm_zoom_in", "dm_zoom_out", "dm_reset_view"]
var _dm_cam_labels: Array[String] = ["+", "−", "⌂"]
var _dm_cam_tips: Array[String] = ["Zoom in (scroll up)", "Zoom out (scroll down)", "Reset view"]
var _dm_cam_current: int = 0

func _on_dm_cam_popup_selected(id: int) -> void:
	_dm_cam_current = id
	_dm_cam_stack_btn.text = _dm_cam_labels[id]
	_dm_cam_stack_btn.tooltip_text = _dm_cam_tips[id]
	action_fired.emit(_dm_cam_action_keys[id])


# ── Player View stack ───────────────────────────────────────────────────────

var _pv_action_keys: Array[String] = ["pv_zoom_in", "pv_zoom_out", "pv_sync", "pv_rotate_ccw", "pv_rotate_cw"]
var _pv_labels: Array[String] = ["▣+", "▣−", "◎", "↺", "↻"]
var _pv_tips: Array[String] = [
	"Zoom player viewport in",
	"Zoom player viewport out",
	"Sync player view to DM",
	"Rotate player view CCW 90°",
	"Rotate player view CW 90°",
]
var _pv_current: int = 0

func _on_player_view_popup_selected(id: int) -> void:
	_pv_current = id
	_player_view_stack_btn.text = _pv_labels[id]
	_player_view_stack_btn.tooltip_text = _pv_tips[id]
	action_fired.emit(_pv_action_keys[id])


func _fire_player_view_action() -> void:
	action_fired.emit(_pv_action_keys[_pv_current])


# ── Wall stack ───────────────────────────────────────────────────────────────

var _wall_labels: Array[String] = ["▭", "▲"]
var _wall_tips: Array[String] = ["Wall tool — Rectangle", "Wall tool — Polygon"]
var _wall_current: int = 0

func _activate_wall_tool() -> void:
	_active_tool_key = "wall"
	tool_activated.emit("wall")
	wall_mode_changed.emit(_wall_current)
	hide_flyout()


func _on_wall_popup_selected(id: int) -> void:
	_wall_current = id
	_wall_stack_btn.text = _wall_labels[id]
	_wall_stack_btn.tooltip_text = _wall_tips[id]
	# Activate the wall tool with the new mode
	_set_active_toggle_btn(_wall_stack_btn)
	_activate_wall_tool()


func _set_active_toggle_btn(btn: Button) -> void:
	## Explicitly sync the tool ButtonGroup: set btn pressed, all others not pressed.
	## Uses set_pressed_no_signal to avoid emitting 'pressed' (activation is
	## handled by the caller directly), and to reliably deselect other buttons
	## regardless of ButtonGroup internals in the current Godot version.
	for b: Button in _tool_group.get_buttons():
		b.set_pressed_no_signal(b == btn)


func _fire_stack_quick_action(btn: Button) -> void:
	## Called on quick-click release of any stack button when the press was
	## consumed to prevent DRAW_PRESSED from getting stuck.
	if btn == _wall_stack_btn:
		_set_active_toggle_btn(btn)
		_activate_wall_tool()
	elif btn == _effect_stack_btn:
		_set_active_toggle_btn(btn)
		_activate_effect_tool()
	elif btn == _dm_cam_stack_btn:
		action_fired.emit(_dm_cam_action_keys[_dm_cam_current])
	elif btn == _player_view_stack_btn:
		_fire_player_view_action()


func _activate_effect_tool() -> void:
	_active_tool_key = "effect"
	tool_activated.emit("effect")
	effect_tool_activated.emit(_selected_effect_type)
	hide_flyout()


func _on_effect_popup_selected(id: int) -> void:
	_selected_effect_type = id
	var label: String = EffectData.EFFECT_LABELS[id] if id < EffectData.EFFECT_LABELS.size() else "FX"
	_effect_stack_btn.tooltip_text = "Magic effect tool — %s" % label
	_set_active_toggle_btn(_effect_stack_btn)
	_activate_effect_tool()


func get_selected_effect_type() -> int:
	return _selected_effect_type


func is_effect_burst_mode() -> bool:
	return false


# ---------------------------------------------------------------------------
# Button factory helpers
# ---------------------------------------------------------------------------

func _apply_compact_style(btn: Button) -> void:
	if _ui_theme_mgr != null:
		_ui_theme_mgr.apply_button_style(btn, _s())
	elif _compact_btn_styles.size() >= 4:
		btn.add_theme_stylebox_override("normal", _compact_btn_styles[0])
		btn.add_theme_stylebox_override("hover", _compact_btn_styles[1])
		btn.add_theme_stylebox_override("disabled", _compact_btn_styles[2])
		btn.add_theme_stylebox_override("pressed", _compact_btn_styles[3])
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _make_toggle_btn(label: String, tip: String, group: ButtonGroup) -> Button:
	var s := _s()
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, roundi(_BTN_SIZE * s))
	b.add_theme_font_size_override("font_size", roundi(_FONT_SIZE * s))
	_apply_compact_style(b)
	return b


func _make_action_btn(label: String, tip: String) -> Button:
	var s := _s()
	var b := Button.new()
	b.text = label
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, roundi(_BTN_SIZE * s))
	b.add_theme_font_size_override("font_size", roundi(_FONT_SIZE * s))
	_apply_compact_style(b)
	return b


func _make_stack_indicator() -> Control:
	var s := _s()
	var indicator := Label.new()
	indicator.text = "▾"
	indicator.add_theme_font_size_override("font_size", roundi(8.0 * s))
	indicator.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
	indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	indicator.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	indicator.anchor_left = 0.0
	indicator.anchor_right = 1.0
	indicator.anchor_top = 0.0
	indicator.anchor_bottom = 1.0
	indicator.offset_right = roundi(-2.0 * s)
	indicator.offset_bottom = roundi(-1.0 * s)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return indicator


func _add_section_header(parent: Control, text: String) -> void:
	var s := _s()
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", roundi(_HEADER_FONT * s))
	var header_tint: Color = _ui_theme_mgr.get_header_tint() if _ui_theme_mgr != null else Color(0.55, 0.55, 0.55)
	lbl.add_theme_color_override("font_color", header_tint)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)


func _refresh_labels_recursive(node: Node, tint: Color) -> void:
	if node is Label:
		var l: Label = node as Label
		if l.has_theme_color_override("font_color"):
			l.add_theme_color_override("font_color", tint)
	for child: Node in node.get_children():
		_refresh_labels_recursive(child, tint)
