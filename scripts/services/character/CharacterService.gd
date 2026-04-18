extends ICharacterService
class_name CharacterService

# ---------------------------------------------------------------------------
# CharacterService — global character roster, persisted to
# user://data/characters.json  (mirroring profiles.json pattern).
# Campaign-independent: characters exist independently of any open campaign.
# ---------------------------------------------------------------------------

const CHARACTERS_FILE: String = "user://data/characters.json"

var _characters: Dictionary = {} ## id -> StatblockData


func _ready() -> void:
	load_characters()


func get_characters() -> Array:
	var result: Array = []
	for sb: StatblockData in _characters.values():
		result.append(sb)
	return result


func get_character_by_id(id: String) -> StatblockData:
	return _characters.get(id, null) as StatblockData


func add_character(statblock: StatblockData) -> void:
	if statblock == null or statblock.id.is_empty():
		push_warning("CharacterService.add_character: statblock has no id")
		return
	_characters[statblock.id] = statblock
	emit_signal("characters_changed")


func remove_character(id: String) -> void:
	if _characters.erase(id):
		emit_signal("characters_changed")


func save_characters() -> void:
	var data: Array = []
	for sb: StatblockData in _characters.values():
		data.append(sb.to_dict())
	_write_json(CHARACTERS_FILE, data)
	emit_signal("characters_changed")


func load_characters() -> void:
	_characters.clear()
	var raw: Variant = _read_json(CHARACTERS_FILE)
	if raw == null:
		emit_signal("characters_changed")
		return
	if not raw is Array:
		push_warning("CharacterService: %s is not an array" % CHARACTERS_FILE)
		emit_signal("characters_changed")
		return
	for entry: Variant in raw as Array:
		if entry is Dictionary:
			var sb: StatblockData = StatblockData.from_dict(entry as Dictionary)
			if not sb.id.is_empty():
				_characters[sb.id] = sb
	emit_signal("characters_changed")


## Import characters from a legacy campaign's embedded characters dict.
## Called by CampaignService when opening an old campaign bundle.
func import_from_campaign_dict(chars: Dictionary) -> void:
	var imported: int = 0
	for key: Variant in chars:
		var raw: Variant = chars[key]
		if raw is Dictionary:
			var sb: StatblockData = StatblockData.from_dict(raw as Dictionary)
			if not sb.id.is_empty() and not _characters.has(sb.id):
				_characters[sb.id] = sb
				imported += 1
	if imported > 0:
		save_characters()


# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------

func _write_json(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir().replace("user://", ""))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	else:
		push_error("CharacterService: could not write to %s" % path)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed
