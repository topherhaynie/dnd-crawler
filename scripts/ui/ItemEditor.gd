extends Window
class_name ItemEditor

# ---------------------------------------------------------------------------
# ItemEditor — form for creating / editing equipment/items.
#
# Covers name, category, description, cost, weight, damage, armor class,
# range, and properties.
# ---------------------------------------------------------------------------

signal item_saved(data: ItemEntry)

var _registry: ServiceRegistry = null
var _data: ItemEntry = null

# ── Fields ────────────────────────────────────────────────────────────────
var _name_edit: LineEdit = null
var _category_option: OptionButton = null
var _desc_edit: TextEdit = null
var _cost_qty_spin: SpinBox = null
var _cost_unit_option: OptionButton = null
var _weight_spin: SpinBox = null
var _damage_dice_edit: LineEdit = null
var _damage_type_edit: LineEdit = null
var _ac_base_spin: SpinBox = null
var _ac_dex_check: CheckBox = null
var _ac_max_bonus_spin: SpinBox = null
var _range_normal_spin: SpinBox = null
var _range_long_spin: SpinBox = null
var _properties_edit: LineEdit = null

# ── Layout ────────────────────────────────────────────────────────────────
var _save_btn: Button = null
var _cancel_btn: Button = null

const COST_UNITS: Array = ["cp", "sp", "ep", "gp", "pp"]
const DAMAGE_TYPES: Array = [
	"", "Acid", "Bludgeoning", "Cold", "Fire", "Force", "Lightning",
	"Necrotic", "Piercing", "Poison", "Psychic", "Radiant", "Slashing", "Thunder",
]


func _ready() -> void:
	_registry = get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	title = "Item Editor"
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var s := func(base: float) -> int:
		return mgr.scaled(base) if mgr != null else roundi(base)
	size = Vector2i(s.call(520.0), s.call(560.0))
	min_size = Vector2i(s.call(400.0), s.call(400.0))
	wrap_controls = false
	exclusive = false
	transient = true
	_build_ui()
	close_requested.connect(_on_cancel)


func edit(data: ItemEntry) -> void:
	_data = data
	if _data == null:
		_data = ItemEntry.new()
		_data.id = ItemEntry.generate_id()
		_data.source = "custom"
		_data.ruleset = "custom"
	_populate_fields()
	popup_centered()
	reapply_theme()


# ---------------------------------------------------------------------------
# UI build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var outer := VBoxContainer.new()
	margin.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	# Name
	form.add_child(_make_section_label("Name"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Item name"
	form.add_child(_name_edit)

	# Category
	form.add_child(_make_section_label("Category"))
	_category_option = OptionButton.new()
	_category_option.add_item("Adventuring Gear")
	_category_option.add_item("Weapon")
	_category_option.add_item("Armor")
	_category_option.add_item("Tool")
	_category_option.add_item("Ammunition")
	_category_option.add_item("Shield")
	_category_option.add_item("Other")
	# Append SRD categories not yet in the list
	if _registry != null and _registry.item != null:
		var srd_cats: PackedStringArray = _registry.item.get_categories()
		for cat: String in srd_cats:
			var found: bool = false
			for i: int in range(_category_option.item_count):
				if _category_option.get_item_text(i) == cat:
					found = true
					break
			if not found:
				_category_option.add_item(cat)
	form.add_child(_category_option)

	# Description
	form.add_child(_make_section_label("Description"))
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size.y = 80
	_desc_edit.placeholder_text = "Item description..."
	form.add_child(_desc_edit)

	# Cost
	form.add_child(_make_section_label("Cost"))
	var cost_row := HBoxContainer.new()
	_cost_qty_spin = SpinBox.new()
	_cost_qty_spin.min_value = 0
	_cost_qty_spin.max_value = 999999
	_cost_qty_spin.value = 0
	_cost_qty_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_row.add_child(_cost_qty_spin)
	_cost_unit_option = OptionButton.new()
	for unit: String in COST_UNITS:
		_cost_unit_option.add_item(unit)
	_cost_unit_option.select(3) # Default to "gp"
	cost_row.add_child(_cost_unit_option)
	form.add_child(cost_row)

	# Weight
	form.add_child(_make_section_label("Weight (lb.)"))
	_weight_spin = SpinBox.new()
	_weight_spin.min_value = 0.0
	_weight_spin.max_value = 9999.0
	_weight_spin.step = 0.1
	_weight_spin.value = 0.0
	form.add_child(_weight_spin)

	# Damage
	form.add_child(_make_section_label("Damage"))
	var dmg_row := HBoxContainer.new()
	_damage_dice_edit = LineEdit.new()
	_damage_dice_edit.placeholder_text = "e.g. 1d8"
	_damage_dice_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dmg_row.add_child(_damage_dice_edit)
	_damage_type_edit = LineEdit.new()
	_damage_type_edit.placeholder_text = "e.g. Slashing"
	_damage_type_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dmg_row.add_child(_damage_type_edit)
	form.add_child(dmg_row)

	# Armor Class
	form.add_child(_make_section_label("Armor Class"))
	var ac_row := HBoxContainer.new()
	var ac_base_lbl := Label.new()
	ac_base_lbl.text = "Base AC:"
	ac_row.add_child(ac_base_lbl)
	_ac_base_spin = SpinBox.new()
	_ac_base_spin.min_value = 0
	_ac_base_spin.max_value = 30
	_ac_base_spin.value = 0
	ac_row.add_child(_ac_base_spin)
	_ac_dex_check = CheckBox.new()
	_ac_dex_check.text = "+ Dex"
	ac_row.add_child(_ac_dex_check)
	var ac_max_lbl := Label.new()
	ac_max_lbl.text = "Max bonus:"
	ac_row.add_child(ac_max_lbl)
	_ac_max_bonus_spin = SpinBox.new()
	_ac_max_bonus_spin.min_value = 0
	_ac_max_bonus_spin.max_value = 10
	_ac_max_bonus_spin.value = 0
	ac_row.add_child(_ac_max_bonus_spin)
	form.add_child(ac_row)

	# Range
	form.add_child(_make_section_label("Range (ft.)"))
	var range_row := HBoxContainer.new()
	var range_normal_lbl := Label.new()
	range_normal_lbl.text = "Normal:"
	range_row.add_child(range_normal_lbl)
	_range_normal_spin = SpinBox.new()
	_range_normal_spin.min_value = 0
	_range_normal_spin.max_value = 9999
	_range_normal_spin.value = 0
	range_row.add_child(_range_normal_spin)
	var range_long_lbl := Label.new()
	range_long_lbl.text = "Long:"
	range_row.add_child(range_long_lbl)
	_range_long_spin = SpinBox.new()
	_range_long_spin.min_value = 0
	_range_long_spin.max_value = 9999
	_range_long_spin.value = 0
	range_row.add_child(_range_long_spin)
	form.add_child(range_row)

	# Properties (comma-separated)
	form.add_child(_make_section_label("Properties (comma-separated)"))
	_properties_edit = LineEdit.new()
	_properties_edit.placeholder_text = "e.g. Light, Finesse, Thrown"
	form.add_child(_properties_edit)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 8)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(_cancel_btn)
	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.pressed.connect(_on_save)
	btn_row.add_child(_save_btn)
	outer.add_child(btn_row)


# ---------------------------------------------------------------------------
# Populate / Collect
# ---------------------------------------------------------------------------

func _populate_fields() -> void:
	_name_edit.text = _data.name

	# Category dropdown
	var found_cat: bool = false
	for i: int in range(_category_option.item_count):
		if _category_option.get_item_text(i) == _data.category:
			_category_option.select(i)
			found_cat = true
			break
	if not found_cat and not _data.category.is_empty():
		_category_option.add_item(_data.category)
		_category_option.select(_category_option.item_count - 1)

	_desc_edit.text = _data.desc

	# Cost
	_cost_qty_spin.value = float(int(_data.cost.get("quantity", 0)))
	var cost_unit: String = str(_data.cost.get("unit", "gp"))
	for i: int in range(_cost_unit_option.item_count):
		if _cost_unit_option.get_item_text(i) == cost_unit:
			_cost_unit_option.select(i)
			break

	_weight_spin.value = _data.weight

	# Damage
	_damage_dice_edit.text = str(_data.damage.get("damage_dice", ""))
	_damage_type_edit.text = str(_data.damage.get("damage_type", ""))

	# AC
	_ac_base_spin.value = float(int(_data.armor_class.get("base", 0)))
	_ac_dex_check.button_pressed = bool(_data.armor_class.get("dex_bonus", false))
	_ac_max_bonus_spin.value = float(int(_data.armor_class.get("max_bonus", 0)))

	# Range
	_range_normal_spin.value = float(int(_data.item_range.get("normal", 0)))
	_range_long_spin.value = float(int(_data.item_range.get("long", 0)))

	# Properties
	var props: PackedStringArray = PackedStringArray()
	for p: Variant in _data.properties:
		props.append(str(p))
	_properties_edit.text = ", ".join(props)


func _collect_fields() -> void:
	_data.name = _name_edit.text.strip_edges()
	_data.category = _category_option.get_item_text(_category_option.selected)
	_data.desc = _desc_edit.text.strip_edges()

	var cost_qty: int = int(_cost_qty_spin.value)
	var cost_unit: String = _cost_unit_option.get_item_text(_cost_unit_option.selected)
	_data.cost = {"quantity": cost_qty, "unit": cost_unit}

	_data.weight = _weight_spin.value

	# Damage
	var dice: String = _damage_dice_edit.text.strip_edges()
	var dtype: String = _damage_type_edit.text.strip_edges()
	if dice.is_empty():
		_data.damage = {}
	else:
		_data.damage = {"damage_dice": dice, "damage_type": dtype}

	# AC
	var ac_base: int = int(_ac_base_spin.value)
	if ac_base > 0:
		_data.armor_class = {
			"base": ac_base,
			"dex_bonus": _ac_dex_check.button_pressed,
			"max_bonus": int(_ac_max_bonus_spin.value),
		}
	else:
		_data.armor_class = {}

	# Range
	var r_normal: int = int(_range_normal_spin.value)
	var r_long: int = int(_range_long_spin.value)
	if r_normal > 0:
		_data.item_range = {"normal": r_normal, "long": r_long}
	else:
		_data.item_range = {}

	# Properties
	var raw: String = _properties_edit.text.strip_edges()
	if raw.is_empty():
		_data.properties = []
	else:
		var parts: PackedStringArray = raw.split(",")
		_data.properties = []
		for part: String in parts:
			var trimmed: String = part.strip_edges()
			if not trimmed.is_empty():
				_data.properties.append(trimmed)

	# Ensure custom source
	if _data.source.is_empty():
		_data.source = "custom"
	if _data.ruleset.is_empty():
		_data.ruleset = "custom"


# ---------------------------------------------------------------------------
# Callbacks
# ---------------------------------------------------------------------------

func _on_save() -> void:
	_collect_fields()
	if _data.name.is_empty():
		_data.name = "Unnamed Item"
	item_saved.emit(_data)
	hide()


func _on_cancel() -> void:
	hide()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_ui_scale_mgr() -> UIScaleManager:
	if _registry != null and _registry.ui_scale != null:
		return _registry.ui_scale
	return null


func reapply_theme() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.ui_theme == null:
		return
	var s_val: float = reg.ui_scale.get_scale() if reg.ui_scale != null else 1.0
	reg.ui_theme.theme_control_tree(self , s_val)
	if reg.ui_scale != null:
		for child: Node in get_children():
			if child is Control:
				reg.ui_scale.scale_control_fonts(child as Control, 14.0)


func _make_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.modulate = Color(0.8, 0.8, 0.8)
	return lbl
