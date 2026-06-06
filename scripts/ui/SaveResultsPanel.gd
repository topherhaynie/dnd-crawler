extends Window
class_name SaveResultsPanel

## Modal dialog showing batch saving throw results with override and damage
## preview/application controls.
##
## Opened by DMWindow after CombatService.call_for_save().
## Emits apply_damage_to_results when the DM applies damage and conditions
## based on results.

signal apply_damage_to_results(results: Array, damage_rows: Array, condition_rows: Array)
signal closed

var _ability: String = ""
var _dc: int = 0
var _results: Array = []

# UI nodes
var _table_container: VBoxContainer = null
var _table_panel: VBoxContainer = null
var _summary_label: Label = null
var _damage_rows_box: VBoxContainer = null
var _damage_rows_header: Label = null
var _add_damage_packet_btn: Button = null
var _condition_rows_box: VBoxContainer = null
var _condition_rows_header: Label = null
var _add_condition_packet_btn: Button = null
var _apply_damage_btn: Button = null
var _rows: Array = [] # Array of {hbox, cells, result_index}
var _result_damage_rows: Array = []
var _damage_packet_rows: Array = []
var _condition_packet_rows: Array = []
var _main_split: VSplitContainer = null
var _damage_scroll: ScrollContainer = null
var _condition_scroll: ScrollContainer = null
var _packet_panel: VBoxContainer = null

const DAMAGE_TYPES: Array[String] = [
	"bludgeoning", "piercing", "slashing", "fire", "cold", "lightning",
	"thunder", "acid", "poison", "necrotic", "radiant", "force",
	"psychic", "none",
]


var _scale: float = 1.0
var _root: VBoxContainer = null
var _ui_built: bool = false


func _init() -> void:
	title = "Saving Throw Results"
	transient = true
	exclusive = true
	wrap_controls = true
	close_requested.connect(_on_close)
	_ensure_ui()


func _ready() -> void:
	_ensure_ui()


func _ensure_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	_build_ui()


## Called by DMWindow after creation and on every scale change.
func apply_scale(s: float) -> void:
	_ensure_ui()
	_scale = s
	if _root == null:
		return
	var si := func(base: float) -> int: return roundi(base * s)
	_root.offset_left = si.call(12.0)
	_root.offset_right = - si.call(12.0)
	_root.offset_top = si.call(12.0)
	_root.offset_bottom = - si.call(12.0)
	_root.add_theme_constant_override("separation", si.call(8.0))
	if _table_container != null:
		_table_container.add_theme_constant_override("separation", si.call(4.0))
	if _summary_label != null:
		_summary_label.add_theme_font_size_override("font_size", si.call(15.0))
	if _main_split != null:
		_main_split.split_offset = si.call(130.0)
	if _table_panel != null:
		_table_panel.custom_minimum_size.x = si.call(600.0)
	if _packet_panel != null:
		_packet_panel.custom_minimum_size.x = si.call(360.0)
	if _add_damage_packet_btn != null:
		_add_damage_packet_btn.add_theme_font_size_override("font_size", si.call(13.0))
		_add_damage_packet_btn.custom_minimum_size.y = si.call(30.0)
	if _apply_damage_btn != null:
		_apply_damage_btn.add_theme_font_size_override("font_size", si.call(13.0))
		_apply_damage_btn.custom_minimum_size.y = si.call(30.0)
	if _damage_rows_header != null:
		_damage_rows_header.add_theme_font_size_override("font_size", si.call(14.0))
	if _condition_rows_header != null:
		_condition_rows_header.add_theme_font_size_override("font_size", si.call(14.0))
	for row: Dictionary in _damage_packet_rows:
		_style_damage_packet_row(row, s)
	for row: Dictionary in _condition_packet_rows:
		_style_condition_packet_row(row, s)
	_sync_result_damage_rows()
	_apply_text_scale(_root, si.call(14.0))
	if _summary_label != null:
		_summary_label.add_theme_font_size_override("font_size", si.call(15.0))
	min_size = Vector2i(si.call(1000.0), si.call(660.0))


func _on_close() -> void:
	closed.emit()
	hide()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func show_results(ability: String, dc: int, results: Array) -> void:
	_ensure_ui()
	_ability = ability.to_upper()
	_dc = dc
	_results = results.duplicate(true)
	title = "Saving Throw: %s DC %d" % [_ability, _dc]
	_rebuild_table()
	_clear_condition_rows()
	_add_condition_row()
	_refresh_damage_preview()
	reset_size()
	popup_centered()


func get_results() -> Array:
	return _results.duplicate(true)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_root = VBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.offset_left = 12.0
	_root.offset_right = -12.0
	_root.offset_top = 12.0
	_root.offset_bottom = -12.0
	_root.add_theme_constant_override("separation", 8)
	add_child(_root)
	var root := _root

	# Summary label
	_summary_label = Label.new()
	root.add_child(_summary_label)

	_main_split = VSplitContainer.new()
	_main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_main_split)

	var table_panel := VBoxContainer.new()
	table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_panel.custom_minimum_size.x = 600.0
	_main_split.add_child(table_panel)
	_table_panel = table_panel

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	table_panel.add_child(header)
	for col_name: String in ["Token", "Roll", "Mod", "Total", "Result", "Damage"]:
		var lbl := Label.new()
		lbl.text = col_name
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if col_name == "Token":
			lbl.custom_minimum_size.x = 160.0
		elif col_name == "Damage":
			lbl.custom_minimum_size.x = 100.0
		else:
			lbl.custom_minimum_size.x = 60.0
		header.add_child(lbl)
	# Override column header
	var override_lbl := Label.new()
	override_lbl.text = "Override"
	override_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	override_lbl.custom_minimum_size.x = 72.0
	header.add_child(override_lbl)

	# Scrollable table body
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	table_panel.add_child(scroll)
	_table_container = VBoxContainer.new()
	_table_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_container.add_theme_constant_override("separation", 4)
	scroll.add_child(_table_container)

	# Damage packet editor header
	var packet_panel := VBoxContainer.new()
	packet_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	packet_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	packet_panel.custom_minimum_size.x = 360.0
	_main_split.add_child(packet_panel)
	_packet_panel = packet_panel

	var packet_header := HBoxContainer.new()
	packet_header.add_theme_constant_override("separation", 8)
	packet_panel.add_child(packet_header)

	_damage_rows_header = Label.new()
	_damage_rows_header.text = "Damage Packets"
	_damage_rows_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_damage_rows_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	packet_header.add_child(_damage_rows_header)

	_add_damage_packet_btn = Button.new()
	_add_damage_packet_btn.text = "+ Packet"
	_add_damage_packet_btn.pressed.connect(_add_damage_row)
	packet_header.add_child(_add_damage_packet_btn)

	_damage_scroll = ScrollContainer.new()
	_damage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_damage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_damage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	packet_panel.add_child(_damage_scroll)

	_damage_rows_box = VBoxContainer.new()
	_damage_rows_box.add_theme_constant_override("separation", 6)
	_damage_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_damage_scroll.add_child(_damage_rows_box)

	var condition_header := HBoxContainer.new()
	condition_header.add_theme_constant_override("separation", 8)
	packet_panel.add_child(condition_header)

	_condition_rows_header = Label.new()
	_condition_rows_header.text = "Conditions"
	_condition_rows_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_condition_rows_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	condition_header.add_child(_condition_rows_header)

	_add_condition_packet_btn = Button.new()
	_add_condition_packet_btn.text = "+ Condition"
	_add_condition_packet_btn.pressed.connect(_add_condition_row)
	condition_header.add_child(_add_condition_packet_btn)

	_condition_scroll = ScrollContainer.new()
	_condition_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_condition_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_condition_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	packet_panel.add_child(_condition_scroll)

	_condition_rows_box = VBoxContainer.new()
	_condition_rows_box.add_theme_constant_override("separation", 6)
	_condition_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_condition_scroll.add_child(_condition_rows_box)

	# Action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	packet_panel.add_child(btn_row)

	var half_btn := Button.new()
	half_btn.text = "Half to Passed, Full to Failed"
	half_btn.pressed.connect(_on_apply_half_full)
	btn_row.add_child(half_btn)

	var full_fail_btn := Button.new()
	full_fail_btn.text = "Full to Failed Only"
	full_fail_btn.pressed.connect(_on_apply_full_fail)
	btn_row.add_child(full_fail_btn)

	_apply_damage_btn = Button.new()
	_apply_damage_btn.text = "Apply Damage"
	_apply_damage_btn.pressed.connect(_on_apply_damage_pressed)
	btn_row.add_child(_apply_damage_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close)
	btn_row.add_child(close_btn)

	_add_damage_row()
	_add_condition_row()
	_apply_text_scale(_root, 14)
	if _summary_label != null:
		_summary_label.add_theme_font_size_override("font_size", 15)


# ---------------------------------------------------------------------------
# Table rebuild
# ---------------------------------------------------------------------------

func _rebuild_table() -> void:
	# Clear existing rows.
	for child: Node in _table_container.get_children():
		child.queue_free()
	_rows.clear()
	_result_damage_rows.clear()

	var pass_count: int = 0
	var fail_count: int = 0

	for i: int in range(_results.size()):
		var r: Dictionary = _results[i]
		var passed: bool = bool(r.get("passed", false))
		if passed:
			pass_count += 1
		else:
			fail_count += 1

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		_table_container.add_child(row)

		# Token name
		var name_lbl := Label.new()
		name_lbl.text = str(r.get("name", ""))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.custom_minimum_size.x = 160.0
		row.add_child(name_lbl)

		# Roll (d20 value)
		var roll_lbl := Label.new()
		var roll_val: int = int(r.get("roll", 0))
		var nat20: bool = bool(r.get("nat20", false))
		var nat1: bool = bool(r.get("nat1", false))
		roll_lbl.text = str(roll_val)
		if nat20:
			roll_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		elif nat1:
			roll_lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		roll_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		roll_lbl.custom_minimum_size.x = 60.0
		row.add_child(roll_lbl)

		# Modifier
		var mod_lbl := Label.new()
		var mod_val: int = int(r.get("modifier", 0))
		mod_lbl.text = "%+d" % mod_val
		mod_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mod_lbl.custom_minimum_size.x = 60.0
		row.add_child(mod_lbl)

		# Total
		var total_lbl := Label.new()
		total_lbl.text = str(int(r.get("total", 0)))
		total_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		total_lbl.custom_minimum_size.x = 60.0
		row.add_child(total_lbl)

		# Result
		var result_lbl := Label.new()
		if passed:
			result_lbl.text = "\u2705 PASS"
			result_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		else:
			result_lbl.text = "\u274c FAIL"
			result_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		result_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		result_lbl.custom_minimum_size.x = 60.0
		row.add_child(result_lbl)

		# Damage adjustors — one row per configured packet.
		var damage_box := VBoxContainer.new()
		damage_box.add_theme_constant_override("separation", 2)
		damage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(damage_box)
		_result_damage_rows.append({"box": damage_box, "spins": []})

		# Override toggle button
		var toggle_btn := Button.new()
		toggle_btn.text = "Toggle"
		toggle_btn.custom_minimum_size.x = 72.0
		toggle_btn.pressed.connect(_on_toggle_result.bind(i))
		row.add_child(toggle_btn)

		_rows.append({"hbox": row, "result_lbl": result_lbl, "index": i})

	_summary_label.text = "%d passed, %d failed" % [pass_count, fail_count]
	_apply_text_scale(_root, max(12, roundi(14.0 * _scale)))
	if _summary_label != null:
		_summary_label.add_theme_font_size_override("font_size", roundi(15.0 * _scale))
	_sync_result_damage_rows()
	_refresh_damage_preview()


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_toggle_result(idx: int) -> void:
	if idx < 0 or idx >= _results.size():
		return
	var r: Dictionary = _results[idx]
	r["passed"] = not bool(r.get("passed", false))
	_results[idx] = r
	# Update the row label.
	if idx < _rows.size():
		var result_lbl: Label = _rows[idx].get("result_lbl", null) as Label
		if result_lbl != null:
			var passed: bool = bool(r.get("passed", false))
			if passed:
				result_lbl.text = "\u2705 PASS"
				result_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
			else:
				result_lbl.text = "\u274c FAIL"
				result_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	# Recount.
	var p: int = 0
	var f: int = 0
	for res: Dictionary in _results:
		if bool(res.get("passed", false)):
			p += 1
		else:
			f += 1
	_summary_label.text = "%d passed, %d failed" % [p, f]
	_refresh_damage_preview()


func _on_apply_half_full() -> void:
	if _damage_packet_rows.is_empty():
		return
	_set_result_damage_defaults(true)
	_update_summary_and_preview()


func _on_apply_full_fail() -> void:
	if _damage_packet_rows.is_empty():
		return
	_set_result_damage_defaults(false)
	_update_summary_and_preview()


func _on_apply_damage_pressed() -> void:
	var results_with_damage: Array = _collect_result_packet_rows()
	var condition_rows: Array = _collect_condition_rows()
	if results_with_damage.is_empty() and condition_rows.is_empty():
		return
	apply_damage_to_results.emit(results_with_damage, _collect_damage_rows(), condition_rows)


func _add_damage_row() -> void:
	if _damage_rows_box == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_damage_rows_box.add_child(row)

	var amount_spin := SpinBox.new()
	amount_spin.min_value = 1
	amount_spin.max_value = 9999
	amount_spin.value = 1
	amount_spin.custom_minimum_size.x = 90.0
	amount_spin.value_changed.connect(func(_value: float) -> void: _refresh_damage_preview())
	row.add_child(amount_spin)

	var type_option := OptionButton.new()
	type_option.custom_minimum_size.x = 140.0
	for dt: String in DAMAGE_TYPES:
		type_option.add_item(dt.capitalize())
	type_option.item_selected.connect(func(_idx: int) -> void: _refresh_damage_preview())
	row.add_child(type_option)

	var remove_btn := Button.new()
	remove_btn.text = "-"
	remove_btn.custom_minimum_size = Vector2(32.0, 30.0)
	row.add_child(remove_btn)

	var row_dict: Dictionary = {
		"node": row,
		"amount_spin": amount_spin,
		"type_option": type_option,
		"remove_btn": remove_btn,
	}
	_damage_packet_rows.append(row_dict)
	_style_damage_packet_row(row_dict, _scale)
	remove_btn.pressed.connect(func() -> void: _remove_damage_row(row_dict))
	_refresh_damage_preview()


func _add_condition_row() -> void:
	if _condition_rows_box == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_condition_rows_box.add_child(row)

	var condition_option := OptionButton.new()
	condition_option.custom_minimum_size.x = 180.0
	condition_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	condition_option.add_item("(none)")
	condition_option.set_item_metadata(0, "")
	for key: String in ConditionRules.get_all_keys():
		condition_option.add_item(ConditionRules.get_label(key))
		condition_option.set_item_metadata(condition_option.item_count - 1, key)
	row.add_child(condition_option)

	var remove_btn := Button.new()
	remove_btn.text = "-"
	remove_btn.custom_minimum_size = Vector2(32.0, 30.0)
	row.add_child(remove_btn)

	var row_dict: Dictionary = {
		"node": row,
		"condition_option": condition_option,
		"remove_btn": remove_btn,
	}
	_condition_packet_rows.append(row_dict)
	_style_condition_packet_row(row_dict, _scale)
	remove_btn.pressed.connect(func() -> void: _remove_condition_row(row_dict))
	_refresh_damage_preview()


func _clear_condition_rows() -> void:
	if _condition_rows_box == null:
		return
	for child: Node in _condition_rows_box.get_children():
		child.queue_free()
	_condition_packet_rows.clear()


func _remove_condition_row(row_dict: Dictionary) -> void:
	if _condition_packet_rows.size() <= 1:
		var condition_option: OptionButton = row_dict.get("condition_option", null) as OptionButton
		if condition_option != null:
			condition_option.selected = 0
		_refresh_damage_preview()
		return
	var row: Node = row_dict.get("node", null) as Node
	if row != null:
		row.queue_free()
	_condition_packet_rows.erase(row_dict)
	_refresh_damage_preview()


func _style_condition_packet_row(row_dict: Dictionary, scale: float) -> void:
	var si := func(base: float) -> int: return roundi(base * scale)
	var row_node: HBoxContainer = row_dict.get("node", null) as HBoxContainer
	var condition_option: OptionButton = row_dict.get("condition_option", null) as OptionButton
	var remove_btn: Button = row_dict.get("remove_btn", null) as Button
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if row_node != null:
		row_node.add_theme_constant_override("separation", si.call(8.0))
		if reg != null and reg.ui_theme != null:
			reg.ui_theme.theme_control_tree(row_node, scale)
		if reg != null and reg.ui_scale != null:
			reg.ui_scale.scale_control_fonts(row_node, 15.0)
	if condition_option != null:
		condition_option.custom_minimum_size.x = si.call(180.0)
		condition_option.add_theme_font_size_override("font_size", si.call(15.0))
	if remove_btn != null:
		if reg != null and reg.ui_scale != null:
			reg.ui_scale.scale_button(remove_btn, 32.0, 30.0, 15.0)
		else:
			remove_btn.custom_minimum_size.x = si.call(32.0)
			remove_btn.custom_minimum_size.y = si.call(30.0)


func _remove_damage_row(row_dict: Dictionary) -> void:
	if _damage_packet_rows.size() <= 1:
		var amount_spin: SpinBox = row_dict.get("amount_spin", null) as SpinBox
		var type_option: OptionButton = row_dict.get("type_option", null) as OptionButton
		if amount_spin != null:
			amount_spin.value = 1
		if type_option != null:
			type_option.selected = 0
		_refresh_damage_preview()
		return
	var row: Node = row_dict.get("node", null) as Node
	if row != null:
		row.queue_free()
	_damage_packet_rows.erase(row_dict)
	_refresh_damage_preview()


func _style_damage_packet_row(row_dict: Dictionary, scale: float) -> void:
	var si := func(base: float) -> int: return roundi(base * scale)
	var row_node: HBoxContainer = row_dict.get("node", null) as HBoxContainer
	var amount_spin: SpinBox = row_dict.get("amount_spin", null) as SpinBox
	var type_option: OptionButton = row_dict.get("type_option", null) as OptionButton
	var remove_btn: Button = row_dict.get("remove_btn", null) as Button
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if row_node != null:
		row_node.add_theme_constant_override("separation", si.call(8.0))
		if reg != null and reg.ui_theme != null:
			reg.ui_theme.theme_control_tree(row_node, scale)
		if reg != null and reg.ui_scale != null:
			reg.ui_scale.scale_control_fonts(row_node, 15.0)
	if amount_spin != null:
		amount_spin.custom_minimum_size.x = si.call(90.0)
		amount_spin.add_theme_font_size_override("font_size", si.call(15.0))
	if type_option != null:
		type_option.custom_minimum_size.x = si.call(140.0)
		type_option.add_theme_font_size_override("font_size", si.call(15.0))
	if remove_btn != null:
		if reg != null and reg.ui_scale != null:
			reg.ui_scale.scale_button(remove_btn, 32.0, 30.0, 15.0)
		else:
			remove_btn.custom_minimum_size.x = si.call(32.0)
			remove_btn.custom_minimum_size.y = si.call(30.0)


func _style_damage_adjustor_row(row_node: HBoxContainer) -> void:
	if row_node == null:
		return
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(row_node, _scale)
	if reg != null and reg.ui_scale != null:
		reg.ui_scale.scale_control_fonts(row_node, 13.0)


func _sync_result_damage_rows() -> void:
	for i: int in range(_result_damage_rows.size()):
		var row_dict: Dictionary = _result_damage_rows[i]
		var box: VBoxContainer = row_dict.get("box", null) as VBoxContainer
		var spins: Array = []
		if box == null:
			continue
		for child: Node in box.get_children():
			child.queue_free()
		if _damage_packet_rows.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "Add damage packets above"
			box.add_child(empty_lbl)
			row_dict["spins"] = spins
			continue
		for packet_row: Dictionary in _damage_packet_rows:
			var packet_type: String = str((packet_row.get("type_option", null) as OptionButton).get_item_text((packet_row.get("type_option", null) as OptionButton).selected))
			var packet_amount: int = int((packet_row.get("amount_spin", null) as SpinBox).value)
			var packet_box := HBoxContainer.new()
			packet_box.add_theme_constant_override("separation", 6)
			packet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_child(packet_box)

			var type_lbl := Label.new()
			type_lbl.text = packet_type
			type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			type_lbl.custom_minimum_size.x = 100.0
			packet_box.add_child(type_lbl)

			var amount_spin := SpinBox.new()
			amount_spin.min_value = 0
			amount_spin.max_value = 9999
			amount_spin.value = packet_amount if int(_results[i].get("passed", false)) == 0 else floor(packet_amount / 2.0)
			amount_spin.custom_minimum_size.x = 90.0
			amount_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			amount_spin.value_changed.connect(func(_value: float) -> void: _update_summary_and_preview())
			packet_box.add_child(amount_spin)
			spins.append(amount_spin)
			_style_damage_adjustor_row(packet_box)
		row_dict["spins"] = spins


func _get_result_damage_row(idx: int) -> Dictionary:
	if idx < 0 or idx >= _result_damage_rows.size():
		return {}
	return _result_damage_rows[idx]


func _collect_damage_rows() -> Array:
	var rows: Array = []
	for row: Dictionary in _damage_packet_rows:
		var amount_spin: SpinBox = row.get("amount_spin", null) as SpinBox
		var type_option: OptionButton = row.get("type_option", null) as OptionButton
		if amount_spin == null or type_option == null:
			continue
		var amount: int = int(amount_spin.value)
		if amount <= 0:
			continue
		var idx: int = type_option.selected
		var damage_type: String = DAMAGE_TYPES[idx] if idx >= 0 and idx < DAMAGE_TYPES.size() else "none"
		rows.append({"amount": amount, "damage_type": damage_type})
	return rows


func _collect_condition_rows() -> Array:
	var rows: Array = []
	for row: Dictionary in _condition_packet_rows:
		var condition_option: OptionButton = row.get("condition_option", null) as OptionButton
		if condition_option == null:
			continue
		var idx: int = condition_option.selected
		if idx < 0:
			continue
		var condition_name: String = str(condition_option.get_item_metadata(idx))
		if condition_name.is_empty():
			continue
		rows.append({"condition_name": condition_name})
	return rows


func _get_packet_total() -> int:
	var total: int = 0
	for row: Dictionary in _collect_damage_rows():
		total += int(row.get("amount", 0))
	return total


func _build_damage_breakdown(total: int) -> String:
	if total <= 0:
		return ""
	var packets: Array = _collect_damage_rows()
	if packets.is_empty():
		return ""
	var packet_total: int = 0
	for packet: Dictionary in packets:
		packet_total += int(packet.get("amount", 0))
	if packet_total <= 0:
		return ""
	var parts: Array[String] = []
	var remaining: int = total
	for i: int in range(packets.size()):
		var packet: Dictionary = packets[i]
		var amount: int = int(packet.get("amount", 0))
		var damage_type: String = str(packet.get("damage_type", "none"))
		var applied: int = amount if i == packets.size() - 1 else int(round(float(amount) * float(total) / float(packet_total)))
		applied = min(applied, remaining)
		remaining -= applied
		parts.append("%d %s" % [applied, damage_type])
	return ", ".join(parts)


func _refresh_damage_preview() -> void:
	_sync_result_damage_rows()
	_update_summary_and_preview()


func _update_summary_and_preview() -> void:
	var pass_count: int = 0
	var fail_count: int = 0
	for r: Dictionary in _results:
		if bool(r.get("passed", false)):
			pass_count += 1
		else:
			fail_count += 1
	if _summary_label != null:
		var damage_count: int = _damage_packet_rows.size()
		var condition_count: int = _condition_packet_rows.size()
		_summary_label.text = "%d passed, %d failed | %d damage packet%s | %d condition packet%s" % [
			pass_count, fail_count,
			damage_count, "" if damage_count == 1 else "s",
			condition_count, "" if condition_count == 1 else "s",
		]


func _set_result_damage_defaults(half_for_pass: bool) -> void:
	for i: int in range(_result_damage_rows.size()):
		var row_dict: Dictionary = _result_damage_rows[i]
		var spins: Array = row_dict.get("spins", []) as Array
		var passed: bool = bool(_results[i].get("passed", false))
		for j: int in range(spins.size()):
			var spin: SpinBox = spins[j] as SpinBox
			var packet_row: Dictionary = _damage_packet_rows[j]
			var amount_spin: SpinBox = packet_row.get("amount_spin", null) as SpinBox
			var packet_amount: int = int(amount_spin.value) if amount_spin != null else 0
			if passed:
				spin.value = floor(packet_amount / 2.0) if half_for_pass else 0
			else:
				spin.value = packet_amount


func _collect_result_packet_rows() -> Array:
	var results_with_damage: Array = []
	for i: int in range(_results.size()):
		var r: Dictionary = _results[i].duplicate(true)
		var row_dict: Dictionary = _get_result_damage_row(i)
		var spins: Array = row_dict.get("spins", []) as Array
		var packet_rows: Array = []
		var damage_total: int = 0
		for j: int in range(spins.size()):
			var spin: SpinBox = spins[j] as SpinBox
			var packet_cfg: Dictionary = _damage_packet_rows[j]
			var damage_type: String = str((packet_cfg.get("type_option", null) as OptionButton).get_item_text((packet_cfg.get("type_option", null) as OptionButton).selected))
			var amount: int = int(spin.value) if spin != null else 0
			packet_rows.append({"amount": amount, "damage_type": damage_type})
			damage_total += amount
		r["damage_packets"] = packet_rows
		r["damage_amount"] = damage_total
		results_with_damage.append(r)
	return results_with_damage


func _apply_text_scale(node: Node, font_size: int) -> void:
	if node is Label:
		(node as Label).add_theme_font_size_override("font_size", font_size)
	elif node is Button:
		(node as Button).add_theme_font_size_override("font_size", font_size)
	elif node is OptionButton:
		(node as OptionButton).add_theme_font_size_override("font_size", font_size)
	elif node is CheckBox:
		(node as CheckBox).add_theme_font_size_override("font_size", font_size)
	elif node is SpinBox:
		var le: LineEdit = (node as SpinBox).get_line_edit()
		if le != null:
			le.add_theme_font_size_override("font_size", font_size)
	for child: Node in node.get_children():
		_apply_text_scale(child, font_size)
