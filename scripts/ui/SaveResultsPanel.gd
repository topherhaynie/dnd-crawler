extends Window
class_name SaveResultsPanel

## Modal dialog showing batch saving throw results with override and damage
## application buttons.
##
## Opened by DMWindow after CombatService.call_for_save().
## Emits apply_damage_to_results when the DM applies damage based on results.

signal apply_damage_to_results(results: Array, damage_amount: int,
	damage_type: String, half_on_pass: bool)
signal closed

var _ability: String = ""
var _dc: int = 0
var _results: Array = []

# UI nodes
var _table_container: VBoxContainer = null
var _summary_label: Label = null
var _damage_amount_spin: SpinBox = null
var _damage_type_option: OptionButton = null
var _rows: Array = [] # Array of {hbox, cells, result_index}

const DAMAGE_TYPES: Array[String] = [
	"bludgeoning", "piercing", "slashing", "fire", "cold", "lightning",
	"thunder", "acid", "poison", "necrotic", "radiant", "force",
	"psychic", "none",
]


var _scale: float = 1.0
var _root: VBoxContainer = null


func _init() -> void:
	title = "Saving Throw Results"
	transient = true
	exclusive = true
	wrap_controls = true
	close_requested.connect(_on_close)


func _ready() -> void:
	_build_ui()


## Called by DMWindow after creation and on every scale change.
func apply_scale(s: float) -> void:
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
	if _damage_amount_spin != null:
		_damage_amount_spin.custom_minimum_size.x = si.call(80.0)
	if _damage_type_option != null:
		_damage_type_option.custom_minimum_size.x = si.call(120.0)
	min_size = Vector2i(si.call(580.0), si.call(360.0))


func _on_close() -> void:
	closed.emit()
	hide()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func show_results(ability: String, dc: int, results: Array) -> void:
	_ability = ability.to_upper()
	_dc = dc
	_results = results.duplicate(true)
	title = "Saving Throw: %s DC %d" % [_ability, _dc]
	_rebuild_table()
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

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	root.add_child(header)
	for col_name: String in ["Token", "Roll", "Mod", "Total", "Result"]:
		var lbl := Label.new()
		lbl.text = col_name
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if col_name == "Token":
			lbl.custom_minimum_size.x = 160.0
		else:
			lbl.custom_minimum_size.x = 60.0
		header.add_child(lbl)
	# Override column header
	var override_lbl := Label.new()
	override_lbl.text = "Override"
	override_lbl.add_theme_font_size_override("font_size", 14)
	override_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	override_lbl.custom_minimum_size.x = 72.0
	header.add_child(override_lbl)

	# Scrollable table body
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_table_container = VBoxContainer.new()
	_table_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_container.add_theme_constant_override("separation", 4)
	scroll.add_child(_table_container)

	# Summary label
	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 15)
	root.add_child(_summary_label)

	# Separator
	root.add_child(HSeparator.new())

	# Damage application row
	var dmg_row := HBoxContainer.new()
	dmg_row.add_theme_constant_override("separation", 8)
	root.add_child(dmg_row)

	var dmg_lbl := Label.new()
	dmg_lbl.text = "Damage:"
	dmg_row.add_child(dmg_lbl)

	_damage_amount_spin = SpinBox.new()
	_damage_amount_spin.min_value = 0
	_damage_amount_spin.max_value = 999
	_damage_amount_spin.value = 0
	_damage_amount_spin.custom_minimum_size.x = 80.0
	dmg_row.add_child(_damage_amount_spin)

	_damage_type_option = OptionButton.new()
	for dt: String in DAMAGE_TYPES:
		_damage_type_option.add_item(dt.capitalize())
	_damage_type_option.custom_minimum_size.x = 120.0
	dmg_row.add_child(_damage_type_option)

	# Action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	root.add_child(btn_row)

	var half_btn := Button.new()
	half_btn.text = "Half to Passed, Full to Failed"
	half_btn.pressed.connect(_on_apply_half_full)
	btn_row.add_child(half_btn)

	var full_fail_btn := Button.new()
	full_fail_btn.text = "Full to Failed Only"
	full_fail_btn.pressed.connect(_on_apply_full_fail)
	btn_row.add_child(full_fail_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close)
	btn_row.add_child(close_btn)


# ---------------------------------------------------------------------------
# Table rebuild
# ---------------------------------------------------------------------------

func _rebuild_table() -> void:
	# Clear existing rows.
	for child: Node in _table_container.get_children():
		child.queue_free()
	_rows.clear()

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
		name_lbl.add_theme_font_size_override("font_size", 14)
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
		roll_lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(roll_lbl)

		# Modifier
		var mod_lbl := Label.new()
		var mod_val: int = int(r.get("modifier", 0))
		mod_lbl.text = "%+d" % mod_val
		mod_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mod_lbl.custom_minimum_size.x = 60.0
		mod_lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(mod_lbl)

		# Total
		var total_lbl := Label.new()
		total_lbl.text = str(int(r.get("total", 0)))
		total_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		total_lbl.custom_minimum_size.x = 60.0
		total_lbl.add_theme_font_size_override("font_size", 14)
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
		result_lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(result_lbl)

		# Override toggle button
		var toggle_btn := Button.new()
		toggle_btn.text = "Toggle"
		toggle_btn.custom_minimum_size.x = 72.0
		toggle_btn.pressed.connect(_on_toggle_result.bind(i))
		row.add_child(toggle_btn)

		_rows.append({"hbox": row, "result_lbl": result_lbl, "index": i})

	_summary_label.text = "%d passed, %d failed" % [pass_count, fail_count]


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


func _on_apply_half_full() -> void:
	var amount: int = int(_damage_amount_spin.value)
	if amount <= 0:
		return
	var dt_idx: int = _damage_type_option.selected
	var damage_type: String = DAMAGE_TYPES[dt_idx] if dt_idx >= 0 and dt_idx < DAMAGE_TYPES.size() else "none"
	apply_damage_to_results.emit(_results.duplicate(true), amount, damage_type, true)


func _on_apply_full_fail() -> void:
	var amount: int = int(_damage_amount_spin.value)
	if amount <= 0:
		return
	var dt_idx: int = _damage_type_option.selected
	var damage_type: String = DAMAGE_TYPES[dt_idx] if dt_idx >= 0 and dt_idx < DAMAGE_TYPES.size() else "none"
	apply_damage_to_results.emit(_results.duplicate(true), amount, damage_type, false)
