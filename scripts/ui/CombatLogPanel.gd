extends PanelContainer
class_name CombatLogPanel

## Scrollable combat log panel for the DM window.
##
## Displays color-coded entries for all combat events.
## Supports filtering by type, text search, DM notes, clear and export.

const _CombatLogEntryScript = preload("res://scripts/ui/CombatLogEntry.gd")

signal undock_requested

const _FILTER_LABELS: Array = ["All", "Attacks", "Damage", "Saves", "Conditions", "Notes"]
const _FILTER_TYPES: Array[Array] = [
	[], ## All — no filter
	["attack_roll"],
	["damage_dealt", "healing_applied"],
	["saving_throw", "death_save"],
	["condition_applied", "condition_removed"],
	["custom"],
]

var _inner_vbox: VBoxContainer = null
var _title_bar: HBoxContainer = null
var _title_lbl: Label = null
var _undock_btn: Button = null
var _toolbar: HBoxContainer = null
var _filter_opt: OptionButton = null
var _search_edit: LineEdit = null
var _add_note_btn: Button = null
var _clear_btn: Button = null
var _export_btn: Button = null
var _scroll: ScrollContainer = null
var _entry_vbox: VBoxContainer = null

var _all_entries: Array = [] ## cached copy of all log entries
var _current_filter_idx: int = 0
var _search_text: String = ""
var _current_scale: float = 1.0


func _ready() -> void:
	_build_ui()


## Rebuild from a full log snapshot (called on panel open or log_entry_added).
func refresh_from_log(log_entries: Array) -> void:
	_all_entries = log_entries.duplicate(true)
	_rebuild_entries()


## Append a single new entry without a full rebuild.
func append_entry(entry: Dictionary) -> void:
	_all_entries.append(entry)
	if _entry_passes_filter(entry):
		_add_entry_widget(entry)
		_scroll_to_bottom()


## Scale all child content to the given UI scale factor.
func apply_scale(s: float) -> void:
	_current_scale = s
	var si := func(base: float) -> int: return roundi(base * s)
	if _title_lbl != null:
		_title_lbl.add_theme_font_size_override("font_size", si.call(14.0))
	if _undock_btn != null:
		_undock_btn.custom_minimum_size = Vector2(si.call(28.0), si.call(28.0))
		_undock_btn.add_theme_font_size_override("font_size", si.call(13.0))
	if _filter_opt != null:
		_filter_opt.custom_minimum_size = Vector2(si.call(90.0), si.call(26.0))
		_filter_opt.add_theme_font_size_override("font_size", si.call(11.0))
	if _search_edit != null:
		_search_edit.custom_minimum_size = Vector2(si.call(80.0), si.call(26.0))
		_search_edit.add_theme_font_size_override("font_size", si.call(11.0))
	for btn: Button in [_add_note_btn, _clear_btn, _export_btn]:
		if btn != null:
			btn.custom_minimum_size = Vector2(0, si.call(26.0))
			btn.add_theme_font_size_override("font_size", si.call(11.0))
	var bg: StyleBoxFlat = get_theme_stylebox("panel") as StyleBoxFlat
	if bg != null:
		var m: float = 8.0 * s
		bg.content_margin_left = m
		bg.content_margin_right = m
		bg.content_margin_top = m
		bg.content_margin_bottom = m
	# Rebuild log entries at the new scale so font sizes update.
	_rebuild_entries()


func _build_ui() -> void:
	_inner_vbox = VBoxContainer.new()
	_inner_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inner_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inner_vbox.add_theme_constant_override("separation", 4)
	add_child(_inner_vbox)

	# Title bar
	_title_bar = HBoxContainer.new()
	_title_bar.add_theme_constant_override("separation", 4)
	_inner_vbox.add_child(_title_bar)

	_title_lbl = Label.new()
	_title_lbl.text = "Combat Log"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.add_theme_font_size_override("font_size", 14)
	_title_bar.add_child(_title_lbl)

	_undock_btn = Button.new()
	_undock_btn.text = "\u21f2"
	_undock_btn.tooltip_text = "Undock panel"
	_undock_btn.custom_minimum_size = Vector2(28, 28)
	_undock_btn.pressed.connect(func() -> void: undock_requested.emit())
	_title_bar.add_child(_undock_btn)

	_inner_vbox.add_child(HSeparator.new())

	# Toolbar row 1: filter + search
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 4)
	_inner_vbox.add_child(_toolbar)

	_filter_opt = OptionButton.new()
	_filter_opt.custom_minimum_size = Vector2(90, 26)
	_filter_opt.add_theme_font_size_override("font_size", 11)
	for lbl: Variant in _FILTER_LABELS:
		_filter_opt.add_item(str(lbl))
	_filter_opt.selected = 0
	_filter_opt.item_selected.connect(_on_filter_changed)
	_toolbar.add_child(_filter_opt)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search…"
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.custom_minimum_size = Vector2(80, 26)
	_search_edit.add_theme_font_size_override("font_size", 11)
	_search_edit.text_changed.connect(_on_search_changed)
	_toolbar.add_child(_search_edit)

	# Toolbar row 2: action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	_inner_vbox.add_child(btn_row)

	_add_note_btn = Button.new()
	_add_note_btn.text = "Add Note"
	_add_note_btn.custom_minimum_size = Vector2(0, 26)
	_add_note_btn.add_theme_font_size_override("font_size", 11)
	_add_note_btn.pressed.connect(_on_add_note_pressed)
	btn_row.add_child(_add_note_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	_clear_btn = Button.new()
	_clear_btn.text = "Clear"
	_clear_btn.custom_minimum_size = Vector2(0, 26)
	_clear_btn.add_theme_font_size_override("font_size", 11)
	_clear_btn.pressed.connect(_on_clear_pressed)
	btn_row.add_child(_clear_btn)

	_export_btn = Button.new()
	_export_btn.text = "Export"
	_export_btn.custom_minimum_size = Vector2(0, 26)
	_export_btn.add_theme_font_size_override("font_size", 11)
	_export_btn.pressed.connect(_on_export_pressed)
	btn_row.add_child(_export_btn)

	_inner_vbox.add_child(HSeparator.new())

	# Scrollable log entries
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inner_vbox.add_child(_scroll)

	_entry_vbox = VBoxContainer.new()
	_entry_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry_vbox.add_theme_constant_override("separation", 2)
	_scroll.add_child(_entry_vbox)

	# Background style
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


# ---------------------------------------------------------------------------
# Filter and rebuild
# ---------------------------------------------------------------------------

func _rebuild_entries() -> void:
	if _entry_vbox == null:
		return
	for child: Node in _entry_vbox.get_children():
		child.queue_free()
	for entry: Variant in _all_entries:
		if entry is Dictionary and _entry_passes_filter(entry as Dictionary):
			_add_entry_widget(entry as Dictionary)
	_scroll_to_bottom()


func _entry_passes_filter(entry: Dictionary) -> bool:
	var type_str: String = str(entry.get("type", ""))
	# Type filter
	if _current_filter_idx > 0:
		var allowed: Array = _FILTER_TYPES[_current_filter_idx] as Array
		if not allowed.has(type_str):
			return false
	# Text search
	if not _search_text.is_empty():
		var haystack: String = str(entry).to_lower()
		if not haystack.contains(_search_text.to_lower()):
			return false
	return true


func _add_entry_widget(entry: Dictionary) -> void:
	var row: HBoxContainer = _CombatLogEntryScript.new() as HBoxContainer
	if row != null:
		row.call("setup", entry, _current_scale)
	_entry_vbox.add_child(row)


func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	# Deferred so the layout has settled before we read the scroll range.
	# ScrollContainer.scroll_vertical is a plain property in Godot 4;
	# a large value clamps automatically to the real maximum.
	_scroll.set_deferred("scroll_vertical", 9999999)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_filter_changed(idx: int) -> void:
	_current_filter_idx = idx
	_rebuild_entries()


func _on_search_changed(new_text: String) -> void:
	_search_text = new_text
	_rebuild_entries()


func _on_add_note_pressed() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.combat == null:
		return
	# Show a simple one-line input dialog.
	var dlg := AcceptDialog.new()
	dlg.title = "Add Combat Note"
	dlg.dialog_text = ""
	var edit := LineEdit.new()
	edit.placeholder_text = "Enter note…"
	edit.custom_minimum_size = Vector2(300, 0)
	dlg.add_child(edit)
	# Shift the accept dialog content to accommodate the line edit.
	dlg.get_label().visible = false
	dlg.confirmed.connect(func() -> void:
		var txt: String = edit.text.strip_edges()
		if not txt.is_empty():
			reg.combat.add_log_entry({"type": "custom", "text": txt})
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	get_viewport().add_child(dlg)
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg)
	dlg.reset_size()
	dlg.popup_centered()
	edit.grab_focus()


func _on_clear_pressed() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.combat == null:
		return
	reg.combat.clear_combat_log()
	_all_entries.clear()
	_rebuild_entries()


func _on_export_pressed() -> void:
	var lines: PackedStringArray = []
	for entry: Variant in _all_entries:
		if entry is Dictionary:
			var e: Dictionary = entry as Dictionary
			var rnd: int = int(e.get("round", 0))
			var type_str: String = str(e.get("type", ""))
			var raw_desc: String = _plain_format(e)
			lines.append("R%d  [%s]  %s" % [rnd, type_str, raw_desc])
	var text: String = "\n".join(lines)
	var path: String = "user://combat_log_%d.txt" % int(Time.get_unix_time_from_system())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


## Plain-text (no BBCode) version of the entry description for export.
func _plain_format(entry: Dictionary) -> String:
	var type_str: String = str(entry.get("type", ""))
	match type_str:
		"combat_start": return "Combat started"
		"combat_end": return "Combat ended"
		"initiative_rolled":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			return "%s initiative: %d" % [nm, int(entry.get("total", 0))]
		"turn_start":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			return "%s's turn  (Round %d)" % [nm, int(entry.get("round", 0))]
		"damage_dealt":
			var tgt: String = str(entry.get("target_name", entry.get("target_id", "?")))
			return "%s takes %d damage" % [tgt, int(entry.get("actual", entry.get("amount", 0)))]
		"healing_applied":
			var tgt: String = str(entry.get("target_name", entry.get("target_id", "?")))
			return "%s heals %d HP" % [tgt, int(entry.get("amount", 0))]
		"saving_throw":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			var passed: bool = bool(entry.get("passed", false))
			return "%s %s save DC%d = %d  %s" % [nm,
				str(entry.get("ability", "?")).to_upper(),
				int(entry.get("dc", 0)),
				int(entry.get("total", 0)),
				"PASS" if passed else "FAIL"]
		"death_save":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			return "%s death save: %d" % [nm, int(entry.get("roll", 0))]
		"condition_applied":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			return "%s gains %s" % [nm, str(entry.get("condition_name", "?")).capitalize()]
		"condition_removed":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			return "%s lost %s" % [nm, str(entry.get("condition_name", "?")).capitalize()]
		"token_killed":
			return "%s slain" % str(entry.get("token_name", entry.get("token_id", "?")))
		"token_stabilized":
			return "%s stabilized" % str(entry.get("token_name", entry.get("token_id", "?")))
		"custom":
			return str(entry.get("text", ""))
		_:
			return str(entry)
