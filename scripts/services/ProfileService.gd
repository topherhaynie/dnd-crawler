extends Node
class_name ProfileService

signal profiles_changed()
const JsonUtils = preload("res://scripts/utils/JsonUtils.gd")

var profiles: Array = []

func _ready() -> void:
	load_profiles()

func get_profiles() -> Array:
	return profiles.duplicate(true)

func get_profile_by_id(_id: String):
	for p in profiles:
		if p is Dictionary and str(p.get("id", "")) == _id:
			return p
		if p is PlayerProfile and str(p.id) == _id:
			return p
	return null

func add_profile(_profile: Dictionary) -> void:
	profiles.append(_profile)
	emit_signal("profiles_changed")

func remove_profile(_id: String) -> void:
	for i in range(profiles.size()):
		var p = profiles[i]
		if (p is Dictionary and str(p.get("id", "")) == _id) or (p is PlayerProfile and str(p.id) == _id):
			profiles.remove_at(i)
			emit_signal("profiles_changed")
			return

func save_profiles() -> void:
	var data := []
	for profile in profiles:
		if profile is PlayerProfile:
			(profile as PlayerProfile).ensure_id()
			data.append((profile as PlayerProfile).to_dict())
		elif profile is Dictionary:
			data.append(profile)
	# Prefer using the Persistence service when available
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var persistence: Node = registry.get_service("Persistence") as Node
		if persistence == null:
			persistence = registry.get_service("PersistenceAdapter") as Node
		if persistence != null and persistence.has_method("save_game"):
			persistence.save_game("profiles", {"profiles": data})
			emit_signal("profiles_changed")
			return
	# Fallback: write directly to profiles.json
	_write_json("user://data/profiles.json", data)
	emit_signal("profiles_changed")

func load_profiles() -> void:
	# Prefer loading via Persistence service when available
	var raw: Variant = null
	var registry: Node = get_node_or_null("/root/ServiceRegistry") as Node
	if registry != null and registry.has_method("get_service"):
		var persistence: Node = registry.get_service("Persistence") as Node
		if persistence == null:
			persistence = registry.get_service("PersistenceAdapter") as Node
		if persistence != null and persistence.has_method("load_game"):
			var loaded: Variant = persistence.load_game("profiles")
			# If persistence returned nothing/empty (no saves yet), fall back to legacy path
			if loaded == null or (loaded is Dictionary and loaded.size() == 0):
				var legacy: Variant = _read_json("user://data/profiles.json")
				if legacy is Dictionary and legacy.has("profiles"):
					raw = legacy["profiles"]
				else:
					raw = legacy
			else:
				if loaded is Dictionary and loaded.has("profiles"):
					raw = loaded["profiles"]
				else:
					raw = loaded
	else:
		raw = _read_json("user://data/profiles.json")
		# Backwards-compat: accept either an array or a wrapper { "profiles": [...] }
		if raw is Dictionary and raw.has("profiles"):
			raw = raw["profiles"]
	profiles.clear()
	if raw == null:
		emit_signal("profiles_changed")
		return
	if not raw is Array:
		push_error("ProfileService: profiles.json is not an array")
		emit_signal("profiles_changed")
		return
	for entry in raw:
		if entry is Dictionary:
			var profile := PlayerProfile.from_dict(entry)
			profiles.append(profile)
	emit_signal("profiles_changed")

func register_player(_player_id: String) -> void:
	# noop for profile service; GameState may track locks/positions
	return

# --- JSON helpers ---
func _write_json(path: String, data: Variant) -> void:
	var dir = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	else:
		push_error("ProfileService: could not write to %s" % path)

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ProfileService: could not read %s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JsonUtils.parse_json_text(text)
	if parsed == null:
		push_error("ProfileService: JSON parse error in %s" % path)
		return null
	# Handle Godot JSON parse wrapper { "result": <value> }
	if parsed is Dictionary and parsed.has("result"):
		return parsed["result"]
	return parsed
