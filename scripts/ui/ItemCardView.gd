extends VBoxContainer
class_name ItemCardView

# ---------------------------------------------------------------------------
# ItemCardView — formatted equipment/item card (reusable widget).
#
# Call display(item) to populate all fields.  Suitable for embedding inside
# a ScrollContainer in the library browser or a popup.
# ---------------------------------------------------------------------------

var _current: ItemEntry = null

var _name_label: Label = null
var _category_label: Label = null
var _cost_label: RichTextLabel = null
var _weight_label: RichTextLabel = null
var _damage_label: RichTextLabel = null
var _ac_label: RichTextLabel = null
var _range_label: RichTextLabel = null
var _properties_label: RichTextLabel = null
var _desc_label: RichTextLabel = null


func _ready() -> void:
	_build_layout()


func display(item: ItemEntry) -> void:
	_current = item
	if item == null:
		_clear()
		return
	_populate(item)


func get_current() -> ItemEntry:
	return _current


func apply_font_scale(base: float) -> void:
	var title_sz: int = roundi(base * 1.6)
	var small_sz: int = roundi(base * 0.9)
	var body_sz: int = roundi(base)

	if _name_label != null:
		_name_label.add_theme_font_size_override("font_size", title_sz)
	if _category_label != null:
		_category_label.add_theme_font_size_override("font_size", small_sz)

	for rtl: RichTextLabel in [_cost_label, _weight_label, _damage_label,
			_ac_label, _range_label, _properties_label, _desc_label]:
		if rtl != null:
			rtl.add_theme_font_size_override("normal_font_size", body_sz)
			rtl.add_theme_font_size_override("bold_font_size", body_sz)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	add_theme_constant_override("separation", 2)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	add_child(_name_label)

	_category_label = Label.new()
	_category_label.add_theme_font_size_override("font_size", 12)
	_category_label.modulate = Color(0.7, 0.7, 0.7)
	add_child(_category_label)

	add_child(_make_separator())

	_cost_label = _make_rich_label()
	add_child(_cost_label)
	_weight_label = _make_rich_label()
	add_child(_weight_label)
	_damage_label = _make_rich_label()
	add_child(_damage_label)
	_ac_label = _make_rich_label()
	add_child(_ac_label)
	_range_label = _make_rich_label()
	add_child(_range_label)
	_properties_label = _make_rich_label()
	add_child(_properties_label)

	add_child(_make_separator())

	_desc_label = _make_rich_label()
	add_child(_desc_label)


# ---------------------------------------------------------------------------
# Populate
# ---------------------------------------------------------------------------

func _populate(item: ItemEntry) -> void:
	_name_label.text = item.name

	# Category + source badge
	var cat_parts: PackedStringArray = PackedStringArray()
	if not item.category.is_empty():
		cat_parts.append(item.category)
	if not item.source.is_empty():
		cat_parts.append("[%s]" % item.source.replace("_", " ").capitalize())
	_category_label.text = " — ".join(cat_parts) if cat_parts.size() > 0 else ""

	# Cost
	if item.cost.size() > 0:
		var qty: Variant = item.cost.get("quantity", 0)
		var unit: Variant = item.cost.get("unit", "gp")
		_set_rich("[b]Cost:[/b] %s %s" % [str(qty), str(unit)], _cost_label)
		_cost_label.visible = true
	else:
		_cost_label.visible = false

	# Weight
	if item.weight > 0.0:
		_set_rich("[b]Weight:[/b] %s lb." % _format_weight(item.weight), _weight_label)
		_weight_label.visible = true
	else:
		_weight_label.visible = false

	# Damage
	if item.damage.size() > 0 and not str(item.damage.get("damage_dice", "")).is_empty():
		var dice: String = str(item.damage.get("damage_dice", ""))
		var dtype: String = str(item.damage.get("damage_type", ""))
		var txt: String = "[b]Damage:[/b] %s" % dice
		if not dtype.is_empty():
			txt += " %s" % dtype
		_set_rich(txt, _damage_label)
		_damage_label.visible = true
	else:
		_damage_label.visible = false

	# Armor Class
	if item.armor_class.size() > 0 and int(item.armor_class.get("base", 0)) > 0:
		var base_ac: int = int(item.armor_class.get("base", 0))
		var dex: bool = bool(item.armor_class.get("dex_bonus", false))
		var max_b: int = int(item.armor_class.get("max_bonus", 0))
		var txt: String = "[b]AC:[/b] %d" % base_ac
		if dex:
			txt += " + Dex"
			if max_b > 0:
				txt += " (max %d)" % max_b
		_set_rich(txt, _ac_label)
		_ac_label.visible = true
	else:
		_ac_label.visible = false

	# Range
	if item.item_range.size() > 0 and int(item.item_range.get("normal", 0)) > 0:
		var normal: int = int(item.item_range.get("normal", 0))
		var long: int = int(item.item_range.get("long", 0))
		var txt: String = "[b]Range:[/b] %d ft." % normal
		if long > 0:
			txt += " / %d ft." % long
		_set_rich(txt, _range_label)
		_range_label.visible = true
	else:
		_range_label.visible = false

	# Properties
	if item.properties.size() > 0:
		var names: PackedStringArray = PackedStringArray()
		for prop: Variant in item.properties:
			names.append(str(prop))
		_set_rich("[b]Properties:[/b] %s" % ", ".join(names), _properties_label)
		_properties_label.visible = true
	else:
		_properties_label.visible = false

	# Description
	if not item.desc.is_empty():
		_set_rich(item.desc, _desc_label)
		_desc_label.visible = true
	else:
		_desc_label.visible = false


func _clear() -> void:
	_name_label.text = ""
	_category_label.text = ""
	for rtl: RichTextLabel in [_cost_label, _weight_label, _damage_label,
			_ac_label, _range_label, _properties_label, _desc_label]:
		if rtl != null:
			rtl.text = ""
			rtl.visible = false


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_rich_label() -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.selection_enabled = true
	rtl.add_theme_font_size_override("normal_font_size", 14)
	rtl.add_theme_font_size_override("bold_font_size", 14)
	return rtl


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	return sep


func _set_rich(bbcode: String, rtl: RichTextLabel) -> void:
	rtl.text = ""
	rtl.append_text(bbcode)


func _format_weight(w: float) -> String:
	if absf(w - roundf(w)) < 0.001:
		return str(int(w))
	return "%0.1f" % w
