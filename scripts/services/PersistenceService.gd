extends Node
class_name PersistenceService

signal persistence_changed(save_name: String)
const JsonUtilsScript = preload("res://scripts/utils/JsonUtils.gd")

func _init() -> void:
    # Ensure save directory exists
    var dir_path := "user://data/saves"
    var dir := DirAccess.open(ProjectSettings.globalize_path(dir_path))
    if dir == null:
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

func save_game(save_name: String, state: Dictionary) -> bool:
    var rel_path := "user://data/saves/%s.json" % save_name
    var abs_dir := ProjectSettings.globalize_path("user://data/saves")
    DirAccess.make_dir_recursive_absolute(abs_dir)
    var abs_path := ProjectSettings.globalize_path(rel_path)
    var tmp_path := abs_path + ".tmp"

    var fa := FileAccess.open(tmp_path, FileAccess.WRITE)
    if fa == null:
        return false
    fa.store_string(JSON.stringify(state, "\t"))
    fa.close()

    # Attempt atomic rename of temp -> final path. Prefer DirAccess.rename if available.
    var raz := DirAccess.open(abs_dir)
    var rename_ok := false
    if raz != null:
        if raz.has_method("rename"):
            var rerr := raz.rename(tmp_path, abs_path)
            rename_ok = rerr == OK
        else:
            # Try static rename helper
            var rerr2 := DirAccess.rename_absolute(tmp_path, abs_path)
            rename_ok = rerr2 == OK
    if not rename_ok:
        # Fallback: try OS-level move via FileAccess (non-atomic fallback)
        if FileAccess.file_exists(abs_path):
            DirAccess.remove_absolute(abs_path)
        var fin := FileAccess.open(tmp_path, FileAccess.READ)
        if fin == null:
            return false
        var data := fin.get_as_text()
        fin.close()
        var fout := FileAccess.open(abs_path, FileAccess.WRITE)
        if fout == null:
            return false
        fout.store_string(data)
        fout.close()
        DirAccess.remove_absolute(tmp_path)

    emit_signal("persistence_changed", save_name)
    return true

func load_game(save_name: String) -> Dictionary:
    var path := "user://data/saves/%s.json" % save_name
    if not FileAccess.file_exists(path):
        return {}
    var fa := FileAccess.open(path, FileAccess.READ)
    if fa == null:
        return {}
    var content := fa.get_as_text()
    fa.close()
    if content == "":
        return {}
    var parsed: Variant = JsonUtilsScript.parse_json_text(content)
    if parsed is Dictionary:
        return parsed as Dictionary
    return {}

func list_saves() -> Array:
    var out := []
    var dir := DirAccess.open("user://data/saves")
    if dir == null:
        return out
    dir.list_dir_begin()
    var fname := dir.get_next()
    while fname != "":
        if not dir.current_is_dir():
            if fname.ends_with(".json"):
                out.append(fname.get_basename())
        fname = dir.get_next()
    dir.list_dir_end()
    return out

func delete_save(save_name: String) -> bool:
    var path := "user://data/saves/%s.json" % save_name
    var dir := DirAccess.open("user://data/saves")
    if dir == null:
        return false
    if dir.file_exists(path):
        var err := dir.remove(path)
        if err == OK:
            emit_signal("persistence_changed", save_name)
            return true
    return false

func export_to_path(save_name: String, dest_path: String) -> bool:
    # Write the named save (user://data/saves/<save_name>.json) to dest_path.
    var src := ProjectSettings.globalize_path("user://data/saves/%s.json" % save_name)
    if not FileAccess.file_exists(src):
        return false
    var fa := FileAccess.open(src, FileAccess.READ)
    if fa == null:
        return false
    var content := fa.get_as_text()
    fa.close()

    var parent := dest_path.get_base_dir()
    if not DirAccess.dir_exists_absolute(parent):
        var mk := DirAccess.make_dir_recursive_absolute(parent)
        if mk != OK:
            return false

    var dst := FileAccess.open(dest_path, FileAccess.WRITE)
    if dst == null:
        return false
    dst.store_string(content)
    dst.close()
    return true

func copy_file(from_path: String, to_path: String) -> int:
    var parent_dir := to_path.get_base_dir()
    if not DirAccess.dir_exists_absolute(parent_dir):
        var mkdir_err := DirAccess.make_dir_recursive_absolute(parent_dir)
        if mkdir_err != OK:
            return mkdir_err
    var src := FileAccess.open(from_path, FileAccess.READ)
    if src == null:
        return FileAccess.get_open_error()
    var data := src.get_buffer(src.get_length())
    src.close()
    var dst := FileAccess.open(to_path, FileAccess.WRITE)
    if dst == null:
        return FileAccess.get_open_error()
    dst.store_buffer(data)
    dst.close()
    return OK
