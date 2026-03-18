extends Node

# ---------------------------------------------------------------------------
# GameState — central store for all runtime session data.
# All other systems read/write through this singleton.
# ---------------------------------------------------------------------------

signal player_lock_changed(player_id, is_locked: bool)
signal dm_mode_changed(mode: DMMode)
signal notification_added(notification: Dictionary)
signal profiles_changed

enum DMMode {PLAY, EDITOR}

# --- Window registry (future multi-window expansion point) ----------------
# Index 0 = DM Window ID, Index 1 = Player TV Window ID
var windows: Array = []

# --- DM state -------------------------------------------------------------
var dm_mode: DMMode = DMMode.PLAY

# --- Player state ---------------------------------------------------------
# Keyed by player profile id (UUID string)
var player_locked: Dictionary = {} # { player_id: bool }
var player_positions: Dictionary = {} # { player_id: Vector2 }

# --- Map state ------------------------------------------------------------
var active_map: Dictionary = {} # loaded map metadata dict
var map_objects: Array = [] # Array of MapObject resources (populated in Phase 6)

# --- DM Notification Queue -----------------------------------------------
# Each entry: { "id": int, "type": String, "player_id": int, "label": String,
#               "notes": String, "object_ref": Variant }
var notification_queue: Array = []
var _next_notification_id: int = 0

# ---------------------------------------------------------------------------
# Player lock helpers
# ---------------------------------------------------------------------------

func lock_player(player_id) -> void:
	player_locked[player_id] = true
	emit_signal("player_lock_changed", player_id, true)

func unlock_player(player_id) -> void:
	player_locked[player_id] = false
	emit_signal("player_lock_changed", player_id, false)

func lock_all_players() -> void:
	for pid in player_locked.keys():
		lock_player(pid)

func unlock_all_players() -> void:
	for pid in player_locked.keys():
		unlock_player(pid)

func is_locked(player_id) -> bool:
	return player_locked.get(player_id, false)

func register_player(player_id) -> void:
	if not player_id in player_locked:
		player_locked[player_id] = false
		player_positions[player_id] = Vector2.ZERO

# ---------------------------------------------------------------------------
# DM mode helpers
# ---------------------------------------------------------------------------

func set_dm_mode(mode: DMMode) -> void:
	if dm_mode != mode:
		dm_mode = mode
		emit_signal("dm_mode_changed", mode)

# ---------------------------------------------------------------------------
# Notification queue helpers
# ---------------------------------------------------------------------------

func push_notification(type: String, player_id, label: String, notes: String = "", object_ref: Variant = null) -> int:
	var entry := {
		"id": _next_notification_id,
		"type": type,
		"player_id": player_id,
		"label": label,
		"notes": notes,
		"object_ref": object_ref
	}
	_next_notification_id += 1
	notification_queue.append(entry)
	emit_signal("notification_added", entry)
	return entry["id"]

func dismiss_notification(notification_id: int, unfreeze_player: bool = true) -> void:
	for i in range(notification_queue.size()):
		if notification_queue[i]["id"] == notification_id:
			var entry = notification_queue[i]
			notification_queue.remove_at(i)
			if unfreeze_player and entry.get("player_id", null) != null:
				unlock_player(entry["player_id"])
			break

# ---------------------------------------------------------------------------
# Profile persistence (player profiles stored here at runtime)
# ---------------------------------------------------------------------------

var profiles: Array = [] # Array of PlayerProfile resources
const JsonUtils = preload("res://scripts/utils/JsonUtils.gd")


func _ready() -> void:
	load_profiles()

func save_profiles() -> void:
	var data := []
	for profile in profiles:
		if profile is PlayerProfile:
			(profile as PlayerProfile).ensure_id()
			data.append((profile as PlayerProfile).to_dict())
		elif profile is Dictionary:
			data.append(profile)
	# Prefer using Persistence service when available
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
	var raw = null
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var persistence: Node = registry.get_service("Persistence") as Node
		if persistence == null:
			persistence = registry.get_service("PersistenceAdapter") as Node
		if persistence != null and persistence.has_method("load_game"):
			var loaded: Variant = persistence.load_game("profiles")
			if loaded is Dictionary and loaded.has("profiles"):
				raw = loaded["profiles"]
			else:
				raw = loaded
	else:
		raw = _read_json("user://data/profiles.json")
	profiles.clear()
	if raw == null:
		emit_signal("profiles_changed")
		return
	if not raw is Array:
		push_error("GameState: profiles.json is not an array")
		emit_signal("profiles_changed")
		return
	for entry in raw:
		if entry is Dictionary:
			var profile := PlayerProfile.from_dict(entry)
			profiles.append(profile)
	_rebuild_player_state_from_profiles()
	emit_signal("profiles_changed")


func get_profile_by_id(profile_id: String) -> PlayerProfile:
	for profile in profiles:
		if profile is PlayerProfile and (profile as PlayerProfile).id == profile_id:
			return profile
	return null


func _rebuild_player_state_from_profiles() -> void:
	var next_locked: Dictionary = {}
	var next_positions: Dictionary = {}
	for profile in profiles:
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		p.ensure_id()
		next_locked[p.id] = player_locked.get(p.id, false)
		next_positions[p.id] = player_positions.get(p.id, Vector2.ZERO)
	player_locked = next_locked
	player_positions = next_positions

# ---------------------------------------------------------------------------
# JSON helpers (internal)
# ---------------------------------------------------------------------------

func _write_json(path: String, data: Variant) -> void:
	var dir = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	else:
		push_error("GameState: could not write to %s" % path)

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("GameState: could not read %s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JsonUtils.parse_json_text(text)
	if parsed == null:
		push_error("GameState: JSON parse error in %s" % path)
	return parsed
