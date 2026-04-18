extends HBoxContainer
class_name InitiativeEntry

## A single row in the initiative tracker panel.
##
## Displays: [initiative value] [token name] [HP bar] [quick action buttons]

signal initiative_value_changed(token_id: String, value: int)
signal damage_requested(token_id: String)
signal heal_requested(token_id: String)
signal delay_requested(token_id: String)
signal remove_requested(token_id: String)

var _token_id: String = ""
var _is_current_turn: bool = false
var _is_map_selected: bool = false

var _init_spin: SpinBox = null
var _name_label: Label = null
var _hp_bar: ProgressBar = null
var _hp_label: Label = null
var _condition_container: HBoxContainer = null
var _dmg_btn: Button = null
var _heal_btn: Button = null
var _delay_btn: Button = null
var _remove_btn: Button = null
var _bg_panel: PanelContainer = null
var _row: HBoxContainer = null
var _hp_box: VBoxContainer = null
## Scale remembered for pill rebuilds.
var _current_scale: float = 1.0


func _ready() -> void:
	_build_ui()


## Called by InitiativePanel on every scale change.
func apply_scale(s: float) -> void:
	var si := func(base: float) -> int: return roundi(base * s)
	custom_minimum_size.y = si.call(36.0)
	if _row != null:
		_row.add_theme_constant_override("separation", si.call(4.0))
	if _init_spin != null:
		_init_spin.custom_minimum_size.x = si.call(52.0)
		_init_spin.get_line_edit().add_theme_font_size_override("font_size", si.call(12.0))
	if _name_label != null:
		_name_label.add_theme_font_size_override("font_size", si.call(12.0))
	if _hp_box != null:
		_hp_box.custom_minimum_size.x = si.call(54.0)
	if _hp_bar != null:
		_hp_bar.custom_minimum_size = Vector2(si.call(54.0), si.call(10.0))
	if _hp_label != null:
		_hp_label.add_theme_font_size_override("font_size", si.call(10.0))
	if _condition_container != null:
		for child: Node in _condition_container.get_children():
			if child is PanelContainer:
				for inner: Node in child.get_children():
					if inner is Label:
						(inner as Label).add_theme_font_size_override(
							"font_size", si.call(9.0))
	_current_scale = s
	for btn: Button in [_dmg_btn, _heal_btn, _delay_btn, _remove_btn]:
		if btn != null:
			btn.custom_minimum_size = Vector2(si.call(26.0), si.call(26.0))
			btn.add_theme_font_size_override("font_size", si.call(13.0))


func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = 36.0

	# Background panel for turn highlight.
	# Skip auto-theming so _update_turn_highlight() always owns the stylebox.
	_bg_panel = PanelContainer.new()
	_bg_panel.set_meta("ui_theme_skip_auto", true)
	_bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bg_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_bg_panel)

	_row = HBoxContainer.new()
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_theme_constant_override("separation", 4)
	_bg_panel.add_child(_row)

	# Initiative value spinner.
	_init_spin = SpinBox.new()
	_init_spin.min_value = -10
	_init_spin.max_value = 40
	_init_spin.step = 1
	_init_spin.custom_minimum_size.x = 52.0
	_init_spin.value_changed.connect(_on_init_changed)
	_init_spin.tooltip_text = "Initiative"
	_row.add_child(_init_spin)

	# Token name. Skip auto-theming so _update_turn_highlight() owns the colour.
	_name_label = Label.new()
	_name_label.set_meta("ui_theme_skip_auto", true)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	_name_label.text = "—"
	_row.add_child(_name_label)

	# HP bar + label stacked.
	_hp_box = VBoxContainer.new()
	_hp_box.custom_minimum_size.x = 54.0
	_hp_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_hp_box)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(54.0, 10.0)
	_hp_bar.show_percentage = false
	_hp_box.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 11)
	_hp_box.add_child(_hp_label)

	# Conditions — compact pill badges. Hidden when empty so it takes no space.
	_condition_container = HBoxContainer.new()
	_condition_container.add_theme_constant_override("separation", 2)
	_condition_container.visible = false
	_row.add_child(_condition_container)

	# Quick action buttons.
	_dmg_btn = Button.new()
	_dmg_btn.text = "⚔"
	_dmg_btn.tooltip_text = "Apply Damage"
	_dmg_btn.custom_minimum_size = Vector2(26.0, 26.0)
	_dmg_btn.pressed.connect(func() -> void: damage_requested.emit(_token_id))
	_row.add_child(_dmg_btn)

	_heal_btn = Button.new()
	_heal_btn.text = "♥"
	_heal_btn.tooltip_text = "Apply Healing"
	_heal_btn.custom_minimum_size = Vector2(26.0, 26.0)
	_heal_btn.pressed.connect(func() -> void: heal_requested.emit(_token_id))
	_row.add_child(_heal_btn)

	_delay_btn = Button.new()
	_delay_btn.text = "⏳"
	_delay_btn.tooltip_text = "Delay Turn"
	_delay_btn.custom_minimum_size = Vector2(26.0, 26.0)
	_delay_btn.pressed.connect(func() -> void: delay_requested.emit(_token_id))
	_row.add_child(_delay_btn)

	_remove_btn = Button.new()
	_remove_btn.text = "✕"
	_remove_btn.tooltip_text = "Remove from Combat"
	_remove_btn.custom_minimum_size = Vector2(26.0, 26.0)
	_remove_btn.pressed.connect(func() -> void: remove_requested.emit(_token_id))
	_row.add_child(_remove_btn)


## Update whether this entry's token is currently selected on the map.
func set_map_selected(selected: bool) -> void:
	_is_map_selected = selected
	_update_turn_highlight()


func set_data(token_id: String, token_name: String, initiative: int,
		current_hp: int, max_hp: int, temp_hp: int, conditions: Array,
		is_current: bool) -> void:
	_token_id = token_id
	_is_current_turn = is_current

	if _init_spin != null:
		_init_spin.set_value_no_signal(float(initiative))
	if _name_label != null:
		_name_label.text = token_name if not token_name.is_empty() else token_id

	_update_hp_display(current_hp, max_hp, temp_hp)
	_update_conditions(conditions)
	_update_turn_highlight()


func _update_hp_display(current: int, max_val: int, temp: int) -> void:
	if _hp_bar != null:
		_hp_bar.max_value = float(maxi(max_val, 1))
		_hp_bar.value = float(current)
		# Color-coded HP bar.
		var ratio: float = float(current) / float(maxi(max_val, 1))
		var bar_color: Color
		if current <= 0:
			bar_color = Color(0.15, 0.15, 0.15)
		elif ratio < 0.25:
			bar_color = Color(0.85, 0.15, 0.15)
		elif ratio < 0.5:
			bar_color = Color(0.9, 0.75, 0.1)
		else:
			bar_color = Color(0.2, 0.75, 0.2)
		var fill_sb := StyleBoxFlat.new()
		fill_sb.bg_color = bar_color
		fill_sb.corner_radius_top_left = 2
		fill_sb.corner_radius_top_right = 2
		fill_sb.corner_radius_bottom_left = 2
		fill_sb.corner_radius_bottom_right = 2
		_hp_bar.add_theme_stylebox_override("fill", fill_sb)

	if _hp_label != null:
		var text: String = "%d/%d" % [current, max_val]
		if temp > 0:
			text += " +%d" % temp
		_hp_label.text = text


func _update_conditions(conditions: Array) -> void:
	if _condition_container == null:
		return
	# Clear existing pills.
	for child: Node in _condition_container.get_children():
		child.queue_free()
	if conditions.is_empty():
		_condition_container.visible = false
		return
	var pill_font_size: int = maxi(8, roundi(9.0 * _current_scale))
	for raw_entry: Variant in conditions:
		var cname: String = ""
		if raw_entry is String:
			cname = raw_entry as String
		elif raw_entry is Dictionary:
			cname = str((raw_entry as Dictionary).get("name", ""))
		if cname.is_empty():
			continue
		var pill := PanelContainer.new()
		var pill_sb := StyleBoxFlat.new()
		pill_sb.bg_color = ConditionRules.get_color(cname)
		pill_sb.corner_radius_top_left = 3
		pill_sb.corner_radius_top_right = 3
		pill_sb.corner_radius_bottom_left = 3
		pill_sb.corner_radius_bottom_right = 3
		pill_sb.content_margin_left = 3.0
		pill_sb.content_margin_right = 3.0
		pill_sb.content_margin_top = 1.0
		pill_sb.content_margin_bottom = 1.0
		pill.add_theme_stylebox_override("panel", pill_sb)
		var lbl := Label.new()
		lbl.text = ConditionRules.get_abbrev(cname)
		lbl.add_theme_font_size_override("font_size", pill_font_size)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.tooltip_text = ConditionRules.get_label(cname)
		pill.tooltip_text = ConditionRules.get_label(cname)
		pill.add_child(lbl)
		_condition_container.add_child(pill)
	_condition_container.visible = true


func _update_turn_highlight() -> void:
	if _bg_panel == null:
		return
	var sb := StyleBoxFlat.new()
	if _is_current_turn:
		sb.bg_color = Color(0.75, 0.55, 0.05, 0.45)
		sb.border_color = Color(1.0, 0.85, 0.2, 1.0)
		sb.border_width_left = 4
		sb.border_width_right = 4
		sb.border_width_top = 4
		sb.border_width_bottom = 4
	elif _is_map_selected:
		sb.bg_color = Color(0.15, 0.35, 0.7, 0.3)
		sb.border_color = Color(0.4, 0.7, 1.0, 1.0)
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.border_width_top = 3
		sb.border_width_bottom = 3
	else:
		sb.bg_color = Color(0.12, 0.12, 0.14, 0.6)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	_bg_panel.add_theme_stylebox_override("panel", sb)
	# Make current-turn name bold/bright, others dimmer.
	# Always use an explicit override (never remove) because auto-theming is
	# skipped on _name_label via the ui_theme_skip_auto meta.
	if _name_label != null:
		if _is_current_turn:
			_name_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5, 1.0))
		elif _is_map_selected:
			_name_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0, 1.0))
		else:
			_name_label.add_theme_color_override("font_color", Color(0.80, 0.80, 0.80, 1.0))


## Scroll the parent ScrollContainer so this entry is visible.
## Called deferred from InitiativePanel._scroll_to_active_entry.
func _scroll_into_view(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	var entry_top: float = position.y
	var entry_bot: float = entry_top + size.y
	var view_top: float = scroll.scroll_vertical
	var view_bot: float = view_top + scroll.size.y
	if entry_top < view_top:
		scroll.scroll_vertical = int(entry_top)
	elif entry_bot > view_bot:
		scroll.scroll_vertical = int(entry_bot - scroll.size.y)


func _on_init_changed(value: float) -> void:
	initiative_value_changed.emit(_token_id, int(value))
