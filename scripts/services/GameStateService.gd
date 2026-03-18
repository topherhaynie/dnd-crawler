extends Node
class_name GameStateService
signal profiles_changed()

const JsonUtils = preload("res://scripts/utils/JsonUtils.gd")
signal player_lock_changed(player_id, is_locked: bool)

var profiles: Array = []
var player_locked: Dictionary = {}
var player_positions: Dictionary = {}
var windows: Array = []

func _ready() -> void:
    load_profiles()

func get_profile_by_id(id: String):
    for p in profiles:
        if not p is Object:
            continue
        if str(p.id) == id:
            return p
    return null

func register_player(player_id: String) -> void:
    if not player_id in player_locked:
        player_locked[player_id] = false
        player_positions[player_id] = Vector2.ZERO
    # No signal emitted here; callers expect state to be present immediately


# --- Player lock helpers (compat with legacy GameState autoload) ---
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


# --- Profile persistence (mirror of legacy GameState autoload behaviour) ---
func save_profiles() -> void:
    var data := []
    for profile in profiles:
        if profile is PlayerProfile:
            (profile as PlayerProfile).ensure_id()
            data.append((profile as PlayerProfile).to_dict())
        elif profile is Dictionary:
            data.append(profile)
    _write_json("user://data/profiles.json", data)
    emit_signal("profiles_changed")


func load_profiles() -> void:
    var raw = _read_json("user://data/profiles.json")
    profiles.clear()
    if raw == null:
        emit_signal("profiles_changed")
        return
    if not raw is Array:
        push_error("GameStateService: profiles.json is not an array")
        emit_signal("profiles_changed")
        return
    for entry in raw:
        if entry is Dictionary:
            var profile := PlayerProfile.from_dict(entry)
            profiles.append(profile)
    _rebuild_player_state_from_profiles()
    emit_signal("profiles_changed")


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


# --- JSON helpers (internal) ---
func _write_json(path: String, data: Variant) -> void:
    var dir = path.get_base_dir()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data, "\t"))
        file.close()
    else:
        push_error("GameStateService: could not write to %s" % path)


func _read_json(path: String) -> Variant:
    return JsonUtils.read_json(path)
