extends Window
class_name PlayerSavePromptDialog

## Modal prompt shown for each selected player during a group save.
##
## The DM can choose to roll for the player, mark the save as passed, or mark
## it as failed without rolling.

signal choice_selected(token_id: String, choice: String)
signal closed

var _token_id: String = ""
var _ability: String = ""
var _dc: int = 0
var _root: VBoxContainer = null
var _name_label: Label = null
var _details_label: Label = null
var _roll_btn: Button = null
var _saved_btn: Button = null
var _failed_btn: Button = null
var _skip_btn: Button = null
var _linked_label: Label = null
var _ui_built: bool = false
const POPUP_SIZE := Vector2i(560, 340)


func _init() -> void:
	_ensure_ui()


func _ready() -> void:
	title = "Player Save"
	transient = true
	exclusive = true
	wrap_controls = false
	min_size = POPUP_SIZE
	size = POPUP_SIZE
	close_requested.connect(_on_close)
	_ensure_ui()


func _ensure_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	_build_ui()


func apply_scale(s: float) -> void:
	_ensure_ui()
	if _root == null:
		return
	var si := func(base: float) -> int: return roundi(base * s)
	_root.offset_left = si.call(12.0)
	_root.offset_right = - si.call(12.0)
	_root.offset_top = si.call(12.0)
	_root.offset_bottom = - si.call(12.0)
	_root.add_theme_constant_override("separation", si.call(8.0))
	if _name_label != null:
		_name_label.add_theme_font_size_override("font_size", si.call(16.0))
	if _details_label != null:
		_details_label.add_theme_font_size_override("font_size", si.call(13.0))
	if _linked_label != null:
		_linked_label.add_theme_font_size_override("font_size", si.call(12.0))
	for btn: Button in [_roll_btn, _saved_btn, _failed_btn, _skip_btn]:
		if btn != null:
			btn.add_theme_font_size_override("font_size", si.call(13.0))
			btn.custom_minimum_size.y = si.call(30.0)
	min_size = POPUP_SIZE
	size = POPUP_SIZE


func open(token_id: String, player_name: String, ability: String, dc: int, has_linked_statblock: bool) -> void:
	_ensure_ui()
	_token_id = token_id
	_ability = ability.to_upper()
	_dc = dc
	if _name_label != null:
		_name_label.text = player_name
	if _details_label != null:
		_details_label.text = "Save: %s DC %d" % [_ability, _dc]
	if _linked_label != null:
		_linked_label.text = "Linked statblock: %s" % ("Yes" if has_linked_statblock else "No")
	min_size = POPUP_SIZE
	size = POPUP_SIZE
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

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_name_label)

	_details_label = Label.new()
	_details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_details_label)

	_linked_label = Label.new()
	_linked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_linked_label)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Choose how to resolve this player's save."
	_root.add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(row)

	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_spacer)

	_roll_btn = Button.new()
	_roll_btn.text = "Roll"
	_roll_btn.pressed.connect(func() -> void: _emit_choice("roll"))
	row.add_child(_roll_btn)

	_saved_btn = Button.new()
	_saved_btn.text = "Saved"
	_saved_btn.pressed.connect(func() -> void: _emit_choice("saved"))
	row.add_child(_saved_btn)

	_failed_btn = Button.new()
	_failed_btn.text = "Failed"
	_failed_btn.pressed.connect(func() -> void: _emit_choice("failed"))
	row.add_child(_failed_btn)

	_skip_btn = Button.new()
	_skip_btn.text = "Skip"
	_skip_btn.pressed.connect(func() -> void: _emit_choice("skip"))
	row.add_child(_skip_btn)

	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_spacer)


func _emit_choice(choice: String) -> void:
	hide()
	choice_selected.emit(_token_id, choice)


func _on_close() -> void:
	closed.emit()
	hide()
