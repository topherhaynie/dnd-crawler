extends Window
class_name StatblockLibrary

# ---------------------------------------------------------------------------
# StatblockLibrary — browsable library window for SRD / campaign / custom
# statblocks.  Non-modal, stays open alongside the map.
# ---------------------------------------------------------------------------

const SEARCH_DEBOUNCE_MS: int = 300
const StatblockEditorScript = preload("res://scripts/ui/StatblockEditor.gd")

## Emitted when DM picks a statblock in attach mode.
signal statblock_picked(data: StatblockData)

var _registry: ServiceRegistry = null
var _search_edit: LineEdit = null
var _category_btn: OptionButton = null
var _source_btn: OptionButton = null
var _results_list: ItemList = null
var _card_view: StatblockCardView = null
var _count_label: Label = null
var _bestiary_btn: Button = null
var _attach_btn: Button = null
var _roll_hp_btn: Button = null
var _edit_copy_btn: Button = null
var _delete_btn: Button = null
var _new_btn: Button = null
var _export_btn: Button = null
var _import_btn: Button = null
var _export_dialog: FileDialog = null
var _import_dialog: FileDialog = null
var _statblock_editor: Window = null
var _search_timer: Timer = null
var _attach_mode: bool = false

## Cached search results for current query
var _results: Array = []


func _ready() -> void:
	title = "Statblock Library"
	_registry = get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var s := func(base: float) -> int:
		return mgr.scaled(base) if mgr != null else roundi(base)
	size = Vector2i(s.call(900.0), s.call(650.0))
	min_size = Vector2i(s.call(600.0), s.call(400.0))
	wrap_controls = false
	transient = false
	exclusive = false

	# Debounce timer
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DEBOUNCE_MS / 1000.0
	_search_timer.timeout.connect(_execute_search)
	add_child(_search_timer)

	_build_ui()
	close_requested.connect(func() -> void: hide())

	# Initial load
	_execute_search()


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var s := func(base: float) -> int:
		return mgr.scaled(base) if mgr != null else roundi(base)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", s.call(10.0))
	margin.add_theme_constant_override("margin_right", s.call(10.0))
	margin.add_theme_constant_override("margin_top", s.call(10.0))
	margin.add_theme_constant_override("margin_bottom", s.call(10.0))
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", s.call(8.0))
	margin.add_child(vbox)

	# ── Toolbar row ─────────────────────────────────────────────────────────
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", s.call(6.0))

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search monsters, spells, items…"
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.clear_button_enabled = true
	_search_edit.add_theme_font_size_override("font_size", s.call(14.0))
	_search_edit.custom_minimum_size = Vector2(s.call(200.0), 0)
	_search_edit.text_changed.connect(_on_search_text_changed)
	toolbar.add_child(_search_edit)

	_category_btn = OptionButton.new()
	_category_btn.add_item("All", 0)
	_category_btn.add_item("Monsters", 1)
	# Future: Spells(2), Equipment(3), etc.
	_category_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_category_btn.item_selected.connect(_on_filter_changed)
	toolbar.add_child(_category_btn)

	_source_btn = OptionButton.new()
	_source_btn.add_item("All Sources", 0)
	_source_btn.add_item("SRD 2014", 1)
	_source_btn.add_item("SRD 2024", 2)
	_source_btn.add_item("Campaign", 3)
	_source_btn.add_item("Global", 4)
	_source_btn.add_item("Map", 5)
	_source_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_source_btn.item_selected.connect(_on_filter_changed)
	## Default to the campaign's ruleset when available.
	if _registry != null and _registry.campaign != null:
		var camp: CampaignData = _registry.campaign.get_active_campaign()
		if camp != null and camp.default_ruleset == "2024":
			_source_btn.selected = 2
		else:
			_source_btn.selected = 1
	toolbar.add_child(_source_btn)

	_new_btn = Button.new()
	_new_btn.text = "+ New Statblock"
	_new_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_new_btn.pressed.connect(_on_new_statblock)
	toolbar.add_child(_new_btn)

	vbox.add_child(toolbar)

	# ── Split: results list | preview card ──────────────────────────────────
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = s.call(300.0)

	# Left: results list
	_results_list = ItemList.new()
	_results_list.custom_minimum_size = Vector2(s.call(250.0), 0)
	_results_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results_list.add_theme_font_size_override("font_size", s.call(14.0))
	_results_list.item_selected.connect(_on_result_selected)
	_results_list.allow_reselect = true
	split.add_child(_results_list)

	# Right: preview card in a scroll container
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.custom_minimum_size = Vector2(s.call(350.0), 0)

	_card_view = StatblockCardView.new()
	_card_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(_card_view)
	split.add_child(right_scroll)

	vbox.add_child(split)

	# ── Bottom bar ──────────────────────────────────────────────────────────
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", s.call(8.0))

	_count_label = Label.new()
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.text = "0 results"
	_count_label.add_theme_font_size_override("font_size", s.call(13.0))
	bottom.add_child(_count_label)

	_bestiary_btn = Button.new()
	_bestiary_btn.text = "Add to Bestiary"
	_bestiary_btn.disabled = true
	_bestiary_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_bestiary_btn.pressed.connect(_on_add_to_bestiary)
	bottom.add_child(_bestiary_btn)

	_attach_btn = Button.new()
	_attach_btn.text = "Attach to Token"
	_attach_btn.disabled = true
	_attach_btn.visible = false
	_attach_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_attach_btn.pressed.connect(_on_attach_to_token)
	bottom.add_child(_attach_btn)

	_roll_hp_btn = Button.new()
	_roll_hp_btn.text = "Roll HP"
	_roll_hp_btn.disabled = true
	_roll_hp_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_roll_hp_btn.pressed.connect(_on_roll_hp)
	bottom.add_child(_roll_hp_btn)

	_edit_copy_btn = Button.new()
	_edit_copy_btn.text = "Edit Copy"
	_edit_copy_btn.disabled = true
	_edit_copy_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_edit_copy_btn.pressed.connect(_on_edit_copy)
	bottom.add_child(_edit_copy_btn)

	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.disabled = true
	_delete_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_delete_btn.pressed.connect(_on_delete_statblock)
	bottom.add_child(_delete_btn)

	_export_btn = Button.new()
	_export_btn.text = "Export…"
	_export_btn.disabled = true
	_export_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_export_btn.pressed.connect(_on_export_statblock)
	bottom.add_child(_export_btn)

	_import_btn = Button.new()
	_import_btn.text = "Import…"
	_import_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_import_btn.pressed.connect(_on_import_statblock)
	bottom.add_child(_import_btn)

	vbox.add_child(bottom)

	# ── File dialogs ────────────────────────────────────────────────────────
	_export_dialog = FileDialog.new()
	_export_dialog.use_native_dialog = true
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.title = "Export Statblock as JSON"
	_export_dialog.add_filter("*.json ; JSON")
	_export_dialog.file_selected.connect(_on_export_path_selected)
	add_child(_export_dialog)

	_import_dialog = FileDialog.new()
	_import_dialog.use_native_dialog = true
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.title = "Import Statblocks from JSON"
	_import_dialog.add_filter("*.json ; JSON")
	_import_dialog.file_selected.connect(_on_import_path_selected)
	add_child(_import_dialog)


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

func _on_search_text_changed(_new_text: String) -> void:
	_search_timer.start()


func _on_filter_changed(_index: int) -> void:
	_execute_search()


func _execute_search() -> void:
	if _registry == null or _registry.statblock == null:
		return

	var query: String = _search_edit.text.strip_edges()
	var category: String = _get_category_filter()
	var filters: Dictionary = _get_source_filter()

	_results = _registry.statblock.search_all(query, category, filters)

	# Sort by name
	_results.sort_custom(func(a: Variant, b: Variant) -> bool:
		var a_name: String = ""
		var b_name: String = ""
		if a is StatblockData:
			a_name = (a as StatblockData).name
		if b is StatblockData:
			b_name = (b as StatblockData).name
		return a_name.naturalnocasecmp_to(b_name) < 0
	)

	_populate_results()


func _populate_results() -> void:
	_results_list.clear()
	for entry: Variant in _results:
		if not entry is StatblockData:
			continue
		var s := entry as StatblockData
		var label: String = s.name
		var cr_str: String = _format_cr(s.challenge_rating)
		if not cr_str.is_empty():
			label += "  (CR %s)" % cr_str
		if not s.creature_type.is_empty():
			label += "  — %s" % s.creature_type
		# Source badge
		var badge: String = ""
		if s.source.begins_with("SRD"):
			badge = s.ruleset
		elif s.source == "custom":
			badge = "Custom"
		elif s.source == "campaign":
			badge = "Campaign"
		if not badge.is_empty():
			label += "  [%s]" % badge
		_results_list.add_item(label)

	_count_label.text = "%d results" % _results.size()
	_update_button_states()


func _on_result_selected(index: int) -> void:
	if index < 0 or index >= _results.size():
		return
	var entry: Variant = _results[index]
	if entry is StatblockData:
		_card_view.display(entry as StatblockData)
		var mgr: UIScaleManager = _get_ui_scale_mgr()
		if mgr != null:
			_card_view.apply_font_scale(mgr.scaled(14.0))
	_update_button_states()


func _update_button_states() -> void:
	var selected: PackedInt32Array = _results_list.get_selected_items()
	var has_selection: bool = selected.size() > 0
	_bestiary_btn.disabled = not has_selection
	_roll_hp_btn.disabled = not has_selection
	_edit_copy_btn.disabled = not has_selection
	if _attach_btn != null:
		_attach_btn.disabled = not has_selection
	if _export_btn != null:
		_export_btn.disabled = not has_selection
	# Delete is only enabled for non-SRD statblocks
	if _delete_btn != null:
		var can_delete: bool = false
		if has_selection:
			var sel_sb: StatblockData = _get_selected_statblock()
			if sel_sb != null and not sel_sb.source.begins_with("SRD"):
				can_delete = true
		_delete_btn.disabled = not can_delete


# ---------------------------------------------------------------------------
# Bottom bar actions
# ---------------------------------------------------------------------------

func _on_add_to_bestiary() -> void:
	var s: StatblockData = _get_selected_statblock()
	if s == null or _registry == null or _registry.campaign == null:
		return
	if _registry.campaign.get_active_campaign() == null:
		_count_label.text = "No active campaign — create one first"
		return
	## Let the service decide how to store it (SRD ref vs full custom copy).
	_registry.campaign.add_to_bestiary(s)
	_registry.campaign.save_campaign()
	_count_label.text = "Added \"%s\" to bestiary" % s.name


func _on_roll_hp() -> void:
	var s: StatblockData = _get_selected_statblock()
	if s == null or _registry == null or _registry.statblock == null:
		return
	var rolled: int = _registry.statblock.roll_statblock_hp(s)
	_count_label.text = "Rolled HP for %s: %d  (base: %d, dice: %s)" % [s.name, rolled, s.hit_points, s.hit_points_roll]


func _on_edit_copy() -> void:
	var s: StatblockData = _get_selected_statblock()
	if s == null or _registry == null or _registry.statblock == null:
		return
	var copy: StatblockData
	if not s.srd_index.is_empty():
		copy = _registry.statblock.duplicate_from_srd(s.srd_index, s.ruleset)
	else:
		copy = StatblockData.from_dict(s.to_dict())
		copy.id = StatblockData.generate_id()
		copy.source = "custom"
	if copy != null:
		_open_editor(copy)


func _on_new_statblock() -> void:
	if _registry == null or _registry.statblock == null:
		return
	var blank: StatblockData = _registry.statblock.create_blank()
	if blank != null:
		_open_editor(blank)


func _on_delete_statblock() -> void:
	var s: StatblockData = _get_selected_statblock()
	if s == null or _registry == null or _registry.statblock == null:
		return
	if s.source.begins_with("SRD"):
		_count_label.text = "Cannot delete SRD statblocks"
		return
	var name_str: String = s.name
	_registry.statblock.remove_statblock(s.id)
	_count_label.text = "Deleted \"%s\"" % name_str
	_execute_search()


func _on_attach_to_token() -> void:
	var s: StatblockData = _get_selected_statblock()
	if s == null:
		return
	statblock_picked.emit(s)
	_count_label.text = "Attached \"%s\" to token" % s.name


# ---------------------------------------------------------------------------
# Export / Import
# ---------------------------------------------------------------------------

func _on_export_statblock() -> void:
	var sb: StatblockData = _get_selected_statblock()
	if sb == null or _export_dialog == null:
		return
	# Suggest a filename based on the statblock name
	var suggested: String = sb.name.to_lower().replace(" ", "_") + ".json"
	_export_dialog.current_file = suggested
	_export_dialog.popup_centered(Vector2i(900, 600))


func _on_import_statblock() -> void:
	if _import_dialog == null:
		return
	_import_dialog.popup_centered(Vector2i(900, 600))


func _on_export_path_selected(path: String) -> void:
	var sb: StatblockData = _get_selected_statblock()
	if sb == null:
		_count_label.text = "Export failed: no statblock selected."
		return
	var target_path := path
	if not target_path.to_lower().ends_with(".json"):
		target_path += ".json"
	var parent_dir := target_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_dir):
		var mk_err := DirAccess.make_dir_recursive_absolute(parent_dir)
		if mk_err != OK:
			_count_label.text = "Export failed: could not create directory."
			return
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		_count_label.text = "Export failed: could not write file."
		return
	file.store_string(JSON.stringify(sb.to_dict(), "\t"))
	file.close()
	_count_label.text = "Exported \"%s\"." % sb.name


func _on_import_path_selected(path: String) -> void:
	if not FileAccess.file_exists(path):
		_count_label.text = "Import failed: file not found."
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_count_label.text = "Import failed: could not read file."
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_count_label.text = "Import failed: invalid JSON."
		return
	var count: int = 0
	if parsed is Dictionary:
		# Single statblock
		var sb := StatblockData.from_dict(parsed as Dictionary)
		if sb.id.is_empty():
			sb.id = StatblockData.generate_id()
		sb.source = "custom"
		if _registry != null and _registry.statblock != null:
			_registry.statblock.add_statblock(sb, "global")
			count = 1
	elif parsed is Array:
		# Array of statblocks
		for item: Variant in parsed:
			if not item is Dictionary:
				continue
			var sb := StatblockData.from_dict(item as Dictionary)
			if sb.id.is_empty():
				sb.id = StatblockData.generate_id()
			sb.source = "custom"
			if _registry != null and _registry.statblock != null:
				_registry.statblock.add_statblock(sb, "global")
				count += 1
	else:
		_count_label.text = "Import failed: JSON must be a statblock object or array."
		return
	if count == 0:
		_count_label.text = "Import skipped: no valid statblocks found."
		return
	_count_label.text = "Imported %d statblock(s)." % count
	_execute_search()


## Enable or disable attach mode. When enabled, "Attach to Token" is shown.
func set_attach_mode(enabled: bool) -> void:
	_attach_mode = enabled
	if _attach_btn != null:
		_attach_btn.visible = enabled
	if enabled:
		title = "Statblock Library — Attach to Token"
	else:
		title = "Statblock Library"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_selected_statblock() -> StatblockData:
	var selected: PackedInt32Array = _results_list.get_selected_items()
	if selected.size() == 0:
		return null
	var idx: int = selected[0]
	if idx < 0 or idx >= _results.size():
		return null
	var entry: Variant = _results[idx]
	if entry is StatblockData:
		return entry as StatblockData
	return null


func _get_category_filter() -> String:
	if _category_btn == null:
		return ""
	match _category_btn.selected:
		1: return "monsters"
	return ""


func _get_source_filter() -> Dictionary:
	if _source_btn == null:
		return {}
	match _source_btn.selected:
		1: return {"source": "srd", "ruleset": "2014"}
		2: return {"source": "srd", "ruleset": "2024"}
		3: return {"source": "campaign"}
		4: return {"source": "global"}
		5: return {"source": "map"}
	return {}


func _format_cr(cr: float) -> String:
	if cr == 0.125:
		return "1/8"
	elif cr == 0.25:
		return "1/4"
	elif cr == 0.5:
		return "1/2"
	elif cr == int(cr):
		return str(int(cr))
	return str(cr)


func _get_ui_scale_mgr() -> UIScaleManager:
	if _registry != null and _registry.ui_scale != null:
		return _registry.ui_scale
	return null


func _open_editor(data: StatblockData) -> void:
	if _statblock_editor == null:
		_statblock_editor = StatblockEditorScript.new()
		_statblock_editor.statblock_saved.connect(_on_editor_saved)
		add_child(_statblock_editor)
	_statblock_editor.edit(data)


func _on_editor_saved(data: StatblockData) -> void:
	if _registry == null or _registry.statblock == null:
		return
	data.source = "custom"
	# Update if it already exists, otherwise add
	var existing: StatblockData = _registry.statblock.get_statblock(data.id)
	if existing != null and not existing.source.begins_with("SRD"):
		_registry.statblock.update_statblock(data)
		_count_label.text = "Saved \"%s\"" % data.name
	else:
		_registry.statblock.add_statblock(data, "global")
		_count_label.text = "Created \"%s\"" % data.name
	_execute_search()
