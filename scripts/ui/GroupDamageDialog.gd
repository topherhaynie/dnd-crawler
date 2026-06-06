extends Window
class_name GroupDamageDialog

## Modal dialog for applying one or more damage packets to a selected group.
##
## The dialog uses the same packet-editor look as the save panel, but omits
## the save-only result/status columns.

signal apply_requested(token_ids: Array, damage_rows: Array, condition_rows: Array)
signal closed

const DAMAGE_TYPES: PackedStringArray = [
	"", "acid", "bludgeoning", "cold", "fire", "force",
	"lightning", "necrotic", "piercing", "poison", "psychic",
	"radiant", "slashing", "thunder",
]

var _token_ids: Array[String] = []
var _scale: float = 1.0
var _root: VBoxContainer = null
var _summary_label: Label = null
var _header_row: HBoxContainer = null
var _rows_scroll: ScrollContainer = null
var _rows_box: VBoxContainer = null
var _condition_scroll: ScrollContainer = null
var _condition_rows_box: VBoxContainer = null
var _footer_row: HBoxContainer = null
var _add_row_btn: Button = null
var _add_condition_btn: Button = null
var _apply_btn: Button = null
var _cancel_btn: Button = null
var _row_nodes: Array = []
var _condition_row_nodes: Array = []
var _ui_built: bool = false


func _ready() -> void:
	title = "Group Damage"
	transient = true
	exclusive = true
	wrap_controls = true
	close_requested.connect(_on_close)
	_ensure_ui()


func _ensure_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	_build_ui()


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
	if _header_row != null:
		_header_row.add_theme_constant_override("separation", si.call(8.0))
	if _rows_scroll != null:
		_rows_scroll.custom_minimum_size.y = si.call(230.0)
	if _rows_scroll != null:
		_rows_scroll.custom_minimum_size.x = si.call(360.0)
	if _rows_box != null:
		_rows_box.add_theme_constant_override("separation", si.call(6.0))
	if _condition_rows_box != null:
		_condition_rows_box.add_theme_constant_override("separation", si.call(6.0))
	if _condition_scroll != null:
		_condition_scroll.custom_minimum_size.x = si.call(360.0)
	if _summary_label != null:
		_summary_label.add_theme_font_size_override("font_size", si.call(15.0))
	if _add_row_btn != null:
		_add_row_btn.add_theme_font_size_override("font_size", si.call(13.0))
		_add_row_btn.custom_minimum_size.y = si.call(30.0)
	if _add_condition_btn != null:
		_add_condition_btn.add_theme_font_size_override("font_size", si.call(13.0))
		_add_condition_btn.custom_minimum_size.y = si.call(30.0)
	if _apply_btn != null:
		_apply_btn.add_theme_font_size_override("font_size", si.call(13.0))
		_apply_btn.custom_minimum_size.y = si.call(30.0)
	if _cancel_btn != null:
		_cancel_btn.add_theme_font_size_override("font_size", si.call(13.0))
		_cancel_btn.custom_minimum_size.y = si.call(30.0)
	for row: Dictionary in _row_nodes:
		_style_row(row, s)
	for row: Dictionary in _condition_row_nodes:
		_style_condition_row(row, s)
	min_size = Vector2i(si.call(760.0), si.call(520.0))
	reset_size()


func open(token_ids: Array[String]) -> void:
	_ensure_ui()
	_token_ids = token_ids.duplicate()
	if _summary_label != null:
		_summary_label.text = "%d target%s selected" % [_token_ids.size(), "" if _token_ids.size() == 1 else "s"]
	_clear_rows()
	_clear_condition_rows()
	_add_row()
	_add_condition_row()
	_update_summary_label()
	reset_size()
	popup_centered()


func _build_ui() -> void:
	_root = VBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.offset_left = 12.0
	_root.offset_right = -12.0
	_root.offset_top = 12.0
	_root.offset_bottom = -12.0
	_root.add_theme_constant_override("separation", 8)
	add_child(_root)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.text = "0 targets selected"
	_root.add_child(_summary_label)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Add one or more damage rows, then apply them to the selected group."
	_root.add_child(hint)

	_header_row = HBoxContainer.new()
	_header_row.add_theme_constant_override("separation", 8)
	_root.add_child(_header_row)

	var header_lbl := Label.new()
	header_lbl.text = "Damage Packets"
	header_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_row.add_child(header_lbl)

	_add_row_btn = Button.new()
	_add_row_btn.text = "+ Packet"
	_add_row_btn.pressed.connect(_add_row)
	_header_row.add_child(_add_row_btn)

	_rows_scroll = ScrollContainer.new()
	_rows_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows_scroll.custom_minimum_size.x = 360.0
	_rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_rows_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_scroll.add_child(_rows_box)

	var condition_header := HBoxContainer.new()
	condition_header.add_theme_constant_override("separation", 8)
	_root.add_child(condition_header)

	var condition_lbl := Label.new()
	condition_lbl.text = "Conditions"
	condition_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	condition_header.add_child(condition_lbl)

	_add_condition_btn = Button.new()
	_add_condition_btn.text = "+ Condition"
	_add_condition_btn.pressed.connect(_add_condition_row)
	condition_header.add_child(_add_condition_btn)

	_condition_scroll = ScrollContainer.new()
	_condition_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_condition_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_condition_scroll.custom_minimum_size.x = 360.0
	_condition_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_condition_scroll)

	_condition_rows_box = VBoxContainer.new()
	_condition_rows_box.add_theme_constant_override("separation", 6)
	_condition_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_condition_scroll.add_child(_condition_rows_box)

	_footer_row = HBoxContainer.new()
	_footer_row.add_theme_constant_override("separation", 8)
	_footer_row.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(_footer_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_close)
	_footer_row.add_child(_cancel_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_row.add_child(spacer)

	_apply_btn = Button.new()
	_apply_btn.text = "Apply"
	_apply_btn.pressed.connect(_on_apply)
	_footer_row.add_child(_apply_btn)

	_add_row()
	_add_condition_row()
	_update_summary_label()


func _clear_rows() -> void:
	for child: Node in _rows_box.get_children():
		child.queue_free()
	_row_nodes.clear()


func _clear_condition_rows() -> void:
	if _condition_rows_box == null:
		return
	for child: Node in _condition_rows_box.get_children():
		child.queue_free()
	_condition_row_nodes.clear()


func _add_row() -> void:
	if _rows_box == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_child(row)

	var type_option := OptionButton.new()
	type_option.custom_minimum_size.x = 160.0
	type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for dt: String in DAMAGE_TYPES:
		type_option.add_item(dt.capitalize() if not dt.is_empty() else "(none)")
	row.add_child(type_option)

	var amount_spin := SpinBox.new()
	amount_spin.min_value = 1
	amount_spin.max_value = 9999
	amount_spin.value = 1
	amount_spin.custom_minimum_size.x = 90.0
	amount_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(amount_spin)

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
	_row_nodes.append(row_dict)
	_style_row(row_dict, _scale if _scale != 0.0 else 1.0)
	remove_btn.pressed.connect(func() -> void: _remove_row(row_dict))
	if _scale != 0.0:
		apply_scale(_scale)
	reset_size()


func _remove_row(row_dict: Dictionary) -> void:
	if _row_nodes.size() <= 1:
		var amount_spin: SpinBox = row_dict.get("amount_spin", null) as SpinBox
		var type_option: OptionButton = row_dict.get("type_option", null) as OptionButton
		if amount_spin != null:
			amount_spin.value = 1
		if type_option != null:
			type_option.selected = 0
		_update_summary_label()
		return
	var row: Node = row_dict.get("node", null) as Node
	if row != null:
		row.queue_free()
	_row_nodes.erase(row_dict)
	_update_summary_label()
	reset_size()


func _style_row(row_dict: Dictionary, scale: float) -> void:
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
			reg.ui_scale.scale_control_fonts(row_node, 14.0)
	if amount_spin != null:
		amount_spin.custom_minimum_size.x = si.call(90.0)
		amount_spin.add_theme_font_size_override("font_size", si.call(14.0))
	if type_option != null:
		type_option.custom_minimum_size.x = si.call(160.0)
		type_option.add_theme_font_size_override("font_size", si.call(14.0))
	if remove_btn != null:
		if reg != null and reg.ui_scale != null:
			reg.ui_scale.scale_button(remove_btn, 32.0, 30.0, 14.0)
		else:
			remove_btn.custom_minimum_size.x = si.call(32.0)
			remove_btn.custom_minimum_size.y = si.call(30.0)


func _add_condition_row() -> void:
	if _condition_rows_box == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_condition_row_nodes.append(row_dict)
	_style_condition_row(row_dict, _scale)
	remove_btn.pressed.connect(func() -> void: _remove_condition_row(row_dict))
	_update_summary_label()
	reset_size()


func _remove_condition_row(row_dict: Dictionary) -> void:
	if _condition_row_nodes.size() <= 1:
		var condition_option: OptionButton = row_dict.get("condition_option", null) as OptionButton
		if condition_option != null:
			condition_option.selected = 0
		_update_summary_label()
		return
	var row: Node = row_dict.get("node", null) as Node
	if row != null:
		row.queue_free()
	_condition_row_nodes.erase(row_dict)
	_update_summary_label()
	reset_size()


func _style_condition_row(row_dict: Dictionary, scale: float) -> void:
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
			reg.ui_scale.scale_control_fonts(row_node, 14.0)
	if condition_option != null:
		condition_option.custom_minimum_size.x = si.call(180.0)
		condition_option.add_theme_font_size_override("font_size", si.call(14.0))
	if remove_btn != null:
		if reg != null and reg.ui_scale != null:
			reg.ui_scale.scale_button(remove_btn, 32.0, 30.0, 14.0)
		else:
			remove_btn.custom_minimum_size.x = si.call(32.0)
			remove_btn.custom_minimum_size.y = si.call(30.0)


func _collect_damage_rows() -> Array:
	var rows: Array = []
	for row: Dictionary in _row_nodes:
		var amount_spin: SpinBox = row.get("amount_spin", null) as SpinBox
		var type_option: OptionButton = row.get("type_option", null) as OptionButton
		if amount_spin == null or type_option == null:
			continue
		var amount: int = int(amount_spin.value)
		if amount <= 0:
			continue
		var idx: int = type_option.selected
		var damage_type: String = DAMAGE_TYPES[idx] if idx >= 0 and idx < DAMAGE_TYPES.size() else ""
		rows.append({"amount": amount, "damage_type": damage_type})
	return rows


func _collect_condition_rows() -> Array:
	var rows: Array = []
	for row: Dictionary in _condition_row_nodes:
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


func _update_summary_label() -> void:
	if _summary_label == null:
		return
	var damage_count: int = _row_nodes.size()
	var condition_count: int = _condition_row_nodes.size()
	_summary_label.text = "%d damage packet%s | %d condition packet%s" % [
		damage_count, "" if damage_count == 1 else "s",
		condition_count, "" if condition_count == 1 else "s",
	]


func _on_apply() -> void:
	var rows: Array = _collect_damage_rows()
	var condition_rows: Array = _collect_condition_rows()
	if rows.is_empty() and condition_rows.is_empty():
		return
	apply_requested.emit(_token_ids.duplicate(), rows, condition_rows)
	hide()


func _on_close() -> void:
	closed.emit()
	hide()
