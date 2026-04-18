extends VBoxContainer

# -----------------------------------------------------------------------------
# WizardStepBackground — Step 4: Background selection (2014) or info note (2024).
# -----------------------------------------------------------------------------

var _wizard: CharacterWizard = null

var _bg_2014_panel: VBoxContainer = null
var _bg_option: OptionButton = null
var _bg_2024_label: Label = null


func _init(wizard: CharacterWizard) -> void:
	_wizard = wizard
	name = "StepBackground"
	add_theme_constant_override("separation", 8)
	_build()


func _build() -> void:
	_bg_2014_panel = VBoxContainer.new()
	_bg_2014_panel.add_theme_constant_override("separation", 6)
	add_child(_bg_2014_panel)

	var lbl := Label.new()
	lbl.text = "Background:"
	_bg_2014_panel.add_child(lbl)

	_bg_option = OptionButton.new()
	for bg: String in WizardConstants.BACKGROUNDS:
		_bg_option.add_item(bg)
	_bg_option.item_selected.connect(_on_background_selected)
	_bg_2014_panel.add_child(_bg_option)

	var note := Label.new()
	note.text = "(Backgrounds are cosmetic at this stage — mechanical bonuses apply in a future update.)"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
	note.modulate = Color(0.7, 0.7, 0.7)
	_bg_2014_panel.add_child(note)

	_bg_2024_label = Label.new()
	_bg_2024_label.text = (
		"In D&D 2024, backgrounds grant an Ability Score Increase, an Origin Feat, "
		+"skill proficiencies, and starting equipment.\n\n"
		+"Choose your background during your first session with your DM."
	)
	_bg_2024_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_bg_2024_label.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	add_child(_bg_2024_label)


func refresh_ui() -> void:
	if _bg_2014_panel != null:
		_bg_2014_panel.visible = (_wizard.ruleset == "2014")
	if _bg_2024_label != null:
		_bg_2024_label.visible = (_wizard.ruleset != "2014")


func _on_background_selected(idx: int) -> void:
	_wizard.background = idx
