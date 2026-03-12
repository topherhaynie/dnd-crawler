extends Node

# ---------------------------------------------------------------------------
# GameState — central store for all runtime session data.
# All other systems read/write through this singleton.
# ---------------------------------------------------------------------------

signal player_lock_changed(player_id: int, is_locked: bool)
signal dm_mode_changed(mode: DMMode)
signal notification_added(notification: Dictionary)

enum DMMode {PLAY, EDITOR}

# --- Window registry (future multi-window expansion point) ----------------
# Index 0 = DM Window ID, Index 1 = Player TV Window ID
var windows: Array = []

# --- DM state -------------------------------------------------------------
var dm_mode: DMMode = DMMode.PLAY

# --- Player state ---------------------------------------------------------
# Keyed by player profile id (int index, 0-based)
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

func lock_player(player_id: int) -> void:
	player_locked[player_id] = true
	emit_signal("player_lock_changed", player_id, true)

func unlock_player(player_id: int) -> void:
	player_locked[player_id] = false
	emit_signal("player_lock_changed", player_id, false)

func lock_all_players() -> void:
	for pid in player_locked.keys():
		lock_player(pid)

func unlock_all_players() -> void:
	for pid in player_locked.keys():
		unlock_player(pid)

func is_locked(player_id: int) -> bool:
	return player_locked.get(player_id, false)

func register_player(player_id: int) -> void:
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

func push_notification(type: String, player_id: int, label: String, notes: String = "", object_ref: Variant = null) -> int:
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
			if unfreeze_player and entry["player_id"] >= 0:
				unlock_player(entry["player_id"])
			break

# ---------------------------------------------------------------------------
# Profile persistence (player profiles stored here at runtime)
# ---------------------------------------------------------------------------

var profiles: Array = [] # Array of PlayerProfile resources (populated in Phase 3)

func save_profiles() -> void:
	var data := []
	for profile in profiles:
		data.append(profile.to_dict())
	_write_json("user://data/profiles.json", data)

func load_profiles() -> void:
	var raw = _read_json("user://data/profiles.json")
	if raw == null:
		return
	profiles.clear()
	# PlayerProfile class wired in Phase 3; stub load for now
	for dict in raw:
		profiles.append(dict)

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
	var result = JSON.parse_string(text)
	if result == null:
		push_error("GameState: JSON parse error in %s" % path)
	return result
