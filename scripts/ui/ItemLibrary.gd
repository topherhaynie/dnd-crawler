extends Window
class_name ItemLibrary

# ---------------------------------------------------------------------------
# ItemLibrary — browsable library window for SRD / campaign / custom items.
# Non-modal, stays open alongside the map.
# ---------------------------------------------------------------------------

const SEARCH_DEBOUNCE_MS: int = 300
const ItemEditorScript = preload("res://scripts/ui/ItemEditor.gd")

## Emitted when DM picks an item in pick mode (e.g. for inventory).
signal item_picked(data: ItemEntry)

var _registry: ServiceRegistry = null
var _search_edit: LineEdit = null
var _category_btn: OptionButton = null
var _source_btn: OptionButton = null
var _results_list: ItemList = null
var _card_view: ItemCardView = null
var _count_label: Label = null
var _campaign_btn: Button = null
var _pick_btn: Button = null
var _edit_copy_btn: Button = null
var _delete_btn: Button = null
var _new_btn: Button = null
var _export_btn: Button = null
var _import_btn: Button = null
var _export_dialog: FileDialog = null
var _import_dialog: FileDialog = null
var _item_editor: Window = null
var _search_timer: Timer = null
var _pick_mode: bool = false

## Cached search results for current query
var _results: Array = []


func _ready() -> void:
	title = "Item Library"
	_registry = get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var s := func(base: float) -> int:
		return mgr.scaled(base) if mgr != null else roundi(base)
	size = Vector2i(s.call(900.0), s.call(650.0))
	min_size = Vector2i(s.call(600.0), s.call(400.0))
	wrap_controls = false
	transient = false
	exclusive = false

	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DEBOUNCE_MS / 1000.0
	_search_timer.timeout.connect(_execute_search)
	add_child(_search_timer)

	_build_ui()
	close_requested.connect(func() -> void: hide())

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
	_search_edit.placeholder_text = "Search items…"
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.clear_button_enabled = true
	_search_edit.add_theme_font_size_override("font_size", s.call(14.0))
	_search_edit.custom_minimum_size = Vector2(s.call(200.0), 0)
	_search_edit.text_changed.connect(_on_search_text_changed)
	toolbar.add_child(_search_edit)

	_category_btn = OptionButton.new()
	_category_btn.add_item("All Categories", 0)
	_category_btn.add_item("Weapon", 1)
	_category_btn.add_item("Armor", 2)
	_category_btn.add_item("Adventuring Gear", 3)
	_category_btn.add_item("Tool", 4)
	# Append SRD-derived categories not already listed
	if _registry != null and _registry.item != null:
		var srd_cats: PackedStringArray = _registry.item.get_categories()
		for cat: String in srd_cats:
			var found: bool = false
			for i: int in range(_category_btn.item_count):
				if _category_btn.get_item_text(i) == cat:
					found = true
					break
			if not found:
				_category_btn.add_item(cat, _category_btn.item_count)
	_category_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_category_btn.item_selected.connect(_on_filter_changed)
	toolbar.add_child(_category_btn)

	_source_btn = OptionButton.new()
	_source_btn.add_item("All Sources", 0)
	_source_btn.add_item("SRD 2014", 1)
	_source_btn.add_item("SRD 2024", 2)
	_source_btn.add_item("Campaign", 3)
	_source_btn.add_item("Global", 4)
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
	_new_btn.text = "+ New Item"
	_new_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_new_btn.pressed.connect(_on_new_item)
	toolbar.add_child(_new_btn)

	vbox.add_child(toolbar)

	# ── Split: results list | preview card ──────────────────────────────────
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = s.call(300.0)

	_results_list = ItemList.new()
	_results_list.custom_minimum_size = Vector2(s.call(250.0), 0)
	_results_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results_list.add_theme_font_size_override("font_size", s.call(14.0))
	_results_list.item_selected.connect(_on_result_selected)
	_results_list.allow_reselect = true
	split.add_child(_results_list)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.custom_minimum_size = Vector2(s.call(350.0), 0)

	_card_view = ItemCardView.new()
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

	_campaign_btn = Button.new()
	_campaign_btn.text = "Add to Campaign"
	_campaign_btn.disabled = true
	_campaign_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_campaign_btn.pressed.connect(_on_add_to_campaign)
	bottom.add_child(_campaign_btn)

	_pick_btn = Button.new()
	_pick_btn.text = "Add to Inventory"
	_pick_btn.disabled = true
	_pick_btn.visible = _pick_mode
	_pick_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_pick_btn.pressed.connect(_on_pick_item)
	bottom.add_child(_pick_btn)

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
	_delete_btn.pressed.connect(_on_delete_item)
	bottom.add_child(_delete_btn)

	_export_btn = Button.new()
	_export_btn.text = "Export…"
	_export_btn.disabled = true
	_export_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_export_btn.pressed.connect(_on_export_item)
	bottom.add_child(_export_btn)

	_import_btn = Button.new()
	_import_btn.text = "Import…"
	_import_btn.add_theme_font_size_override("font_size", s.call(13.0))
	_import_btn.pressed.connect(_on_import_item)
	bottom.add_child(_import_btn)

	vbox.add_child(bottom)

	# ── File dialogs ────────────────────────────────────────────────────────
	_export_dialog = FileDialog.new()
	_export_dialog.use_native_dialog = true
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.title = "Export Item as JSON"
	_export_dialog.add_filter("*.json ; JSON")
	_export_dialog.file_selected.connect(_on_export_path_selected)
	add_child(_export_dialog)

	_import_dialog = FileDialog.new()
	_import_dialog.use_native_dialog = true
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.title = "Import Items from JSON"
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
	if _registry == null or _registry.item == null:
		return

	var query: String = _search_edit.text.strip_edges()
	var category: String = _get_category_filter()
	var filters: Dictionary = _get_source_filter()

	_results = _registry.item.search_all(query, category, filters)

	_results.sort_custom(func(a: Variant, b: Variant) -> bool:
		var a_name: String = ""
		var b_name: String = ""
		if a is ItemEntry:
			a_name = (a as ItemEntry).name
		if b is ItemEntry:
			b_name = (b as ItemEntry).name
		return a_name.naturalnocasecmp_to(b_name) < 0
	)

	_populate_results()


func _populate_results() -> void:
	_results_list.clear()
	for entry: Variant in _results:
		if not entry is ItemEntry:
			continue
		var it := entry as ItemEntry
		var label: String = it.name
		if not it.category.is_empty():
			label += "  — %s" % it.category
		# Source badge
		var badge: String = ""
		if it.source.begins_with("srd_"):
			badge = it.ruleset
		elif it.source == "custom":
			badge = "Custom"
		elif it.source == "campaign":
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
	if entry is ItemEntry:
		_card_view.display(entry as ItemEntry)
		var mgr: UIScaleManager = _get_ui_scale_mgr()
		if mgr != null:
			_card_view.apply_font_scale(mgr.scaled(14.0))
	_update_button_states()


func _update_button_states() -> void:
	var selected: PackedInt32Array = _results_list.get_selected_items()
	var has_selection: bool = selected.size() > 0
	_campaign_btn.disabled = not has_selection
	_edit_copy_btn.disabled = not has_selection
	if _pick_btn != null:
		_pick_btn.disabled = not has_selection
	if _export_btn != null:
		_export_btn.disabled = not has_selection
	if _delete_btn != null:
		var can_delete: bool = false
		if has_selection:
			var sel_item: ItemEntry = _get_selected_item()
			if sel_item != null and not sel_item.source.begins_with("srd_"):
				can_delete = true
		_delete_btn.disabled = not can_delete


# ---------------------------------------------------------------------------
# Bottom bar actions
# ---------------------------------------------------------------------------

func _on_add_to_campaign() -> void:
	var it: ItemEntry = _get_selected_item()
	if it == null or _registry == null or _registry.campaign == null:
		return
	if _registry.campaign.get_active_campaign() == null:
		_count_label.text = "No active campaign — create one first"
		return
	_registry.campaign.add_to_item_library(it)
	_registry.campaign.save_campaign()
	_count_label.text = "Added \"%s\" to campaign item library" % it.name
	_execute_search()


func _on_pick_item() -> void:
	var it: ItemEntry = _get_selected_item()
	if it == null:
		return
	item_picked.emit(it)
	_count_label.text = "Added \"%s\" to inventory" % it.name


func _on_edit_copy() -> void:
	var it: ItemEntry = _get_selected_item()
	if it == null or _registry == null or _registry.item == null:
		return
	var copy: ItemEntry
	if it.source.begins_with("srd_"):
		copy = _registry.item.duplicate_from_srd(it.index, it.ruleset)
	else:
		copy = ItemEntry.from_dict(it.to_dict())
		copy.id = ItemEntry.generate_id()
		copy.source = "custom"
	if copy != null:
		_open_editor(copy)


func _on_new_item() -> void:
	if _registry == null or _registry.item == null:
		return
	var blank: ItemEntry = _registry.item.create_blank()
	if blank != null:
		_open_editor(blank)


func _on_delete_item() -> void:
	var it: ItemEntry = _get_selected_item()
	if it == null or _registry == null or _registry.item == null:
		return
	if it.source.begins_with("srd_"):
		_count_label.text = "Cannot delete SRD items"
		return
	var name_str: String = it.name
	_registry.item.remove_item(it.id)
	_count_label.text = "Deleted \"%s\"" % name_str
	_execute_search()


# ---------------------------------------------------------------------------
# Export / Import
# ---------------------------------------------------------------------------

func _on_export_item() -> void:
	var it: ItemEntry = _get_selected_item()
	if it == null or _export_dialog == null:
		return
	var suggested: String = it.name.to_lower().replace(" ", "_") + ".json"
	_export_dialog.current_file = suggested
	_export_dialog.popup_centered(Vector2i(900, 600))


func _on_import_item() -> void:
	if _import_dialog == null:
		return
	_import_dialog.popup_centered(Vector2i(900, 600))


func _on_export_path_selected(path: String) -> void:
	var it: ItemEntry = _get_selected_item()
	if it == null:
		_count_label.text = "Export failed: no item selected."
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
	file.store_string(JSON.stringify(it.to_dict(), "\t"))
	file.close()
	_count_label.text = "Exported \"%s\"." % it.name


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
		var it := ItemEntry.from_dict(parsed as Dictionary)
		if it.id.is_empty():
			it.id = ItemEntry.generate_id()
		it.source = "custom"
		if _registry != null and _registry.item != null:
			_registry.item.add_item(it, "global")
			count = 1
	elif parsed is Array:
		for raw: Variant in parsed:
			if not raw is Dictionary:
				continue
			var it := ItemEntry.from_dict(raw as Dictionary)
			if it.id.is_empty():
				it.id = ItemEntry.generate_id()
			it.source = "custom"
			if _registry != null and _registry.item != null:
				_registry.item.add_item(it, "global")
				count += 1
	else:
		_count_label.text = "Import failed: JSON must be an item object or array."
		return
	if count == 0:
		_count_label.text = "Import skipped: no valid items found."
		return
	_count_label.text = "Imported %d item(s)." % count
	_execute_search()


## Enable or disable pick mode.  When enabled, "Add to Inventory" is shown.
func set_pick_mode(enabled: bool) -> void:
	_pick_mode = enabled
	if _pick_btn != null:
		_pick_btn.visible = enabled
	if enabled:
		title = "Item Library — Add to Inventory"
	else:
		title = "Item Library"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_selected_item() -> ItemEntry:
	var selected: PackedInt32Array = _results_list.get_selected_items()
	if selected.size() == 0:
		return null
	var idx: int = selected[0]
	if idx < 0 or idx >= _results.size():
		return null
	var entry: Variant = _results[idx]
	if entry is ItemEntry:
		return entry as ItemEntry
	return null


func _get_category_filter() -> String:
	if _category_btn == null:
		return ""
	if _category_btn.selected == 0:
		return ""
	return _category_btn.get_item_text(_category_btn.selected)


func _get_source_filter() -> Dictionary:
	if _source_btn == null:
		return {}
	match _source_btn.selected:
		1: return {"source": "srd", "ruleset": "2014"}
		2: return {"source": "srd", "ruleset": "2024"}
		3: return {"source": "campaign"}
		4: return {"source": "global"}
	return {}


func _get_ui_scale_mgr() -> UIScaleManager:
	if _registry != null and _registry.ui_scale != null:
		return _registry.ui_scale
	return null


func _open_editor(data: ItemEntry) -> void:
	if _item_editor == null:
		_item_editor = ItemEditorScript.new()
		_item_editor.item_saved.connect(_on_editor_saved)
		add_child(_item_editor)
	_item_editor.edit(data)


func _on_editor_saved(data: ItemEntry) -> void:
	if _registry == null or _registry.item == null:
		return
	data.source = "custom"
	var existing: ItemEntry = _registry.item.get_item(data.id)
	if existing != null and not existing.source.begins_with("srd_"):
		_registry.item.update_item(data)
		_count_label.text = "Saved \"%s\"" % data.name
	else:
		_registry.item.add_item(data, "global")
		_count_label.text = "Created \"%s\"" % data.name
	_execute_search()
