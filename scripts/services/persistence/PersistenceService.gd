extends IPersistenceService
class_name PersistenceService

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


# ---------------------------------------------------------------------------
# .sav bundle I/O
# ---------------------------------------------------------------------------

const _SAVES_DIR: String = "user://data/saves"


func save_game_bundle(bundle_path: String, state: RefCounted, fog_image: Image, map_bundle_path: String) -> bool:
	var abs_bundle := _abs(bundle_path)
	DirAccess.make_dir_recursive_absolute(abs_bundle)

	# 1. Copy the entire .map bundle into the .sav bundle as map.map/
	var embedded_map_dir := abs_bundle.path_join("map.map")
	if not _copy_dir_recursive(map_bundle_path, embedded_map_dir):
		push_error("PersistenceService: failed to embed .map into .sav at '%s'" % embedded_map_dir)
		return false

	# 2. Write fog.png (L8 image)
	if fog_image != null and not fog_image.is_empty():
		var fog_path := abs_bundle.path_join("fog.png")
		var err := fog_image.save_png(fog_path)
		if err != OK:
			push_error("PersistenceService: failed to save fog.png (err %d)" % err)
			return false

	# 3. Write state.json
	var state_path := abs_bundle.path_join("state.json")
	var fa := FileAccess.open(state_path, FileAccess.WRITE)
	if fa == null:
		push_error("PersistenceService: cannot write state.json at '%s'" % state_path)
		return false
	fa.store_string(JSON.stringify(state.to_dict(), "\t"))
	fa.close()

	emit_signal("persistence_changed", state.save_name)
	return true


func load_game_bundle(bundle_path: String) -> Dictionary:
	## Returns {"state": GameSaveData, "fog_image": Image, "map_bundle_path": String}
	## or empty dict on failure.
	var abs_bundle := _abs(bundle_path)

	# 1. Read state.json
	var state_path := abs_bundle.path_join("state.json")
	if not FileAccess.file_exists(state_path):
		push_error("PersistenceService: state.json not found in '%s'" % abs_bundle)
		return {}
	var fa := FileAccess.open(state_path, FileAccess.READ)
	if fa == null:
		return {}
	var text := fa.get_as_text()
	fa.close()
	var parsed: Variant = JsonUtilsScript.parse_json_text(text)
	if not (parsed is Dictionary):
		push_error("PersistenceService: invalid state.json in '%s'" % abs_bundle)
		return {}
	var state := _GameSaveDataClass.from_dict(parsed as Dictionary)

	# 2. Load fog.png
	var fog_image: Image = null
	var fog_path := abs_bundle.path_join(state.fog_image_path)
	if FileAccess.file_exists(fog_path):
		fog_image = Image.new()
		var img_err := fog_image.load(fog_path)
		if img_err != OK:
			push_error("PersistenceService: failed to load fog.png (err %d)" % img_err)
			fog_image = null

	# 3. Resolve embedded map.map/ path
	var embedded_map := abs_bundle.path_join("map.map")
	if not DirAccess.dir_exists_absolute(embedded_map):
		push_error("PersistenceService: embedded map.map not found in '%s'" % abs_bundle)
		return {}

	return {
		"state": state,
		"fog_image": fog_image,
		"map_bundle_path": embedded_map,
	}


func list_save_bundles() -> Array:
	var out: Array = []
	var abs_dir := _abs(_SAVES_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return out
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir() and fname.ends_with(".sav"):
			out.append(fname.get_basename())
		fname = dir.get_next()
	dir.list_dir_end()
	return out


func delete_save_bundle(save_name: String) -> bool:
	var abs_path := _abs(_SAVES_DIR).path_join(save_name + ".sav")
	if not DirAccess.dir_exists_absolute(abs_path):
		return false
	if not _remove_dir_recursive(abs_path):
		return false
	emit_signal("persistence_changed", save_name)
	return true


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _abs(path: String) -> String:
	## Resolve user:// and res:// paths to absolute OS paths.
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


func _copy_dir_recursive(src_dir: String, dst_dir: String) -> bool:
	var abs_src := _abs(src_dir)
	var abs_dst := _abs(dst_dir)
	DirAccess.make_dir_recursive_absolute(abs_dst)
	var dir := DirAccess.open(abs_src)
	if dir == null:
		return false
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname == "." or fname == "..":
			fname = dir.get_next()
			continue
		var src_path := abs_src.path_join(fname)
		var dst_path := abs_dst.path_join(fname)
		if dir.current_is_dir():
			if not _copy_dir_recursive(src_path, dst_path):
				dir.list_dir_end()
				return false
		else:
			var err := copy_file(src_path, dst_path)
			if err != OK:
				dir.list_dir_end()
				return false
		fname = dir.get_next()
	dir.list_dir_end()
	return true


func _remove_dir_recursive(dir_path: String) -> bool:
	var abs_path := _abs(dir_path)
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname == "." or fname == "..":
			fname = dir.get_next()
			continue
		var full := abs_path.path_join(fname)
		if dir.current_is_dir():
			if not _remove_dir_recursive(full):
				dir.list_dir_end()
				return false
		else:
			var err := DirAccess.remove_absolute(full)
			if err != OK:
				dir.list_dir_end()
				return false
		fname = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(abs_path) == OK
