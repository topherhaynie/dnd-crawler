extends PanelContainer
class_name DiceTray

# ---------------------------------------------------------------------------
# DiceTray — persistent dice tray panel for the DM window.
#
# Features:
#   - Text field for arbitrary dice expressions ("2d6+3", "4d6kh3")
#   - Quick die buttons: d4, d6, d8, d10, d12, d20
#   - Modifier +/- spinner
#   - Roll button (uses current roll mode)
#   - Roll history display (last N rolls)
#   - Animated / Fast mode toggle
# ---------------------------------------------------------------------------

signal roll_requested(expression: String, context: Dictionary)

var _ui_scale_mgr: UIScaleManager = null
var _ui_theme_mgr: UIThemeManager = null
var _dice_mgr: DiceManager = null

var _vbox: VBoxContainer = null
var _expression_edit: LineEdit = null
var _modifier_spin: SpinBox = null
var _roll_btn: Button = null
var _clear_btn: Button = null
var _mode_check: CheckButton = null
var _history_list: RichTextLabel = null
var _undock_btn: Button = null

const DIE_TYPES: Array = [4, 6, 8, 10, 12, 20]
const MAX_VISIBLE_HISTORY: int = 20

var _rebuilding: bool = false


func setup(mgr: UIScaleManager, theme_mgr: UIThemeManager = null, dice_mgr: DiceManager = null) -> void:
	_ui_scale_mgr = mgr
	_ui_theme_mgr = theme_mgr
	_dice_mgr = dice_mgr
	_build()
	if _dice_mgr != null and _dice_mgr.service != null:
		# Signal subscription — approved exception (see architecture.instructions.md)
		_dice_mgr.service.roll_completed.connect(_on_roll_completed)


func refresh_theme() -> void:
	if _ui_theme_mgr == null:
		return
	var palette: Dictionary = _ui_theme_mgr.get_accent_palette()
	var panel_bg: Color = palette.get("panel_bg", Color(0.15, 0.15, 0.15, 0.95)) as Color
	var panel_border: Color = palette.get("panel_border", Color(0.3, 0.3, 0.3)) as Color
	var hdr_tint: Color = _ui_theme_mgr.get_header_tint()
	var bg_sb: Variant = get_theme_stylebox("panel")
	if bg_sb is StyleBoxFlat:
		(bg_sb as StyleBoxFlat).bg_color = panel_bg
		(bg_sb as StyleBoxFlat).border_color = panel_border
	_ui_theme_mgr.theme_control_tree(self , _s())
	# Header label tints
	if _vbox != null:
		for child: Node in _vbox.get_children():
			if child is Label:
				var lbl: Label = child as Label
				if lbl.text in ["DICE TRAY", "HISTORY"]:
					lbl.add_theme_color_override("font_color", hdr_tint)


func _s() -> float:
	if _ui_scale_mgr != null:
		return _ui_scale_mgr.get_scale()
	return 1.0


func _si(base: float) -> int:
	return roundi(base * _s())


func _build() -> void:
	var s: float = _s()
	name = "DiceTray"

	# Dark panel background
	var accent: Dictionary = UIThemeData.get_accent_palette(
		_ui_theme_mgr.get_theme() if _ui_theme_mgr != null else 0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = accent.get("panel_bg", Color(0.15, 0.15, 0.15, 0.95)) as Color
	bg.border_color = accent.get("panel_border", Color(0.3, 0.3, 0.3)) as Color
	bg.set_border_width_all(1)
	bg.set_content_margin_all(roundi(6.0 * s))
	add_theme_stylebox_override("panel", bg)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", _si(4.0))
	add_child(_vbox)

	# --- Header row ---
	var header_row := HBoxContainer.new()
	var header := Label.new()
	header.text = "DICE TRAY"
	header.add_theme_font_size_override("font_size", _si(12.0))
	header_row.add_child(header)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	_undock_btn = Button.new()
	_undock_btn.text = "⇱"
	_undock_btn.tooltip_text = "Undock"
	_undock_btn.add_theme_font_size_override("font_size", _si(11.0))
	_undock_btn.custom_minimum_size = Vector2(_si(22.0), _si(22.0))
	header_row.add_child(_undock_btn)
	_vbox.add_child(header_row)

	# --- Expression input ---
	_expression_edit = LineEdit.new()
	_expression_edit.placeholder_text = "e.g. 2d6+3"
	_expression_edit.add_theme_font_size_override("font_size", _si(13.0))
	_expression_edit.custom_minimum_size = Vector2(0, _si(28.0))
	_expression_edit.text_submitted.connect(_on_expression_submitted)
	_vbox.add_child(_expression_edit)

	# --- Quick die buttons ---
	var die_row := HBoxContainer.new()
	die_row.add_theme_constant_override("separation", _si(2.0))
	for sides: Variant in DIE_TYPES:
		var btn := Button.new()
		btn.text = "d%d" % [int(sides)]
		btn.add_theme_font_size_override("font_size", _si(11.0))
		btn.custom_minimum_size = Vector2(_si(32.0), _si(26.0))
		btn.tooltip_text = "Add d%d to expression" % [int(sides)]
		btn.pressed.connect(_on_die_button_pressed.bind(int(sides)))
		die_row.add_child(btn)
	_vbox.add_child(die_row)

	# --- Modifier row ---
	var mod_row := HBoxContainer.new()
	mod_row.add_theme_constant_override("separation", _si(4.0))
	var mod_label := Label.new()
	mod_label.text = "Mod:"
	mod_label.add_theme_font_size_override("font_size", _si(12.0))
	mod_row.add_child(mod_label)
	_modifier_spin = SpinBox.new()
	_modifier_spin.min_value = -20
	_modifier_spin.max_value = 20
	_modifier_spin.step = 1
	_modifier_spin.value = 0
	_modifier_spin.custom_minimum_size = Vector2(_si(60.0), 0)
	_modifier_spin.get_line_edit().add_theme_font_size_override("font_size", _si(12.0))
	mod_row.add_child(_modifier_spin)
	var mod_spacer := Control.new()
	mod_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mod_row.add_child(mod_spacer)
	_mode_check = CheckButton.new()
	_mode_check.text = "3D"
	_mode_check.tooltip_text = "Toggle animated 3D dice"
	_mode_check.add_theme_font_size_override("font_size", _si(11.0))
	_mode_check.button_pressed = false
	_mode_check.toggled.connect(_on_mode_toggled)
	mod_row.add_child(_mode_check)
	_vbox.add_child(mod_row)

	# --- Roll / Clear buttons ---
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", _si(4.0))
	_roll_btn = Button.new()
	_roll_btn.text = "Roll"
	_roll_btn.add_theme_font_size_override("font_size", _si(13.0))
	_roll_btn.custom_minimum_size = Vector2(_si(60.0), _si(28.0))
	_roll_btn.pressed.connect(_on_roll_pressed)
	btn_row.add_child(_roll_btn)
	var adv_btn := Button.new()
	adv_btn.text = "Adv"
	adv_btn.tooltip_text = "Roll with advantage (twice, take higher)"
	adv_btn.add_theme_font_size_override("font_size", _si(11.0))
	adv_btn.custom_minimum_size = Vector2(_si(40.0), _si(28.0))
	adv_btn.pressed.connect(_on_advantage_pressed)
	btn_row.add_child(adv_btn)
	var dis_btn := Button.new()
	dis_btn.text = "Dis"
	dis_btn.tooltip_text = "Roll with disadvantage (twice, take lower)"
	dis_btn.add_theme_font_size_override("font_size", _si(11.0))
	dis_btn.custom_minimum_size = Vector2(_si(40.0), _si(28.0))
	dis_btn.pressed.connect(_on_disadvantage_pressed)
	btn_row.add_child(dis_btn)
	var btn_spacer := Control.new()
	btn_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(btn_spacer)
	_clear_btn = Button.new()
	_clear_btn.text = "Clear"
	_clear_btn.add_theme_font_size_override("font_size", _si(11.0))
	_clear_btn.custom_minimum_size = Vector2(_si(48.0), _si(28.0))
	_clear_btn.pressed.connect(_on_clear_pressed)
	btn_row.add_child(_clear_btn)
	_vbox.add_child(btn_row)

	_vbox.add_child(HSeparator.new())

	# --- History header ---
	var hist_hdr := Label.new()
	hist_hdr.text = "HISTORY"
	hist_hdr.add_theme_font_size_override("font_size", _si(10.0))
	_vbox.add_child(hist_hdr)

	# --- History display ---
	_history_list = RichTextLabel.new()
	_history_list.bbcode_enabled = true
	_history_list.fit_content = false
	_history_list.scroll_following = true
	_history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_list.custom_minimum_size = Vector2(0, _si(100.0))
	_history_list.add_theme_font_size_override("normal_font_size", _si(11.0))
	_history_list.add_theme_font_size_override("bold_font_size", _si(11.0))
	_vbox.add_child(_history_list)


# --- Expression helpers ---

func _get_full_expression() -> String:
	var base: String = _expression_edit.text.strip_edges() if _expression_edit != null else ""
	if base.is_empty():
		return ""
	var mod: int = int(_modifier_spin.value) if _modifier_spin != null else 0
	if mod > 0:
		return "%s+%d" % [base, mod]
	elif mod < 0:
		return "%s%d" % [base, mod]
	return base


# --- Signal handlers ---

func _on_die_button_pressed(sides: int) -> void:
	if _expression_edit == null:
		return
	var current: String = _expression_edit.text.strip_edges()
	if current.is_empty():
		_expression_edit.text = "1d%d" % sides
	else:
		# Check if last segment is same die type to increment count
		var regex := RegEx.new()
		var err: int = regex.compile("(\\d+)d%d$" % sides)
		if err == OK:
			var m: RegExMatch = regex.search(current)
			if m != null:
				var old_count: int = int(m.get_string(1))
				_expression_edit.text = current.substr(0, m.get_start()) + "%dd%d" % [old_count + 1, sides]
				return
		_expression_edit.text = current + "+1d%d" % sides


func _on_expression_submitted(_text: String) -> void:
	_do_roll()


func _on_roll_pressed() -> void:
	_do_roll()


func _on_advantage_pressed() -> void:
	var expr: String = _get_full_expression()
	if expr.is_empty():
		return
	if _dice_mgr != null:
		_dice_mgr.roll_with_advantage(expr, {"source": "dice_tray", "roll_type": "advantage"})
	roll_requested.emit(expr, {"roll_type": "advantage"})


func _on_disadvantage_pressed() -> void:
	var expr: String = _get_full_expression()
	if expr.is_empty():
		return
	if _dice_mgr != null:
		_dice_mgr.roll_with_disadvantage(expr, {"source": "dice_tray", "roll_type": "disadvantage"})
	roll_requested.emit(expr, {"roll_type": "disadvantage"})


func _on_mode_toggled(pressed: bool) -> void:
	if _dice_mgr != null:
		_dice_mgr.set_roll_mode(pressed)


func _on_clear_pressed() -> void:
	if _expression_edit != null:
		_expression_edit.text = ""
	if _modifier_spin != null:
		_modifier_spin.value = 0
	if _dice_mgr != null:
		_dice_mgr.clear_roll_history()
	if _history_list != null:
		_history_list.clear()


func _do_roll() -> void:
	var expr: String = _get_full_expression()
	if expr.is_empty():
		return
	if _dice_mgr != null:
		_dice_mgr.roll(expr, {"source": "dice_tray"})
	roll_requested.emit(expr, {})


func _on_roll_completed(result: DiceResult) -> void:
	_append_history_entry(result)


func append_remote_roll(player_name: String, result: DiceResult) -> void:
	_append_history_entry(result, player_name)


func _append_history_entry(result: DiceResult, player_name: String = "") -> void:
	if _history_list == null:
		return
	var rolls_str: String = ""
	for group_idx: int in range(result.individual_rolls.size()):
		var group: Array = result.individual_rolls[group_idx]
		if group_idx > 0:
			rolls_str += " + "
		rolls_str += "["
		for i: int in range(group.size()):
			if i > 0:
				rolls_str += ", "
			rolls_str += str(group[i])
		rolls_str += "]"
	if result.modifiers != 0:
		if result.modifiers > 0:
			rolls_str += " +%d" % result.modifiers
		else:
			rolls_str += " %d" % result.modifiers

	var color: String = "#FFFFFF"
	if result.is_critical:
		color = "#FFD700"
	elif result.is_fumble:
		color = "#FF4444"

	var crit_tag: String = ""
	if result.is_critical:
		crit_tag = " [b][color=#FFD700]NAT 20![/color][/b]"
	elif result.is_fumble:
		crit_tag = " [b][color=#FF4444]NAT 1![/color][/b]"

	var prefix: String = ""
	if not player_name.is_empty():
		prefix = "[color=#88BBFF]%s:[/color] " % player_name

	var line: String = "%s[b]%s[/b] → [color=%s]%d[/color] %s%s" % [
		prefix, result.expression, color, result.total, rolls_str, crit_tag]
	_history_list.append_text(line + "\n")

	# Trim old entries (guard against re-entrant rebuild)
	var line_count: int = _history_list.get_line_count()
	if not _rebuilding and line_count > MAX_VISIBLE_HISTORY * 2:
		# RichTextLabel doesn't support removing lines easily;
		# rebuild from service history instead.
		_rebuild_history_from_service()


func _rebuild_history_from_service() -> void:
	if _history_list == null or _dice_mgr == null:
		return
	_rebuilding = true
	_history_list.clear()
	var history: Array = _dice_mgr.get_roll_history()
	# Show most recent MAX_VISIBLE_HISTORY entries (history is newest-first)
	var show_count: int = mini(history.size(), MAX_VISIBLE_HISTORY)
	for i: int in range(show_count - 1, -1, -1):
		var entry: Dictionary = history[i] as Dictionary
		var result_dict: Variant = entry.get("result", {})
		if result_dict is Dictionary:
			var r: DiceResult = DiceResult.from_dict(result_dict as Dictionary)
			_append_history_entry(r)
	_rebuilding = false
