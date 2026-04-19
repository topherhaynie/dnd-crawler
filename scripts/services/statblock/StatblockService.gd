extends IStatblockService
class_name StatblockService

# ---------------------------------------------------------------------------
# StatblockService — unified statblock management across scopes.
#
# Scopes:
#   "global"   → user://data/statblocks/<id>.json
#   "campaign"  → stored inside active CampaignData.bestiary
#   "map"       → stored in map-local collection (runtime only for now)
# ---------------------------------------------------------------------------

const GLOBAL_DIR: String = "user://data/statblocks/"

## {id: StatblockData} — global custom statblocks
var _global_cache: Dictionary = {}
## {id: StatblockData} — map-local statblocks (transient, lives with save)
var _map_cache: Dictionary = {}
## True once global dir has been scanned
var _global_loaded: bool = false


func _ready() -> void:
	_ensure_global_loaded()


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------

func add_statblock(data: StatblockData, scope: String) -> void:
	if data.id.is_empty():
		data.id = StatblockData.generate_id()

	match scope:
		"global":
			_global_cache[data.id] = data
			_write_global(data)
		"campaign":
			var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			if registry != null and registry.campaign != null:
				registry.campaign.add_to_bestiary(data)
				registry.campaign.save_campaign()
		"map":
			_map_cache[data.id] = data
		_:
			push_warning("StatblockService.add_statblock: unknown scope '%s'" % scope)
			return

	statblock_added.emit(data)


func update_statblock(data: StatblockData) -> void:
	# Determine scope from where it lives
	if _global_cache.has(data.id):
		_global_cache[data.id] = data
		_write_global(data)
	elif _map_cache.has(data.id):
		_map_cache[data.id] = data
	else:
		# Check campaign bestiary
		var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if registry != null and registry.campaign != null:
			var campaign: CampaignData = registry.campaign.get_active_campaign()
			if campaign != null and campaign.bestiary.has(data.id):
				campaign.bestiary[data.id] = data.to_dict()
				registry.campaign.save_campaign()

	statblock_updated.emit(data)


func remove_statblock(id: String) -> void:
	if _global_cache.has(id):
		_global_cache.erase(id)
		_delete_global(id)
	elif _map_cache.has(id):
		_map_cache.erase(id)
	else:
		var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if registry != null and registry.campaign != null:
			registry.campaign.remove_from_bestiary(id)

	statblock_removed.emit(id)


func get_statblock(id: String) -> StatblockData:
	_ensure_global_loaded()

	# Check map-local first
	if _map_cache.has(id):
		var val: Variant = _map_cache[id]
		if val is StatblockData:
			return val as StatblockData

	# Check global
	if _global_cache.has(id):
		var val: Variant = _global_cache[id]
		if val is StatblockData:
			return val as StatblockData

	# Check campaign bestiary
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.campaign != null:
		var campaign: CampaignData = registry.campaign.get_active_campaign()
		if campaign != null and campaign.bestiary.has(id):
			var raw: Variant = campaign.bestiary[id]
			if raw is Dictionary:
				return StatblockData.from_dict(raw as Dictionary)

	# Check SRD (by srd_index)
	if registry != null and registry.srd != null:
		for ruleset: String in ["2014", "2024"]:
			var monster: StatblockData = registry.srd.get_monster(id, ruleset)
			if monster != null:
				return monster

	return null


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

func search_all(query: String, category: String, filters: Dictionary) -> Array:
	_ensure_global_loaded()
	var results: Array = []
	var q: String = query.to_lower()
	var filter_ruleset: String = str(filters.get("ruleset", ""))
	var filter_source: String = str(filters.get("source", ""))

	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry

	# SRD monsters
	if _should_include_category(category, "monsters") and _should_include_source(filter_source, "srd"):
		if registry != null and registry.srd != null:
			var rulesets: Array = _get_rulesets(filter_ruleset)
			for rs: String in rulesets:
				var monsters: Array = registry.srd.get_monsters(rs)
				for entry: Variant in monsters:
					if not entry is StatblockData:
						continue
					var m := entry as StatblockData
					if _matches(q, m):
						results.append(m)

	# Campaign bestiary
	if _should_include_source(filter_source, "campaign"):
		if registry != null and registry.campaign != null:
			var bestiary: Array = registry.campaign.get_bestiary()
			for entry: Variant in bestiary:
				if not entry is StatblockData:
					continue
				var s := entry as StatblockData
				if _should_include_category(category, _infer_category(s)) and _matches(q, s):
					if filter_ruleset.is_empty() or s.ruleset == filter_ruleset:
						results.append(s)

	# Global custom statblocks
	if _should_include_source(filter_source, "global"):
		for key: Variant in _global_cache:
			var val: Variant = _global_cache[key]
			if not val is StatblockData:
				continue
			var s := val as StatblockData
			if _should_include_category(category, _infer_category(s)) and _matches(q, s):
				if filter_ruleset.is_empty() or s.ruleset == filter_ruleset:
					results.append(s)

	# Map-local
	if _should_include_source(filter_source, "map"):
		for key: Variant in _map_cache:
			var val: Variant = _map_cache[key]
			if not val is StatblockData:
				continue
			var s := val as StatblockData
			if _should_include_category(category, _infer_category(s)) and _matches(q, s):
				if filter_ruleset.is_empty() or s.ruleset == filter_ruleset:
					results.append(s)

	return results


func get_all_by_scope(scope: String) -> Array:
	_ensure_global_loaded()
	match scope:
		"global":
			return _global_cache.values()
		"map":
			return _map_cache.values()
		"campaign":
			var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			if registry != null and registry.campaign != null:
				return registry.campaign.get_bestiary()
			return []
	return []


# ---------------------------------------------------------------------------
# Duplication / Creation
# ---------------------------------------------------------------------------

func duplicate_from_srd(srd_index: String, ruleset: String) -> StatblockData:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.srd == null:
		return null
	var base: StatblockData = registry.srd.get_monster(srd_index, ruleset)
	if base == null:
		return null

	# Round-trip through dict to deep-copy
	var copy: StatblockData = StatblockData.from_dict(base.to_dict())
	copy.id = StatblockData.generate_id()
	copy.source = "custom"
	copy.srd_index = srd_index
	return copy


func create_blank() -> StatblockData:
	var s := StatblockData.new()
	s.id = StatblockData.generate_id()
	s.name = "New Creature"
	s.source = "custom"
	s.ruleset = "custom"
	s.hit_points = 10
	s.armor_class = [ {"type": "natural", "value": 10}]
	s.strength = 10
	s.dexterity = 10
	s.constitution = 10
	s.intelligence = 10
	s.wisdom = 10
	s.charisma = 10
	return s


func roll_statblock_hp(statblock: StatblockData) -> int:
	if statblock == null:
		return 0
	return statblock.roll_hit_points()


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
					var s: StatblockData = StatblockData.from_dict(parsed as Dictionary)
					_global_cache[s.id] = s
		entry = dir.get_next()
	dir.list_dir_end()


func _write_global(data: StatblockData) -> void:
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

func _matches(query: String, data: StatblockData) -> bool:
	if query.is_empty():
		return true
	return data.name.to_lower().contains(query) or data.srd_index.to_lower().contains(query) or data.creature_type.to_lower().contains(query)


func _should_include_category(filter: String, actual: String) -> bool:
	if filter.is_empty() or filter == "all":
		return true
	return filter == actual


func _should_include_source(filter: String, actual: String) -> bool:
	if filter.is_empty() or filter == "all":
		return true
	return filter == actual


func _infer_category(data: StatblockData) -> String:
	if not data.creature_type.is_empty():
		return "monsters"
	if not data.class_name_str.is_empty():
		return "characters"
	return "monsters"


func _get_rulesets(filter_ruleset: String) -> Array:
	if filter_ruleset.is_empty():
		return ["2014", "2024"]
	return [filter_ruleset]
