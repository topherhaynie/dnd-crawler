extends Window
class_name QuickDamageDialog

## Unified popup for applying damage, healing, or temporary HP to a token.
##
## Usage:
##   var dlg := QuickDamageDialog.new()
##   add_child(dlg)
##   dlg.open(token_id, token_name, QuickDamageDialog.HpMode.DAMAGE)
##   dlg.applied.connect(func(tid, amount, damage_type, mode): ...)

enum HpMode {DAMAGE, HEAL, TEMP_HP}

signal applied(token_id: String, amount: int, damage_type: String, mode: HpMode)

const DAMAGE_TYPES: PackedStringArray = [
	"", "acid", "bludgeoning", "cold", "fire", "force",
	"lightning", "necrotic", "piercing", "poison", "psychic",
	"radiant", "slashing", "thunder",
]

var _token_id: String = ""
var _mode: HpMode = HpMode.DAMAGE

var _margin: MarginContainer = null
var _vbox: VBoxContainer = null
var _title_label: Label = null
var _mode_damage_btn: Button = null
var _mode_heal_btn: Button = null
var _mode_temp_btn: Button = null
var _amount_spin: SpinBox = null
var _type_row: HBoxContainer = null
var _type_option: OptionButton = null
var _apply_btn: Button = null
var _cancel_btn: Button = null


func _ready() -> void:
	title = "HP Adjustment"
	size = Vector2i(340, 210)
	exclusive = true
	wrap_controls = true
	close_requested.connect(hide)
	_build_ui()


## Called by DMWindow after creation and on every scale change.
func apply_scale(s: float) -> void:
	var si := func(base: float) -> int: return roundi(base * s)
	if _margin != null:
		for side: String in ["left", "right", "top", "bottom"]:
			_margin.add_theme_constant_override("margin_" + side, si.call(12.0))
	if _vbox != null:
		_vbox.add_theme_constant_override("separation", si.call(8.0))
	if _title_label != null:
		_title_label.add_theme_font_size_override("font_size", si.call(14.0))
	if _amount_spin != null:
		_amount_spin.get_line_edit().add_theme_font_size_override("font_size", si.call(14.0))
	var btn_font_size: int = si.call(13.0)
	var btn_min_h: int = si.call(30.0)
	for btn: Button in [_mode_damage_btn, _mode_heal_btn, _mode_temp_btn,
			_apply_btn, _cancel_btn]:
		if btn != null:
			btn.add_theme_font_size_override("font_size", btn_font_size)
			btn.custom_minimum_size = Vector2(0, btn_min_h)
	# Re-fit window to new content size.
	reset_size()


func _build_ui() -> void:
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", 12)
	_margin.add_theme_constant_override("margin_right", 12)
	_margin.add_theme_constant_override("margin_top", 12)
	_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(_margin)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	_margin.add_child(_vbox)

	# Token name header.
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_title_label)

	# Mode selector row.
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_child(mode_row)

	_mode_damage_btn = Button.new()
	_mode_damage_btn.text = "⚔ Damage"
	_mode_damage_btn.toggle_mode = true
	_mode_damage_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_damage_btn.pressed.connect(func() -> void: _set_mode(HpMode.DAMAGE))
	mode_row.add_child(_mode_damage_btn)

	_mode_heal_btn = Button.new()
	_mode_heal_btn.text = "♥ Heal"
	_mode_heal_btn.toggle_mode = true
	_mode_heal_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_heal_btn.pressed.connect(func() -> void: _set_mode(HpMode.HEAL))
	mode_row.add_child(_mode_heal_btn)

	_mode_temp_btn = Button.new()
	_mode_temp_btn.text = "🛡 Temp HP"
	_mode_temp_btn.toggle_mode = true
	_mode_temp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_temp_btn.pressed.connect(func() -> void: _set_mode(HpMode.TEMP_HP))
	mode_row.add_child(_mode_temp_btn)

	# Amount row.
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 8)
	_vbox.add_child(amount_row)

	var amount_lbl := Label.new()
	amount_lbl.text = "Amount:"
	amount_row.add_child(amount_lbl)

	_amount_spin = SpinBox.new()
	_amount_spin.min_value = 1
	_amount_spin.max_value = 9999
	_amount_spin.value = 1
	_amount_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_row.add_child(_amount_spin)

	# Damage type row (visible only in Damage mode).
	_type_row = HBoxContainer.new()
	_type_row.add_theme_constant_override("separation", 8)
	_vbox.add_child(_type_row)

	var type_lbl := Label.new()
	type_lbl.text = "Type:"
	_type_row.add_child(type_lbl)

	_type_option = OptionButton.new()
	_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for dt: String in DAMAGE_TYPES:
		_type_option.add_item(dt.capitalize() if not dt.is_empty() else "(none)")
	_type_row.add_child(_type_option)

	# Action buttons.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	_vbox.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(hide)
	btn_row.add_child(_cancel_btn)

	_apply_btn = Button.new()
	_apply_btn.text = "Apply"
	_apply_btn.pressed.connect(_on_apply)
	btn_row.add_child(_apply_btn)


## Open the dialog targeting a specific token and pre-selecting the given mode.
func open(token_id: String, token_name: String, initial_mode: HpMode = HpMode.DAMAGE) -> void:
	_token_id = token_id
	if _title_label != null:
		_title_label.text = token_name
	if _amount_spin != null:
		_amount_spin.value = 1
	_set_mode(initial_mode)
	reset_size()
	popup_centered()


## Convenience wrappers kept for backward compatibility.
func open_damage(token_id: String, token_name: String) -> void:
	open(token_id, token_name, HpMode.DAMAGE)


func open_healing(token_id: String, token_name: String) -> void:
	open(token_id, token_name, HpMode.HEAL)


func _set_mode(m: HpMode) -> void:
	_mode = m
	if _mode_damage_btn != null:
		_mode_damage_btn.button_pressed = (m == HpMode.DAMAGE)
	if _mode_heal_btn != null:
		_mode_heal_btn.button_pressed = (m == HpMode.HEAL)
	if _mode_temp_btn != null:
		_mode_temp_btn.button_pressed = (m == HpMode.TEMP_HP)
	if _type_row != null:
		_type_row.visible = (m == HpMode.DAMAGE)
	var mode_titles: Array[String] = ["Damage", "Heal", "Temp HP"]
	title = "HP Adjustment — %s" % mode_titles[m]


func _on_apply() -> void:
	var amount: int = int(_amount_spin.value) if _amount_spin != null else 0
	var dtype: String = ""
	if _mode == HpMode.DAMAGE and _type_option != null and _type_option.selected > 0:
		dtype = DAMAGE_TYPES[_type_option.selected]
	applied.emit(_token_id, amount, dtype, _mode)
	hide()
