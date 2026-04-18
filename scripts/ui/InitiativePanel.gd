extends PanelContainer
class_name InitiativePanel

## Initiative tracker panel for the DM window.
##
## Displays sorted initiative order with HP bars, conditions, and quick
## action buttons. Wired to CombatService signals.

signal damage_requested(token_id: String)
signal heal_requested(token_id: String)
## Emitted when the panel itself initiates a combat start (so DMWindow can show
## the panel if it was hidden).
signal combat_start_requested
## Emitted when an action macro button is pressed for the active combatant.
signal action_macro_pressed(token_id: String, action: String)

var _toolbar: HBoxContainer = null
var _start_btn: Button = null
var _roll_btn: Button = null
var _add_btn: Button = null
var _reset_names_btn: Button = null
var _next_btn: Button = null
var _prev_btn: Button = null
var _round_label: Label = null
var _scroll: ScrollContainer = null
var _entry_vbox: VBoxContainer = null
var _entries: Dictionary = {} ## token_id -> InitiativeEntry
var _undock_btn: Button = null
var _inner_vbox: VBoxContainer = null
var _title_bar: HBoxContainer = null
var _title_lbl: Label = null
var _selected_map_token: String = ""

# Action macro buttons.
var _macro_bar: HBoxContainer = null
var _macro_buttons: Array[Button] = []

# Turn timer.
var _timer_bar: HBoxContainer = null
var _timer_label: Label = null
var _timer_toggle_btn: Button = null
var _timer_spin: SpinBox = null
var _turn_timer: Timer = null
var _timer_seconds_remaining: int = 0
var _timer_enabled: bool = false
var _timer_duration: int = 120 ## Default 2 minutes per turn.


func _ready() -> void:
	_build_ui()
	_refresh_button_states()


## Called by DMWindow after creation and on every scale change.
func apply_scale(s: float) -> void:
	var si := func(base: float) -> int: return roundi(base * s)
	if _inner_vbox != null:
		_inner_vbox.add_theme_constant_override("separation", si.call(4.0))
	if _title_bar != null:
		_title_bar.add_theme_constant_override("separation", si.call(4.0))
	if _title_lbl != null:
		_title_lbl.add_theme_font_size_override("font_size", si.call(14.0))
	if _undock_btn != null:
		_undock_btn.custom_minimum_size = Vector2(si.call(28.0), si.call(28.0))
		_undock_btn.add_theme_font_size_override("font_size", si.call(13.0))
	if _toolbar != null:
		_toolbar.add_theme_constant_override("separation", si.call(4.0))
	for btn: Button in [_start_btn, _roll_btn, _add_btn, _reset_names_btn]:
		if btn != null:
			btn.custom_minimum_size = Vector2(0, si.call(26.0))
			btn.add_theme_font_size_override("font_size", si.call(12.0))
	for btn: Button in [_prev_btn, _next_btn]:
		if btn != null:
			btn.custom_minimum_size = Vector2(si.call(28.0), si.call(26.0))
			btn.add_theme_font_size_override("font_size", si.call(13.0))
	if _round_label != null:
		_round_label.custom_minimum_size.x = si.call(70.0)
		_round_label.add_theme_font_size_override("font_size", si.call(12.0))
	if _entry_vbox != null:
		_entry_vbox.add_theme_constant_override("separation", si.call(2.0))
	var bg: StyleBoxFlat = get_theme_stylebox("panel") as StyleBoxFlat
	if bg != null:
		var m: float = 8.0 * s
		bg.content_margin_left = m
		bg.content_margin_right = m
		bg.content_margin_top = m
		bg.content_margin_bottom = m
	# Scale all child entries.
	for entry: Variant in _entries.values():
		var ie: InitiativeEntry = entry as InitiativeEntry
		if ie != null:
			ie.apply_scale(s)
	# Scale macro buttons.
	if _macro_bar != null:
		_macro_bar.add_theme_constant_override("separation", si.call(2.0))
	for btn: Button in _macro_buttons:
		if btn != null:
			btn.custom_minimum_size = Vector2(0, si.call(22.0))
			btn.add_theme_font_size_override("font_size", si.call(10.0))
	# Scale timer bar.
	if _timer_toggle_btn != null:
		_timer_toggle_btn.custom_minimum_size = Vector2(si.call(28.0), si.call(22.0))
		_timer_toggle_btn.add_theme_font_size_override("font_size", si.call(12.0))
	if _timer_label != null:
		_timer_label.add_theme_font_size_override("font_size", si.call(12.0))
		_timer_label.custom_minimum_size.x = si.call(50.0)


func _build_ui() -> void:
	_inner_vbox = VBoxContainer.new()
	_inner_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inner_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inner_vbox.add_theme_constant_override("separation", 4)
	add_child(_inner_vbox)

	# Title bar.
	_title_bar = HBoxContainer.new()
	_title_bar.add_theme_constant_override("separation", 4)
	_inner_vbox.add_child(_title_bar)

	_title_lbl = Label.new()
	_title_lbl.text = "Initiative"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.add_theme_font_size_override("font_size", 14)
	_title_bar.add_child(_title_lbl)

	_undock_btn = Button.new()
	_undock_btn.text = "⇲"
	_undock_btn.tooltip_text = "Undock panel"
	_undock_btn.custom_minimum_size = Vector2(28, 28)
	_title_bar.add_child(_undock_btn)

	_inner_vbox.add_child(HSeparator.new())

	# Toolbar.
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 4)
	_inner_vbox.add_child(_toolbar)

	_start_btn = Button.new()
	_start_btn.text = "Start Combat"
	_start_btn.pressed.connect(_on_start_pressed)
	_toolbar.add_child(_start_btn)

	_roll_btn = Button.new()
	_roll_btn.text = "Roll All"
	_roll_btn.tooltip_text = "Roll initiative for all combatants"
	_roll_btn.pressed.connect(_on_roll_pressed)
	_toolbar.add_child(_roll_btn)

	_add_btn = Button.new()
	_add_btn.text = "+"
	_add_btn.tooltip_text = "Add selected token(s) to combat"
	_add_btn.pressed.connect(_on_add_pressed)
	_toolbar.add_child(_add_btn)

	_reset_names_btn = Button.new()
	_reset_names_btn.text = "↺"
	_reset_names_btn.tooltip_text = "Reset token numbers (renumber from 1)"
	_reset_names_btn.pressed.connect(_on_reset_names_pressed)
	_toolbar.add_child(_reset_names_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(spacer)

	_prev_btn = Button.new()
	_prev_btn.text = "◀"
	_prev_btn.tooltip_text = "Previous Turn"
	_prev_btn.pressed.connect(_on_prev_pressed)
	_toolbar.add_child(_prev_btn)

	_round_label = Label.new()
	_round_label.text = "Round: —"
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.custom_minimum_size.x = 70.0
	_toolbar.add_child(_round_label)

	_next_btn = Button.new()
	_next_btn.text = "▶"
	_next_btn.tooltip_text = "Next Turn"
	_next_btn.pressed.connect(_on_next_pressed)
	_toolbar.add_child(_next_btn)

	# Action macros bar.
	_macro_bar = HBoxContainer.new()
	_macro_bar.add_theme_constant_override("separation", 2)
	_inner_vbox.add_child(_macro_bar)
	_macro_buttons.clear()
	for action_name: String in ["Attack", "Cast", "Dash", "Dodge", "Disengage", "Help", "Hide"]:
		var btn := Button.new()
		btn.text = action_name
		btn.tooltip_text = action_name + " action"
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_macro_pressed.bind(action_name))
		_macro_bar.add_child(btn)
		_macro_buttons.append(btn)

	# Turn timer bar.
	_timer_bar = HBoxContainer.new()
	_timer_bar.add_theme_constant_override("separation", 4)
	_inner_vbox.add_child(_timer_bar)

	_timer_toggle_btn = Button.new()
	_timer_toggle_btn.text = "⏱"
	_timer_toggle_btn.tooltip_text = "Toggle turn timer"
	_timer_toggle_btn.toggle_mode = true
	_timer_toggle_btn.button_pressed = false
	_timer_toggle_btn.toggled.connect(_on_timer_toggled)
	_timer_bar.add_child(_timer_toggle_btn)

	var timer_lbl := Label.new()
	timer_lbl.text = "Timer:"
	_timer_bar.add_child(timer_lbl)

	_timer_spin = SpinBox.new()
	_timer_spin.min_value = 10
	_timer_spin.max_value = 600
	_timer_spin.step = 10
	_timer_spin.value = _timer_duration
	_timer_spin.suffix = "s"
	_timer_spin.tooltip_text = "Seconds per turn"
	_timer_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer_spin.value_changed.connect(func(val: float) -> void: _timer_duration = int(val))
	_timer_bar.add_child(_timer_spin)

	_timer_label = Label.new()
	_timer_label.text = ""
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.custom_minimum_size.x = 50.0
	_timer_bar.add_child(_timer_label)

	# Internal timer node.
	_turn_timer = Timer.new()
	_turn_timer.wait_time = 1.0
	_turn_timer.timeout.connect(_on_timer_tick)
	add_child(_turn_timer)

	_inner_vbox.add_child(HSeparator.new())

	# Scrollable entry list.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inner_vbox.add_child(_scroll)

	_entry_vbox = VBoxContainer.new()
	_entry_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry_vbox.add_theme_constant_override("separation", 2)
	_scroll.add_child(_entry_vbox)

	# Background style.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_left = 6
	bg.corner_radius_bottom_right = 6
	bg.content_margin_left = 8.0
	bg.content_margin_right = 8.0
	bg.content_margin_top = 8.0
	bg.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", bg)


## Full rebuild of initiative entries from service state.
func refresh(combat_mgr: CombatManager, token_mgr: TokenManager,
		statblock_mgr: StatblockManager) -> void:
	if combat_mgr == null:
		return
	_clear_entries()
	var order: Array = combat_mgr.get_initiative_order()
	var current_tid: String = combat_mgr.get_current_turn_token_id()
	var round_num: int = combat_mgr.get_round_number()

	for entry_data: Dictionary in order:
		var tid: String = str(entry_data.get("token_id", ""))
		var init_val: int = int(entry_data.get("initiative", 0))
		if tid.is_empty():
			continue

		# Resolve token name and HP.
		var token_name: String = tid
		var current_hp: int = 0
		var max_hp: int = 0
		var temp_hp: int = 0
		var conditions: Array = []

		if token_mgr != null:
			var td: TokenData = token_mgr.get_token_by_id(tid)
			if td != null:
				# Prefer the token label; fall back to the primary statblock name.
				if not td.label.is_empty():
					token_name = td.label
				elif not td.statblock_refs.is_empty() and statblock_mgr != null:
					var sb_id: String = str(td.statblock_refs[0])
					var sb: StatblockData = statblock_mgr.get_statblock(sb_id)
					if sb != null and not sb.name.is_empty():
						token_name = sb.name
				else:
					token_name = tid
				if not td.statblock_refs.is_empty():
					var sb_id: String = str(td.statblock_refs[0])
					var raw: Variant = td.statblock_overrides.get(sb_id, null)
					if raw is Dictionary:
						var so: StatblockOverride = StatblockOverride.from_dict(
							raw as Dictionary)
						current_hp = so.current_hp
						max_hp = so.max_hp
						temp_hp = so.temp_hp
						conditions = so.conditions
			else:
				# No TokenData — this may be a player token; look up the profile name
				# and HP from the combat service's player overrides.
				var reg_ref: ServiceRegistry = _get_registry()
				if reg_ref != null and reg_ref.profile != null:
					var prof: Variant = reg_ref.profile.get_profile_by_id(tid)
					if prof is PlayerProfile and not (prof as PlayerProfile).player_name.is_empty():
						token_name = (prof as PlayerProfile).player_name
				if reg_ref != null and reg_ref.combat != null:
					var status: Dictionary = reg_ref.combat.get_hp_status(tid)
					current_hp = int(status.get("current", 0))
					max_hp = int(status.get("max", 0))
					temp_hp = int(status.get("temp", 0))
					conditions = reg_ref.combat.get_conditions(tid)

		var row := InitiativeEntry.new()
		_entry_vbox.add_child(row)
		row.set_data(tid, token_name, init_val, current_hp, max_hp, temp_hp,
			conditions, tid == current_tid)
		row.initiative_value_changed.connect(_on_entry_init_changed)
		row.damage_requested.connect(func(id: String) -> void:
			damage_requested.emit(id))
		row.heal_requested.connect(func(id: String) -> void:
			heal_requested.emit(id))
		row.delay_requested.connect(_on_entry_delay)
		row.remove_requested.connect(_on_entry_remove)
		_entries[tid] = row

	# Restore map-selection highlight after rebuild.
	if not _selected_map_token.is_empty() and _entries.has(_selected_map_token):
		var sel_entry: InitiativeEntry = _entries[_selected_map_token] as InitiativeEntry
		if sel_entry != null:
			sel_entry.set_map_selected(true)

	_update_round_label(round_num)
	_refresh_button_states()
	_scroll_to_active_entry()

func _scroll_to_active_entry() -> void:
	## Scroll the list so the current-turn entry is visible.
	if _scroll == null or _entry_vbox == null:
		return
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null:
		return
	var current_tid: String = reg.combat.get_current_turn_token_id()
	if current_tid.is_empty() or not _entries.has(current_tid):
		return
	var entry: InitiativeEntry = _entries[current_tid] as InitiativeEntry
	if entry == null:
		return
	# Deferred so layout has settled before we read positions.
	entry.call_deferred("_scroll_into_view", _scroll)


func _clear_entries() -> void:
	for child: Node in _entry_vbox.get_children():
		_entry_vbox.remove_child(child)
		child.queue_free()
	_entries.clear()


func _update_round_label(round_num: int) -> void:
	if _round_label != null:
		_round_label.text = "Round: %d" % round_num


func _refresh_button_states() -> void:
	var reg: ServiceRegistry = _get_registry()
	var in_combat: bool = reg != null and reg.combat != null and reg.combat.is_in_combat()
	if _start_btn != null:
		_start_btn.text = "End Combat" if in_combat else "Start Combat"
	if _roll_btn != null:
		_roll_btn.disabled = not in_combat
	if _add_btn != null:
		_add_btn.disabled = not in_combat
	if _next_btn != null:
		_next_btn.disabled = not in_combat
	if _prev_btn != null:
		_prev_btn.disabled = not in_combat
	# Macro bar and timer bar only visible during combat.
	if _macro_bar != null:
		_macro_bar.visible = in_combat
	if _timer_bar != null:
		_timer_bar.visible = in_combat
	if not in_combat:
		_stop_timer()


func _on_start_pressed() -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null:
		return
	if reg.combat.is_in_combat():
		reg.combat.end_combat()
		_clear_entries()
		_refresh_button_states()
	else:
		# Start combat with currently selected tokens, or all monsters.
		var token_ids: Array[String] = _gather_combat_tokens(reg)
		if token_ids.is_empty():
			return
		combat_start_requested.emit()
		reg.combat.start_combat(token_ids)


func _on_roll_pressed() -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null:
		return
	reg.combat.roll_initiative_all()


func _on_next_pressed() -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null:
		return
	reg.combat.next_turn()


func _on_prev_pressed() -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null:
		return
	reg.combat.previous_turn()


func _on_add_pressed() -> void:
	## Add currently selected token(s) to the active combat.
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null or not reg.combat.is_in_combat():
		return
	if reg.selection == null:
		return
	var ids: Array[String] = reg.selection.get_selected_ids()
	if ids.is_empty():
		return
	for tid: String in ids:
		reg.combat.add_combatant(tid)


func _on_reset_names_pressed() -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null or not reg.combat.is_in_combat():
		return
	reg.combat.reset_combat_labels()


func _on_entry_init_changed(token_id: String, value: int) -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null:
		return
	reg.combat.set_initiative(token_id, value)


func _on_entry_delay(token_id: String) -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null:
		return
	reg.combat.delay_turn(token_id)


func _on_entry_remove(token_id: String) -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null:
		return
	reg.combat.remove_combatant(token_id)


func _gather_combat_tokens(reg: ServiceRegistry) -> Array[String]:
	var ids: Array[String] = []
	var id_set: Dictionary = {} ## For deduplication.
	# If tokens are explicitly selected, include those.
	if reg.selection != null:
		for tid: String in reg.selection.get_selected_ids():
			if not id_set.has(tid):
				ids.append(tid)
				id_set[tid] = true
	# If no selection, fall back to all monsters + NPCs on the map.
	if ids.is_empty() and reg.token != null:
		for raw: Variant in reg.token.get_all_tokens():
			var td: TokenData = raw as TokenData
			if td == null:
				continue
			if td.category == TokenData.TokenCategory.MONSTER or \
					td.category == TokenData.TokenCategory.NPC:
				if not id_set.has(td.id):
					ids.append(td.id)
					id_set[td.id] = true
	return ids


## Highlight the initiative row for the token currently selected on the map.
func set_selected_token(token_id: String) -> void:
	# Clear old highlight.
	if not _selected_map_token.is_empty() and _entries.has(_selected_map_token):
		var old_entry: InitiativeEntry = _entries[_selected_map_token] as InitiativeEntry
		if old_entry != null:
			old_entry.set_map_selected(false)
	_selected_map_token = token_id
	if not token_id.is_empty() and _entries.has(token_id):
		var new_entry: InitiativeEntry = _entries[token_id] as InitiativeEntry
		if new_entry != null:
			new_entry.set_map_selected(true)


func _get_registry() -> ServiceRegistry:
	return get_node_or_null("/root/ServiceRegistry") as ServiceRegistry


# ---------------------------------------------------------------------------
# Action macros
# ---------------------------------------------------------------------------

func _on_macro_pressed(action: String) -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.combat == null or not reg.combat.is_in_combat():
		return
	var tid: String = reg.combat.get_current_turn_token_id()
	if tid.is_empty():
		return
	# Log the action to combat log.
	var token_name: String = tid
	if reg.token != null:
		var td: TokenData = reg.token.get_token_by_id(tid)
		if td != null and not td.label.is_empty():
			token_name = td.label
	reg.combat.add_log_entry({
		"type": "action",
		"text": "%s uses %s" % [token_name, action],
	})
	action_macro_pressed.emit(tid, action)


# ---------------------------------------------------------------------------
# Turn timer
# ---------------------------------------------------------------------------

func _on_timer_toggled(pressed: bool) -> void:
	_timer_enabled = pressed
	if pressed:
		_restart_timer()
	else:
		_stop_timer()


func _restart_timer() -> void:
	if not _timer_enabled:
		return
	_timer_seconds_remaining = _timer_duration
	_update_timer_display()
	if _turn_timer != null:
		_turn_timer.start()


func _stop_timer() -> void:
	if _turn_timer != null:
		_turn_timer.stop()
	_timer_seconds_remaining = 0
	if _timer_label != null:
		_timer_label.text = ""


func _on_timer_tick() -> void:
	_timer_seconds_remaining -= 1
	_update_timer_display()
	if _timer_seconds_remaining <= 0:
		_turn_timer.stop()
		if _timer_label != null:
			_timer_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))


func _update_timer_display() -> void:
	if _timer_label == null:
		return
	@warning_ignore("integer_division")
	var mins: int = _timer_seconds_remaining / 60
	var secs: int = _timer_seconds_remaining % 60
	_timer_label.text = "%d:%02d" % [mins, secs]
	# Color shift: green > yellow > red.
	var ratio: float = clampf(float(_timer_seconds_remaining) / maxf(float(_timer_duration), 1.0), 0.0, 1.0)
	if ratio > 0.5:
		_timer_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	elif ratio > 0.2:
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	else:
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))


## Called externally when the turn changes so the timer can restart.
func on_turn_changed() -> void:
	if _timer_enabled:
		_restart_timer()
