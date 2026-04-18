extends ICampaignService
class_name CampaignService

# ---------------------------------------------------------------------------
# CampaignService — persists campaigns as directory bundles under
# user://data/campaigns/<slug>.campaign/campaign.json
# ---------------------------------------------------------------------------

const CAMPAIGNS_DIR: String = "user://data/campaigns/"
const _PREFS_FILE: String = "user://data/dm_prefs.json"

var _active: CampaignData = null
var _active_path: String = ""


func get_active_campaign() -> CampaignData:
	return _active


## Returns the absolute filesystem path to the last opened/created campaign
## directory, or "" if no preference has been recorded yet.
func get_last_campaign_path() -> String:
	var raw: Variant = _read_prefs()
	if raw is Dictionary:
		return str((raw as Dictionary).get("last_campaign_path", ""))
	return ""


func new_campaign(p_name: String, p_ruleset: String) -> CampaignData:
	var c := CampaignData.new()
	c.generate_id()
	c.name = p_name
	c.default_ruleset = p_ruleset
	c.created_at = Time.get_datetime_string_from_system(true)
	c.updated_at = c.created_at

	_active = c
	_active_path = CAMPAIGNS_DIR + _unique_slug(p_name) + ".campaign/"

	# Save immediately so the directory exists
	_write_campaign(c, _active_path)
	_save_last_campaign_path(_active_path)

	campaign_loaded.emit(c)
	return c


func open_campaign(path: String) -> CampaignData:
	var json_path: String = path
	# Accept either directory or direct json file
	if path.ends_with(".campaign") or path.ends_with(".campaign/"):
		json_path = path.rstrip("/") + "/campaign.json"

	if not FileAccess.file_exists(json_path):
		push_warning("CampaignService.open_campaign: file not found: %s" % json_path)
		return null

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_warning("CampaignService.open_campaign: cannot open %s" % json_path)
		return null

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("CampaignService.open_campaign: invalid JSON in %s" % json_path)
		return null

	var c: CampaignData = CampaignData.from_dict(parsed as Dictionary)
	_active = c
	_active_path = json_path.get_base_dir() + "/"
	_save_last_campaign_path(_active_path)

	## One-time migration: if the file had the old embedded characters dict,
	## import them into the global CharacterService and update the campaign file.
	if not c._legacy_characters.is_empty():
		var sreg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if sreg != null and sreg.character != null and sreg.character.service != null:
			var char_svc: ICharacterService = sreg.character.service
			for key: Variant in c._legacy_characters:
				var raw: Variant = c._legacy_characters[key]
				if raw is Dictionary:
					var sb: StatblockData = StatblockData.from_dict(raw as Dictionary)
					if not sb.id.is_empty():
						char_svc.add_character(sb)
						if not c.character_ids.has(sb.id):
							c.character_ids.append(sb.id)
			char_svc.save_characters()
			c._legacy_characters.clear()
			save_campaign()

	campaign_loaded.emit(c)
	return c


func save_campaign() -> bool:
	if _active == null or _active_path.is_empty():
		return false
	_active.updated_at = Time.get_datetime_string_from_system(true)
	var ok: bool = _write_campaign(_active, _active_path)
	if ok:
		_save_last_campaign_path(_active_path)
	return ok


func save_campaign_as(path: String) -> bool:
	if _active == null:
		return false
	var dir_path: String = path
	if not dir_path.ends_with("/"):
		dir_path += "/"
	_active.updated_at = Time.get_datetime_string_from_system(true)
	_active_path = dir_path
	return _write_campaign(_active, dir_path)


func close_campaign() -> void:
	_active = null
	_active_path = ""
	campaign_closed.emit()


func list_campaigns() -> Array:
	var results: Array = []
	DirAccess.make_dir_recursive_absolute(CAMPAIGNS_DIR)
	var dir := DirAccess.open(CAMPAIGNS_DIR)
	if dir == null:
		return results

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and entry.ends_with(".campaign"):
			var json_path: String = CAMPAIGNS_DIR + entry + "/campaign.json"
			if FileAccess.file_exists(json_path):
				var file := FileAccess.open(json_path, FileAccess.READ)
				if file != null:
					var parsed: Variant = JSON.parse_string(file.get_as_text())
					file.close()
					if parsed is Dictionary:
						var d := parsed as Dictionary
						results.append({
							"id": str(d.get("id", "")),
							"name": str(d.get("name", "")),
							"path": CAMPAIGNS_DIR + entry + "/",
							"updated_at": str(d.get("updated_at", "")),
							"default_ruleset": str(d.get("default_ruleset", "2014")), "map_paths": d.get("map_paths", []) if d.get("map_paths") is Array else [],
						"save_paths": d.get("save_paths", []) if d.get("save_paths") is Array else [], })
		entry = dir.get_next()
	dir.list_dir_end()
	return results


# ---------------------------------------------------------------------------
# Bestiary
# ---------------------------------------------------------------------------

func add_to_bestiary(statblock: StatblockData) -> void:
	if _active == null:
		push_warning("CampaignService.add_to_bestiary: no active campaign")
		return
	## SRD entries are stored as lightweight references; custom entries store the full dict.
	if not statblock.srd_index.is_empty() and statblock.source.begins_with("SRD"):
		_active.bestiary[statblock.srd_index] = {
			"type": "srd_ref",
			"srd_index": statblock.srd_index,
			"ruleset": statblock.ruleset,
		}
	else:
		if statblock.id.is_empty():
			statblock.id = StatblockData.generate_id()
		_active.bestiary[statblock.id] = statblock.to_dict()
	bestiary_updated.emit()


func remove_from_bestiary(statblock_id: String) -> void:
	if _active == null:
		return
	_active.bestiary.erase(statblock_id)
	bestiary_updated.emit()


func get_bestiary() -> Array:
	if _active == null:
		return []
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var results: Array = []
	for key: Variant in _active.bestiary:
		var raw: Variant = _active.bestiary[key]
		if not raw is Dictionary:
			continue
		var d := raw as Dictionary
		if str(d.get("type", "")) == "srd_ref":
			## Resolve SRD reference on the fly.
			if registry != null and registry.srd != null:
				var sb: StatblockData = registry.srd.get_monster(
					str(d.get("srd_index", "")), str(d.get("ruleset", "2014")))
				if sb != null:
					results.append(sb)
		else:
			results.append(StatblockData.from_dict(d))
	return results


# ---------------------------------------------------------------------------
# Item Library
# ---------------------------------------------------------------------------

func add_to_item_library(item: ItemEntry) -> void:
	if _active == null:
		push_warning("CampaignService.add_to_item_library: no active campaign")
		return
	if item.id.is_empty():
		item.id = ItemEntry.generate_id()
	_active.item_library[item.id] = item.to_dict()
	item_library_updated.emit()


func remove_from_item_library(item_id: String) -> void:
	if _active == null:
		return
	_active.item_library.erase(item_id)
	item_library_updated.emit()


func get_item_library() -> Array:
	if _active == null:
		return []
	var results: Array = []
	for key: Variant in _active.item_library:
		var raw: Variant = _active.item_library[key]
		if raw is Dictionary:
			results.append(ItemEntry.from_dict(raw as Dictionary))
	return results


# ---------------------------------------------------------------------------
# Characters (ID references only — data lives in CharacterService)
# ---------------------------------------------------------------------------

func add_character(character_id: String) -> void:
	if _active == null:
		push_warning("CampaignService.add_character: no active campaign")
		return
	if not _active.character_ids.has(character_id):
		_active.character_ids.append(character_id)


func remove_character(character_id: String) -> void:
	if _active == null:
		return
	_active.character_ids.erase(character_id)
	_active.character_overrides.erase(character_id)


func get_character_ids() -> Array:
	if _active == null:
		return []
	return _active.character_ids.duplicate()


func has_character(character_id: String) -> bool:
	if _active == null:
		return false
	return _active.character_ids.has(character_id)


# ---------------------------------------------------------------------------
# Character overrides (campaign-scoped presentation layer)
# ---------------------------------------------------------------------------

func set_character_override(character_id: String, p_override: CharacterOverride) -> void:
	if _active == null:
		push_warning("CampaignService.set_character_override: no active campaign")
		return
	p_override.character_id = character_id
	_active.character_overrides[character_id] = p_override.to_dict()


func get_character_override(character_id: String) -> CharacterOverride:
	if _active == null:
		return null
	var raw: Variant = _active.character_overrides.get(character_id, null)
	if raw is Dictionary:
		return CharacterOverride.from_dict(raw as Dictionary)
	return null


func remove_character_override(character_id: String) -> void:
	if _active == null:
		return
	_active.character_overrides.erase(character_id)


func get_all_character_overrides() -> Dictionary:
	if _active == null:
		return {}
	return _active.character_overrides.duplicate()


func resolve_character_portrait(character_id: String) -> String:
	if _active == null:
		return ""
	# 1) Campaign override portrait
	var raw: Variant = _active.character_overrides.get(character_id, null)
	if raw is Dictionary:
		var co := CharacterOverride.from_dict(raw as Dictionary)
		if not co.portrait_path.is_empty():
			return co.portrait_path
	# 2) Global character portrait
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.character != null:
		var sb: StatblockData = reg.character.get_character_by_id(character_id)
		if sb != null and not sb.portrait_path.is_empty():
			return sb.portrait_path
	return ""


func resolve_character_name(character_id: String) -> String:
	if _active == null:
		return ""
	# 1) Campaign override display name
	var raw: Variant = _active.character_overrides.get(character_id, null)
	if raw is Dictionary:
		var co := CharacterOverride.from_dict(raw as Dictionary)
		if not co.display_name.is_empty():
			return co.display_name
	# 2) Global character name
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.character != null:
		var sb: StatblockData = reg.character.get_character_by_id(character_id)
		if sb != null:
			return sb.name
	return ""


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

func update_settings(new_settings: Dictionary) -> void:
	if _active == null:
		return
	_active.settings.merge(new_settings, true)


func get_setting(key: String) -> Variant:
	if _active == null:
		return null
	return _active.settings.get(key, null)


# ---------------------------------------------------------------------------
# Map / save path management
# ---------------------------------------------------------------------------

func add_map_path(path: String) -> void:
	if _active == null:
		return
	if not _active.map_paths.has(path):
		_active.map_paths.append(path)
		assets_changed.emit()


func remove_map_path(path: String) -> void:
	if _active == null:
		return
	_active.map_paths.erase(path)
	assets_changed.emit()


func get_map_paths() -> Array:
	if _active == null:
		return []
	return _active.map_paths.duplicate()


func add_save_path(path: String) -> void:
	if _active == null:
		return
	if not _active.save_paths.has(path):
		_active.save_paths.append(path)
		assets_changed.emit()


func remove_save_path(path: String) -> void:
	if _active == null:
		return
	_active.save_paths.erase(path)
	assets_changed.emit()


func get_save_paths() -> Array:
	if _active == null:
		return []
	return _active.save_paths.duplicate()


func get_campaign_dir() -> String:
	return _active_path


# ---------------------------------------------------------------------------
# Notes
# ---------------------------------------------------------------------------

func add_note(title: String, body: String, folder: String = "") -> String:
	if _active == null:
		return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var note_id: String = "note_%d_%d" % [Time.get_unix_time_from_system(), rng.randi()]
	var now: String = Time.get_datetime_string_from_system(true)
	_active.notes.append({
		"id": note_id,
		"title": title,
		"body": body,
		"folder": folder,
		"created_at": now,
		"updated_at": now,
	})
	notes_changed.emit()
	return note_id


func update_note(note_id: String, title: String, body: String, folder: String = "") -> void:
	if _active == null:
		return
	for i: int in _active.notes.size():
		var n: Variant = _active.notes[i]
		if not n is Dictionary:
			continue
		if (n as Dictionary).get("id", "") == note_id:
			var d := n as Dictionary
			d["title"] = title
			d["body"] = body
			d["folder"] = folder
			d["updated_at"] = Time.get_datetime_string_from_system(true)
			_active.notes[i] = d
			notes_changed.emit()
			return


func delete_note(note_id: String) -> void:
	if _active == null:
		return
	for i: int in _active.notes.size():
		var n: Variant = _active.notes[i]
		if n is Dictionary and (n as Dictionary).get("id", "") == note_id:
			_active.notes.remove_at(i)
			notes_changed.emit()
			return


func get_notes() -> Array:
	if _active == null:
		return []
	return _active.notes.duplicate()


# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

func add_image(abs_path: String, copy_to_campaign: bool) -> Dictionary:
	if _active == null:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var img_id: String = "img_%d_%d" % [Time.get_unix_time_from_system(), rng.randi()]
	var stored_path: String = abs_path
	var copied: bool = false
	if copy_to_campaign:
		var assets_dir: String = _active_path + "assets/"
		DirAccess.make_dir_recursive_absolute(assets_dir)
		var ext: String = abs_path.get_extension()
		var dest: String = assets_dir + img_id + "." + ext
		var err: Error = DirAccess.copy_absolute(abs_path, dest)
		if err == OK:
			stored_path = dest
			copied = true
		else:
			push_warning("CampaignService.add_image: copy failed %s → %s (err %d)" % [abs_path, dest, err])
	var entry: Dictionary = {
		"id": img_id,
		"name": abs_path.get_file(),
		"path": stored_path,
		"folder": "",
		"copied": copied,
	}
	_active.images.append(entry)
	images_changed.emit()
	return entry


func update_image(image_id: String, new_name: String, new_folder: String) -> void:
	if _active == null:
		return
	for img: Variant in _active.images:
		if not img is Dictionary:
			continue
		var d := img as Dictionary
		if str(d.get("id", "")) == image_id:
			d["name"] = new_name
			d["folder"] = new_folder
			images_changed.emit()
			return


func remove_image(image_id: String) -> void:
	if _active == null:
		return
	for i: int in _active.images.size():
		var img: Variant = _active.images[i]
		if not img is Dictionary:
			continue
		if (img as Dictionary).get("id", "") == image_id:
			var d := img as Dictionary
			if bool(d.get("copied", false)):
				var path: String = str(d.get("path", ""))
				if not path.is_empty() and FileAccess.file_exists(path):
					DirAccess.remove_absolute(path)
			_active.images.remove_at(i)
			images_changed.emit()
			return


func get_images() -> Array:
	if _active == null:
		return []
	return _active.images.duplicate()


# ---------------------------------------------------------------------------
# Folder persistence
# ---------------------------------------------------------------------------

func get_note_folders() -> Array:
	if _active == null:
		return []
	return _active.note_folders.duplicate()


func add_note_folder(folder_name: String) -> void:
	if _active == null:
		return
	if not _active.note_folders.has(folder_name):
		_active.note_folders.append(folder_name)
		notes_changed.emit()


func remove_note_folder(folder_name: String) -> void:
	if _active == null:
		return
	var prefix: String = folder_name + "/"
	var i: int = _active.note_folders.size() - 1
	while i >= 0:
		var f: String = str(_active.note_folders[i])
		if f == folder_name or f.begins_with(prefix):
			_active.note_folders.remove_at(i)
		i -= 1
	notes_changed.emit()


func rename_note_folder(old_name: String, new_name: String) -> void:
	if _active == null:
		return
	var prefix: String = old_name + "/"
	for i: int in _active.note_folders.size():
		var f: String = str(_active.note_folders[i])
		if f == old_name:
			_active.note_folders[i] = new_name
		elif f.begins_with(prefix):
			_active.note_folders[i] = new_name + "/" + f.substr(prefix.length())
	## Also update notes that reference the old folder or subfolders
	for i: int in _active.notes.size():
		var n: Variant = _active.notes[i]
		if not n is Dictionary:
			continue
		var d := n as Dictionary
		var nf: String = str(d.get("folder", ""))
		if nf == old_name:
			d["folder"] = new_name
			d["updated_at"] = Time.get_datetime_string_from_system(true)
			_active.notes[i] = d
		elif nf.begins_with(prefix):
			d["folder"] = new_name + "/" + nf.substr(prefix.length())
			d["updated_at"] = Time.get_datetime_string_from_system(true)
			_active.notes[i] = d
	notes_changed.emit()


func get_image_folders() -> Array:
	if _active == null:
		return []
	return _active.image_folders.duplicate()


func add_image_folder(folder_name: String) -> void:
	if _active == null:
		return
	if not _active.image_folders.has(folder_name):
		_active.image_folders.append(folder_name)
		images_changed.emit()


func remove_image_folder(folder_name: String) -> void:
	if _active == null:
		return
	var prefix: String = folder_name + "/"
	var i: int = _active.image_folders.size() - 1
	while i >= 0:
		var f: String = str(_active.image_folders[i])
		if f == folder_name or f.begins_with(prefix):
			_active.image_folders.remove_at(i)
		i -= 1
	images_changed.emit()


func rename_image_folder(old_name: String, new_name: String) -> void:
	if _active == null:
		return
	var prefix: String = old_name + "/"
	for i: int in _active.image_folders.size():
		var f: String = str(_active.image_folders[i])
		if f == old_name:
			_active.image_folders[i] = new_name
		elif f.begins_with(prefix):
			_active.image_folders[i] = new_name + "/" + f.substr(prefix.length())
	for img: Variant in _active.images:
		if not img is Dictionary:
			continue
		var d := img as Dictionary
		var imf: String = str(d.get("folder", ""))
		if imf == old_name:
			d["folder"] = new_name
		elif imf.begins_with(prefix):
			d["folder"] = new_name + "/" + imf.substr(prefix.length())
	images_changed.emit()

func _write_campaign(c: CampaignData, dir_path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(dir_path)
	var json_path: String = dir_path + "campaign.json"
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		push_warning("CampaignService._write_campaign: cannot write %s" % json_path)
		return false
	file.store_string(JSON.stringify(c.to_dict(), "\t"))
	file.close()
	return true


## Convert a human name into a filesystem-safe slug (lowercase, spaces→hyphens,
## strips everything except a-z 0-9 and hyphens).  Appends "-2", "-3" etc. when
## a directory with that slug already exists under CAMPAIGNS_DIR.
func _unique_slug(p_name: String) -> String:
	var slug: String = p_name.to_lower().strip_edges()
	# Replace runs of whitespace/special chars with a single hyphen.
	var result: String = ""
	var prev_hyphen: bool = true # start true to strip leading hyphens
	for i: int in slug.length():
		var ch: String = slug.substr(i, 1)
		if ch >= "a" and ch <= "z" or ch >= "0" and ch <= "9":
			result += ch
			prev_hyphen = false
		elif not prev_hyphen:
			result += "-"
			prev_hyphen = true
	# Strip trailing hyphen.
	while result.ends_with("-"):
		result = result.left(result.length() - 1)
	if result.is_empty():
		result = "campaign"
	# Deduplicate against existing directories.
	var abs_base: String = ProjectSettings.globalize_path(CAMPAIGNS_DIR)
	if not DirAccess.dir_exists_absolute(abs_base.path_join(result + ".campaign")):
		return result
	var counter: int = 2
	while DirAccess.dir_exists_absolute(abs_base.path_join(result + "-%d.campaign" % counter)):
		counter += 1
	return result + "-%d" % counter


func _save_last_campaign_path(dir_path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path(dir_path)
	var prefs: Dictionary = {}
	var existing: Variant = _read_prefs()
	if existing is Dictionary:
		prefs = existing as Dictionary
	prefs["last_campaign_path"] = abs_path
	_write_prefs(prefs)


func _read_prefs() -> Variant:
	var abs_path: String = ProjectSettings.globalize_path(_PREFS_FILE)
	if not FileAccess.file_exists(abs_path):
		return null
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	return JSON.parse_string(text)


func _write_prefs(prefs: Dictionary) -> void:
	var abs_dir: String = ProjectSettings.globalize_path("user://data/")
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var abs_path: String = ProjectSettings.globalize_path(_PREFS_FILE)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(prefs, "\t"))
	f.close()
