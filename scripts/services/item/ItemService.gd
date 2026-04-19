extends IItemService
class_name ItemService

# ---------------------------------------------------------------------------
# ItemService — unified item/equipment management across scopes.
#
# Scopes:
#   "global"    → user://data/items/<id>.json
#   "campaign"  → stored inside active CampaignData.item_library
#   (SRD items are read-only, loaded from SRDLibraryService)
# ---------------------------------------------------------------------------

const GLOBAL_DIR: String = "user://data/items/"

## {id: ItemEntry} — global custom items
var _global_cache: Dictionary = {}
## {ruleset: Array[ItemEntry]} — SRD equipment cache, parsed lazily
var _srd_cache: Dictionary = {}
## Distinct SRD categories collected during parsing
var _category_set: Dictionary = {}
## True once global dir has been scanned
var _global_loaded: bool = false
## True once SRD items have been parsed
var _srd_parsed: bool = false


func _ready() -> void:
	_ensure_global_loaded()


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------

func add_item(data: ItemEntry, scope: String) -> void:
	if data.id.is_empty():
		data.id = ItemEntry.generate_id()

	match scope:
		"global":
			_global_cache[data.id] = data
			_write_global(data)
		"campaign":
			var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			if registry != null and registry.campaign != null:
				registry.campaign.add_to_item_library(data)
				registry.campaign.save_campaign()
		_:
			push_warning("ItemService.add_item: unknown scope '%s'" % scope)
			return

	item_added.emit(data)


func update_item(data: ItemEntry) -> void:
	if _global_cache.has(data.id):
		_global_cache[data.id] = data
		_write_global(data)
	else:
		var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if registry != null and registry.campaign != null:
			var campaign: CampaignData = registry.campaign.get_active_campaign()
			if campaign != null and campaign.item_library.has(data.id):
				campaign.item_library[data.id] = data.to_dict()
				registry.campaign.save_campaign()

	item_updated.emit(data)


func remove_item(id: String) -> void:
	if _global_cache.has(id):
		_global_cache.erase(id)
		_delete_global(id)
	else:
		var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if registry != null and registry.campaign != null:
			registry.campaign.remove_from_item_library(id)

	item_removed.emit(id)


func get_item(id: String) -> ItemEntry:
	_ensure_global_loaded()

	# Check global
	if _global_cache.has(id):
		var val: Variant = _global_cache[id]
		if val is ItemEntry:
			return val as ItemEntry

	# Check campaign item library
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.campaign != null:
		var campaign: CampaignData = registry.campaign.get_active_campaign()
		if campaign != null and campaign.item_library.has(id):
			var raw: Variant = campaign.item_library[id]
			if raw is Dictionary:
				return ItemEntry.from_dict(raw as Dictionary)

	# Check SRD (by index)
	_ensure_srd_parsed()
	for ruleset: String in ["2014", "2024"]:
		var list: Variant = _srd_cache.get(ruleset, [])
		if list is Array:
			for entry: Variant in list as Array:
				if entry is ItemEntry and (entry as ItemEntry).index == id:
					return entry as ItemEntry

	return null


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

func search_all(query: String, category: String, filters: Dictionary) -> Array:
	_ensure_global_loaded()
	_ensure_srd_parsed()
	var results: Array = []
	var q: String = query.to_lower()
	var filter_ruleset: String = str(filters.get("ruleset", ""))
	var filter_source: String = str(filters.get("source", ""))

	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry

	# SRD items
	if _should_include_source(filter_source, "srd"):
		var rulesets: Array = _get_rulesets(filter_ruleset)
		for rs: String in rulesets:
			var list: Variant = _srd_cache.get(rs, [])
			if not list is Array:
				continue
			for entry: Variant in list as Array:
				if not entry is ItemEntry:
					continue
				var it := entry as ItemEntry
				if _matches_category(category, it) and _matches_query(q, it):
					results.append(it)

	# Campaign item library
	if _should_include_source(filter_source, "campaign"):
		if registry != null and registry.campaign != null:
			var items: Array = registry.campaign.get_item_library()
			for entry: Variant in items:
				if not entry is ItemEntry:
					continue
				var it := entry as ItemEntry
				if _matches_category(category, it) and _matches_query(q, it):
					if filter_ruleset.is_empty() or it.ruleset == filter_ruleset:
						results.append(it)

	# Global custom items
	if _should_include_source(filter_source, "global"):
		for key: Variant in _global_cache:
			var val: Variant = _global_cache[key]
			if not val is ItemEntry:
				continue
			var it := val as ItemEntry
			if _matches_category(category, it) and _matches_query(q, it):
				if filter_ruleset.is_empty() or it.ruleset == filter_ruleset:
					results.append(it)

	return results


func get_all_by_scope(scope: String) -> Array:
	_ensure_global_loaded()
	match scope:
		"global":
			return _global_cache.values()
		"campaign":
			var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			if registry != null and registry.campaign != null:
				return registry.campaign.get_item_library()
			return []
	return []


# ---------------------------------------------------------------------------
# Duplication / Creation
# ---------------------------------------------------------------------------

func duplicate_from_srd(srd_index: String, ruleset: String) -> ItemEntry:
	_ensure_srd_parsed()
	var list: Variant = _srd_cache.get(ruleset, [])
	if not list is Array:
		return null
	for entry: Variant in list as Array:
		if not entry is ItemEntry:
			continue
		var it := entry as ItemEntry
		if it.index == srd_index:
			var copy: ItemEntry = ItemEntry.from_dict(it.to_dict())
			copy.id = ItemEntry.generate_id()
			copy.source = "custom"
			copy.ruleset = "custom"
			return copy
	return null


func create_blank() -> ItemEntry:
	var it := ItemEntry.new()
	it.id = ItemEntry.generate_id()
	it.name = "New Item"
	it.source = "custom"
	it.ruleset = "custom"
	it.category = "Adventuring Gear"
	return it


func get_categories() -> PackedStringArray:
	_ensure_srd_parsed()
	var cats: PackedStringArray = PackedStringArray()
	for key: Variant in _category_set:
		cats.append(str(key))
	cats.sort()
	return cats


# ---------------------------------------------------------------------------
# Internal — SRD parsing
# ---------------------------------------------------------------------------

func _ensure_srd_parsed() -> void:
	if _srd_parsed:
		return
	_srd_parsed = true
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.srd == null:
		return
	for rs: String in ["2014", "2024"]:
		var raw_list: Array = registry.srd.get_equipment(rs)
		var parsed: Array = []
		for raw: Variant in raw_list:
			if not raw is Dictionary:
				continue
			var it: ItemEntry = ItemEntry.from_srd(raw as Dictionary, rs)
			parsed.append(it)
			if not it.category.is_empty():
				_category_set[it.category] = true
		_srd_cache[rs] = parsed


# ---------------------------------------------------------------------------
# Internal — Global persistence
# ---------------------------------------------------------------------------

func _ensure_global_loaded() -> void:
	if _global_loaded:
		return
	_global_loaded = true
	DirAccess.make_dir_recursive_absolute(GLOBAL_DIR)
	var dir := DirAccess.open(GLOBAL_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.ends_with(".json"):
			var path: String = GLOBAL_DIR + entry
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				file.close()
				if parsed is Dictionary:
					var it: ItemEntry = ItemEntry.from_dict(parsed as Dictionary)
					_global_cache[it.id] = it
		entry = dir.get_next()
	dir.list_dir_end()


func _write_global(data: ItemEntry) -> void:
	DirAccess.make_dir_recursive_absolute(GLOBAL_DIR)
	var path: String = GLOBAL_DIR + data.id + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data.to_dict(), "\t"))
		file.close()


func _delete_global(id: String) -> void:
	var path: String = GLOBAL_DIR + id + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Internal — Search helpers
# ---------------------------------------------------------------------------

func _matches_query(query: String, data: ItemEntry) -> bool:
	if query.is_empty():
		return true
	return data.name.to_lower().contains(query) or data.index.to_lower().contains(query) or data.category.to_lower().contains(query)


func _matches_category(filter: String, data: ItemEntry) -> bool:
	if filter.is_empty() or filter == "all":
		return true
	return data.category.to_lower() == filter.to_lower()


func _should_include_source(filter: String, actual: String) -> bool:
	if filter.is_empty() or filter == "all":
		return true
	return filter == actual


func _get_rulesets(filter_ruleset: String) -> Array:
	if filter_ruleset.is_empty():
		return ["2014", "2024"]
	return [filter_ruleset]
