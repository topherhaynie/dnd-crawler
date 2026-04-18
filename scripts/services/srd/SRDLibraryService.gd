extends ISRDLibraryService
class_name SRDLibraryService

# ---------------------------------------------------------------------------
# SRDLibraryService — loads and indexes bundled SRD JSON files.
#
# Lazily parses each category on first access. Both 2014 and 2024 rulesets
# are loaded into separate caches and are queryable simultaneously.
# ---------------------------------------------------------------------------

const SRD_BASE_PATH: String = "res://assets/srd/"
const IMAGE_CACHE_DIR: String = "user://data/srd_cache/images/monsters/"
const API_IMAGE_BASE: String = "https://www.dnd5eapi.co"

## {ruleset: {index: StatblockData}}
var _monsters: Dictionary = {}
## {ruleset: {index: SpellData}}
var _spells: Dictionary = {}
## {ruleset: Array[Dictionary]} — raw equipment dicts
var _equipment: Dictionary = {}
## {ruleset: Array[Dictionary]} — raw condition dicts
var _conditions: Dictionary = {}
## {ruleset: Array[Dictionary]} — raw class dicts
var _classes: Dictionary = {}
## {ruleset: Array[Dictionary]} — raw race dicts
var _races: Dictionary = {}
## {ruleset: Array[Dictionary]} — raw feat dicts with mechanical metadata
var _feats: Dictionary = {}

## {index: String} — monster index → image URL path from SRD
var _monster_image_urls: Dictionary = {}

var _version: String = ""
var _loaded: bool = false


func load_library() -> void:
	if _loaded:
		return

	for ruleset: String in ["2014", "2024"]:
		_monsters[ruleset] = {}
		_spells[ruleset] = {}
		_equipment[ruleset] = []
		_conditions[ruleset] = []
		_classes[ruleset] = []
		_races[ruleset] = []
		_feats[ruleset] = []

		var base: String = SRD_BASE_PATH + ruleset + "/"
		_load_monsters(base, ruleset)
		_load_spells(base, ruleset)
		_load_raw_category(base, "5e-SRD-Equipment.json", _equipment, ruleset)
		_load_raw_category(base, "5e-SRD-Conditions.json", _conditions, ruleset)
		_load_raw_category(base, "5e-SRD-Classes.json", _classes, ruleset)
		_load_raw_category(base, "5e-SRD-Feats.json", _feats, ruleset)

		# 2024 uses Species.json instead of Races.json
		if ruleset == "2024":
			_load_raw_category(base, "5e-SRD-Species.json", _races, ruleset)
		else:
			_load_raw_category(base, "5e-SRD-Races.json", _races, ruleset)

	# Load version info
	var ver_path: String = SRD_BASE_PATH + "srd_version.json"
	if FileAccess.file_exists(ver_path):
		var ver_file := FileAccess.open(ver_path, FileAccess.READ)
		if ver_file != null:
			var ver_json: Variant = JSON.parse_string(ver_file.get_as_text())
			ver_file.close()
			if ver_json is Dictionary:
				_version = str((ver_json as Dictionary).get("version", ""))

	_loaded = true
	library_loaded.emit()
	Log.info("SRDLibraryService", "library loaded — %d monsters (2014), %d monsters (2024), %d spells (2014), %d spells (2024)" % [
		(_monsters.get("2014", {}) as Dictionary).size(),
		(_monsters.get("2024", {}) as Dictionary).size(),
		(_spells.get("2014", {}) as Dictionary).size(),
		(_spells.get("2024", {}) as Dictionary).size(),
	])


func _load_monsters(base_path: String, p_ruleset: String) -> void:
	var data: Array = _load_json_array(base_path + "5e-SRD-Monsters.json")
	var cache: Dictionary = _monsters.get(p_ruleset, {}) as Dictionary
	for raw: Variant in data:
		if not raw is Dictionary:
			continue
		var d := raw as Dictionary
		var monster: StatblockData = StatblockData.from_srd_monster(d, p_ruleset)
		cache[monster.srd_index] = monster

		# Cache image URL if present
		var img: Variant = d.get("image", "")
		if img is String and not (img as String).is_empty():
			_monster_image_urls[monster.srd_index] = img as String
	_monsters[p_ruleset] = cache


func _load_spells(base_path: String, p_ruleset: String) -> void:
	var data: Array = _load_json_array(base_path + "5e-SRD-Spells.json")
	var cache: Dictionary = _spells.get(p_ruleset, {}) as Dictionary
	for raw: Variant in data:
		if not raw is Dictionary:
			continue
		var spell: SpellData = SpellData.from_srd(raw as Dictionary, p_ruleset)
		cache[spell.index] = spell
	_spells[p_ruleset] = cache


func _load_raw_category(base_path: String, filename: String, target: Dictionary, p_ruleset: String) -> void:
	var path: String = base_path + filename
	if not FileAccess.file_exists(path):
		return
	var data: Array = _load_json_array(path)
	target[p_ruleset] = data


func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SRDLibraryService: failed to open %s" % path)
		return []
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return parsed as Array
	return []


# ---------------------------------------------------------------------------
# Query — Monsters
# ---------------------------------------------------------------------------

func get_monsters(p_ruleset: String) -> Array:
	_ensure_loaded()
	var cache: Variant = _monsters.get(p_ruleset, {})
	if cache is Dictionary:
		return (cache as Dictionary).values()
	return []


func get_monster(index: String, p_ruleset: String) -> StatblockData:
	_ensure_loaded()
	var cache: Variant = _monsters.get(p_ruleset, {})
	if cache is Dictionary:
		var result: Variant = (cache as Dictionary).get(index, null)
		if result is StatblockData:
			return result as StatblockData
	return null


# ---------------------------------------------------------------------------
# Query — Spells
# ---------------------------------------------------------------------------

func get_spells(p_ruleset: String) -> Array:
	_ensure_loaded()
	var cache: Variant = _spells.get(p_ruleset, {})
	if cache is Dictionary:
		return (cache as Dictionary).values()
	return []


func get_spell(index: String, p_ruleset: String) -> SpellData:
	_ensure_loaded()
	var cache: Variant = _spells.get(p_ruleset, {})
	if cache is Dictionary:
		var result: Variant = (cache as Dictionary).get(index, null)
		if result is SpellData:
			return result as SpellData
	return null


# ---------------------------------------------------------------------------
# Query — Other categories (raw dicts for now, typed parsers in later phases)
# ---------------------------------------------------------------------------

func get_equipment(p_ruleset: String) -> Array:
	_ensure_loaded()
	var raw: Variant = _equipment.get(p_ruleset, [])
	if raw is Array:
		return raw as Array
	return []


func get_conditions(p_ruleset: String) -> Array:
	_ensure_loaded()
	var raw: Variant = _conditions.get(p_ruleset, [])
	if raw is Array:
		return raw as Array
	return []


func get_classes(p_ruleset: String) -> Array:
	_ensure_loaded()
	var raw: Variant = _classes.get(p_ruleset, [])
	if raw is Array:
		return raw as Array
	return []


func get_races(p_ruleset: String) -> Array:
	_ensure_loaded()
	var raw: Variant = _races.get(p_ruleset, [])
	if raw is Array:
		return raw as Array
	return []


# ---------------------------------------------------------------------------
# Query — Feats
# ---------------------------------------------------------------------------

func get_feats(p_ruleset: String) -> Array:
	_ensure_loaded()
	var raw: Variant = _feats.get(p_ruleset, [])
	if raw is Array:
		return raw as Array
	return []


func get_feat(index: String, p_ruleset: String) -> Dictionary:
	_ensure_loaded()
	var raw: Variant = _feats.get(p_ruleset, [])
	if raw is Array:
		for entry: Variant in raw as Array:
			if entry is Dictionary:
				if str((entry as Dictionary).get("index", "")) == index:
					return entry as Dictionary
	return {}


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

func search(query: String, category: String, p_ruleset: String) -> Array:
	_ensure_loaded()
	var results: Array = []
	var q: String = query.to_lower()

	var rulesets: Array = [p_ruleset] if not p_ruleset.is_empty() else ["2014", "2024"]

	for rs: String in rulesets:
		# Search monsters
		if category.is_empty() or category == "monsters":
			var monster_cache: Variant = _monsters.get(rs, {})
			if monster_cache is Dictionary:
				for monster: Variant in (monster_cache as Dictionary).values():
					if not monster is StatblockData:
						continue
					var m := monster as StatblockData
					if _matches_query(q, m.name, m.srd_index, m.creature_type):
						results.append(m)

		# Search spells
		if category.is_empty() or category == "spells":
			var spell_cache: Variant = _spells.get(rs, {})
			if spell_cache is Dictionary:
				for spell: Variant in (spell_cache as Dictionary).values():
					if not spell is SpellData:
						continue
					var sp := spell as SpellData
					if _matches_query(q, sp.name, sp.index, sp.school):
						results.append(sp)

		# Search equipment
		if category.is_empty() or category == "equipment":
			var equip_list: Variant = _equipment.get(rs, [])
			if equip_list is Array:
				for item_raw: Variant in equip_list as Array:
					if not item_raw is Dictionary:
						continue
					var item_d := item_raw as Dictionary
					var item_name: String = str(item_d.get("name", ""))
					var item_index: String = str(item_d.get("index", ""))
					if _matches_query(q, item_name, item_index, ""):
						results.append(item_d)

	return results


func _matches_query(query: String, p_name: String, index: String, type_str: String) -> bool:
	if query.is_empty():
		return true
	return p_name.to_lower().contains(query) or index.to_lower().contains(query) or type_str.to_lower().contains(query)


# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------

func get_version() -> String:
	_ensure_loaded()
	return _version


# ---------------------------------------------------------------------------
# Monster Images
# ---------------------------------------------------------------------------

func get_monster_image_url(index: String) -> String:
	_ensure_loaded()
	var path: Variant = _monster_image_urls.get(index, "")
	if path is String and not (path as String).is_empty():
		return API_IMAGE_BASE + (path as String)
	return ""


func get_cached_monster_image(index: String) -> Image:
	var cache_path: String = IMAGE_CACHE_DIR + index + ".png"
	if not FileAccess.file_exists(cache_path):
		return null
	var img := Image.new()
	var err: Error = img.load(cache_path)
	if err != OK:
		return null
	return img


func prefetch_all_monster_images() -> void:
	_ensure_loaded()
	var indices: Array = []
	for url_index: Variant in _monster_image_urls:
		indices.append(str(url_index))

	if indices.is_empty():
		image_prefetch_completed.emit()
		return

	# Ensure cache directory exists
	DirAccess.make_dir_recursive_absolute(IMAGE_CACHE_DIR)

	var total: int = indices.size()
	var current: int = 0

	for idx: String in indices:
		current += 1
		image_prefetch_progress.emit(current, total)

		var cache_path: String = IMAGE_CACHE_DIR + idx + ".png"
		if FileAccess.file_exists(cache_path):
			continue

		var url: String = get_monster_image_url(idx)
		if url.is_empty():
			continue

		# Download via HTTPRequest node
		var http := HTTPRequest.new()
		add_child(http)
		var err: Error = http.request(url)
		if err != OK:
			http.queue_free()
			continue

		# Wait for completion
		var response: Array = await http.request_completed
		http.queue_free()

		var result_code: int = int(response[0])
		var status_code: int = int(response[1])
		var body: PackedByteArray = response[3] as PackedByteArray

		if result_code != HTTPRequest.RESULT_SUCCESS or status_code != 200:
			continue

		# Save to cache
		var file := FileAccess.open(cache_path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(body)
			file.close()

	image_prefetch_completed.emit()


func check_for_updates(version_url: String) -> void:
	_ensure_loaded()
	if version_url.is_empty():
		update_check_completed.emit(false, "", "No update URL configured.")
		return
	var http := HTTPRequest.new()
	add_child(http)
	var err: Error = http.request(version_url)
	if err != OK:
		http.queue_free()
		update_check_completed.emit(false, "", "HTTP request failed (error %d)." % err)
		return
	var response: Array = await http.request_completed
	http.queue_free()
	var result_code: int = int(response[0])
	var status_code: int = int(response[1])
	var body: PackedByteArray = response[3] as PackedByteArray
	if result_code != HTTPRequest.RESULT_SUCCESS or status_code != 200:
		update_check_completed.emit(false, "", "Could not reach update server (HTTP %d)." % status_code)
		return
	var text: String = body.get_string_from_utf8()
	var remote: Variant = JSON.parse_string(text)
	if remote == null or not remote is Dictionary:
		update_check_completed.emit(false, "", "Invalid response from update server.")
		return
	var remote_ver: String = str((remote as Dictionary).get("version", ""))
	if remote_ver.is_empty():
		update_check_completed.emit(false, "", "Remote version file has no version field.")
		return
	var has_update: bool = _compare_semver(_version, remote_ver) < 0
	if has_update:
		update_check_completed.emit(true, remote_ver, "Update available: %s → %s" % [_version, remote_ver])
	else:
		update_check_completed.emit(false, remote_ver, "SRD is up to date (v%s)." % _version)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _compare_semver(local: String, remote: String) -> int:
	## Returns -1 if local < remote, 0 if equal, 1 if local > remote.
	var l_parts: PackedStringArray = local.split(".")
	var r_parts: PackedStringArray = remote.split(".")
	var max_len: int = maxi(l_parts.size(), r_parts.size())
	for i: int in range(max_len):
		var l_val: int = int(l_parts[i]) if i < l_parts.size() else 0
		var r_val: int = int(r_parts[i]) if i < r_parts.size() else 0
		if l_val < r_val:
			return -1
		elif l_val > r_val:
			return 1
	return 0

func _ensure_loaded() -> void:
	if not _loaded:
		load_library()
