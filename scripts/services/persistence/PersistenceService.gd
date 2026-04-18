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
const _MAPS_DIR: String = "user://data/maps"
const _THUMBNAIL_MAX := Vector2i(400, 300)
const _SUPPORTED_IMG_EXT: Array = ["png", "jpg", "jpeg", "webp", "bmp", "tga"]

var _ffmpeg_available_cached: int = -1 # -1 = unchecked, 0 = no, 1 = yes


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
# Map bundle enumeration & metadata
# ---------------------------------------------------------------------------

func list_map_bundles() -> Array:
	var out: Array = []
	var abs_dir := _abs(_MAPS_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return out
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir() and fname.ends_with(".map"):
			out.append(fname.get_basename())
		fname = dir.get_next()
	dir.list_dir_end()
	return out


func load_bundle_metadata(bundle_path: String) -> Dictionary:
	## Returns {name, modified_time, thumbnail_path, bundle_path} for a .map or .sav bundle.
	var abs_bundle := _abs(bundle_path)
	var result: Dictionary = {
		"name": abs_bundle.get_file().get_basename(),
		"modified_time": 0,
		"thumbnail_path": "",
		"bundle_path": abs_bundle,
	}

	# Resolve modified time from the bundle directory
	var json_path: String = ""
	if abs_bundle.ends_with(".map"):
		json_path = abs_bundle.path_join("map.json")
	elif abs_bundle.ends_with(".sav"):
		json_path = abs_bundle.path_join("state.json")
	if not json_path.is_empty() and FileAccess.file_exists(json_path):
		result["modified_time"] = FileAccess.get_modified_time(json_path)

	# Read name from JSON metadata
	if not json_path.is_empty() and FileAccess.file_exists(json_path):
		var fa := FileAccess.open(json_path, FileAccess.READ)
		if fa != null:
			var text := fa.get_as_text()
			fa.close()
			var parsed: Variant = JsonUtilsScript.parse_json_text(text)
			if parsed is Dictionary:
				var d: Dictionary = parsed as Dictionary
				if d.has("map_name") and d["map_name"] is String:
					result["name"] = d["map_name"] as String
				elif d.has("save_name") and d["save_name"] is String:
					result["name"] = d["save_name"] as String

	# Thumbnail path
	var thumb := abs_bundle.path_join("thumbnail.png")
	if FileAccess.file_exists(thumb):
		result["thumbnail_path"] = thumb

	return result


func generate_thumbnail(image_path: String, dest_path: String, max_size: Vector2i = _THUMBNAIL_MAX) -> bool:
	## Load an image, scale it down to fit within max_size, and save as PNG.
	var img := Image.new()
	var err := img.load(image_path)
	if err != OK:
		push_error("PersistenceService.generate_thumbnail: failed to load '%s' (err %d)" % [image_path, err])
		return false
	# Calculate scale to fit within max_size preserving aspect ratio
	var src_w: float = float(img.get_width())
	var src_h: float = float(img.get_height())
	if src_w <= 0.0 or src_h <= 0.0:
		return false
	var scale_factor: float = minf(float(max_size.x) / src_w, float(max_size.y) / src_h)
	if scale_factor < 1.0:
		var new_w: int = maxi(1, roundi(src_w * scale_factor))
		var new_h: int = maxi(1, roundi(src_h * scale_factor))
		img.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)
	var save_err := img.save_png(dest_path)
	if save_err != OK:
		push_error("PersistenceService.generate_thumbnail: failed to save '%s' (err %d)" % [dest_path, save_err])
		return false
	return true


# ---------------------------------------------------------------------------
# Video conversion (ffmpeg CLI)
# ---------------------------------------------------------------------------

var _ffmpeg_path_cached: String = ""
var _ffprobe_path_cached: String = ""


func _resolve_ffmpeg_path() -> String:
	## Return the absolute path to an ffmpeg binary.  Checks the app bundle
	## first (shipped with the release), then falls back to the system PATH.
	if not _ffmpeg_path_cached.is_empty():
		return _ffmpeg_path_cached
	var bundled := _bundled_tool_path("ffmpeg")
	if not bundled.is_empty():
		_ffmpeg_path_cached = bundled
		return bundled
	# Fallback: system PATH
	var output: Array = []
	if OS.execute("ffmpeg", ["-version"], output, true) == 0:
		_ffmpeg_path_cached = "ffmpeg"
		return "ffmpeg"
	return ""


func _resolve_ffprobe_path() -> String:
	## Return the absolute path to an ffprobe binary.
	if not _ffprobe_path_cached.is_empty():
		return _ffprobe_path_cached
	var bundled := _bundled_tool_path("ffprobe")
	if not bundled.is_empty():
		_ffprobe_path_cached = bundled
		return bundled
	var output: Array = []
	if OS.execute("ffprobe", ["-version"], output, true) == 0:
		_ffprobe_path_cached = "ffprobe"
		return "ffprobe"
	return ""


func _bundled_tool_path(tool_name: String) -> String:
	## Look for a bundled binary next to the executable (release builds),
	## inside the .app Frameworks directory (macOS releases), or in the
	## project's .cache directory (dev builds running from the editor).
	var exe_path := OS.get_executable_path()
	if exe_path.is_empty():
		return ""
	var candidates: Array[String] = []
	match OS.get_name():
		"macOS":
			# Inside .app: Contents/MacOS/<exe> → Contents/Frameworks/<tool>
			var macos_dir := exe_path.get_base_dir()
			var contents_dir := macos_dir.get_base_dir()
			candidates.append(contents_dir.path_join("Frameworks").path_join(tool_name))
			# Also check next to the executable directly (dev builds)
			candidates.append(macos_dir.path_join(tool_name))
			# Project .cache (for dev: same dir build_macos.sh downloads to)
			var project_dir := ProjectSettings.globalize_path("res://")
			candidates.append(project_dir.path_join(".cache/ffmpeg-macos").path_join(tool_name))
		"Windows":
			var suffix := ".exe"
			var exe_dir := exe_path.get_base_dir()
			candidates.append(exe_dir.path_join(tool_name + suffix))
			var project_dir := ProjectSettings.globalize_path("res://")
			candidates.append(project_dir.path_join(".cache/ffmpeg-windows").path_join(tool_name + suffix))
		_:
			var exe_dir := exe_path.get_base_dir()
			candidates.append(exe_dir.path_join(tool_name))
	for candidate: String in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func is_ffmpeg_available() -> bool:
	## Check whether ffmpeg is reachable (bundled or system).
	if _ffmpeg_available_cached >= 0:
		return _ffmpeg_available_cached == 1
	var path := _resolve_ffmpeg_path()
	_ffmpeg_available_cached = 1 if not path.is_empty() else 0
	return _ffmpeg_available_cached == 1


func convert_video_to_ogv(
	src_path: String,
	dest_path: String,
	progress_file: String = "",
	max_width: int = 1920,
	fps: int = 30,
	video_quality: int = 6,
	audio_quality: int = 4,
) -> int:
	## Convert a video file to OGV (Theora + Vorbis) via bundled/system ffmpeg.
	## If progress_file is non-empty, ffmpeg writes machine-readable progress
	## info there (poll for out_time_us to track completion).
	## max_width: 0 = original, otherwise cap to this width.
	## fps: 0 = original, otherwise cap framerate.
	## video_quality: libtheora -q:v (0–10, higher = better).
	## audio_quality: libvorbis -q:a (0–10, higher = better).
	## Returns 0 on success, non-zero on failure.
	var ff := _resolve_ffmpeg_path()
	if ff.is_empty():
		push_error("PersistenceService.convert_video_to_ogv: ffmpeg not found")
		return -1
	var parent_dir := dest_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_dir):
		DirAccess.make_dir_recursive_absolute(parent_dir)
	var args: PackedStringArray = [
		"-hwaccel", "auto",
		"-i", src_path,
	]
	if max_width > 0:
		args.append_array(["-vf", "scale='min(%d,iw)':-2" % max_width])
	if fps > 0:
		args.append_array(["-r", str(fps)])
	args.append_array([
		"-c:v", "libtheora", "-q:v", str(clampi(video_quality, 0, 10)),
		"-c:a", "libvorbis", "-q:a", str(clampi(audio_quality, 0, 10)),
	])
	if not progress_file.is_empty():
		args.append_array(["-progress", progress_file])
	args.append_array(["-y", dest_path])
	Log.info("PersistenceService", "running %s %s" % [ff, " ".join(args)])
	var output: Array = []
	var exit_code: int = OS.execute(ff, args, output, true)
	if exit_code != 0:
		var stderr_text: String = "\n".join(output.map(func(v: Variant) -> String: return str(v)))
		push_error("PersistenceService.convert_video_to_ogv: ffmpeg exited %d\n%s" % [exit_code, stderr_text])
	return exit_code


func probe_video_duration(path: String) -> float:
	## Use ffprobe to extract the total duration in seconds.
	var fp := _resolve_ffprobe_path()
	if fp.is_empty():
		return 0.0
	var output: Array = []
	var exit_code: int = OS.execute(fp, [
		"-v", "error",
		"-show_entries", "format=duration",
		"-of", "csv=p=0",
		path
	], output, true)
	if exit_code != 0 or output.is_empty():
		return 0.0
	var line: String = str(output[0]).strip_edges()
	return line.to_float()


func probe_video_dimensions(path: String) -> Vector2i:
	## Use ffprobe to extract the video stream dimensions.
	var fp := _resolve_ffprobe_path()
	if fp.is_empty():
		push_error("PersistenceService.probe_video_dimensions: ffprobe not found")
		return Vector2i.ZERO
	var output: Array = []
	var exit_code: int = OS.execute(fp, [
		"-v", "error",
		"-select_streams", "v:0",
		"-show_entries", "stream=width,height",
		"-of", "csv=p=0",
		path
	], output, true)
	if exit_code != 0 or output.is_empty():
		push_error("PersistenceService.probe_video_dimensions: ffprobe failed (exit %d)" % exit_code)
		return Vector2i.ZERO
	var line: String = str(output[0]).strip_edges()
	var parts: PackedStringArray = line.split(",")
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func generate_video_thumbnail(src_video: String, dest_png: String, max_size: Vector2i = _THUMBNAIL_MAX) -> bool:
	## Extract a frame near the start of a video and save as a resized PNG thumbnail.
	var ff := _resolve_ffmpeg_path()
	if ff.is_empty():
		push_error("PersistenceService.generate_video_thumbnail: ffmpeg not found")
		return false
	var tmp_path := dest_png + ".tmp.png"
	var output: Array = []
	var exit_code: int = OS.execute(ff, [
		"-i", src_video,
		"-ss", "00:00:01",
		"-frames:v", "1",
		"-y", tmp_path
	], output, true)
	if exit_code != 0 or not FileAccess.file_exists(tmp_path):
		# Fallback: try frame 0 (video shorter than 1 second)
		exit_code = OS.execute(ff, [
			"-i", src_video,
			"-frames:v", "1",
			"-y", tmp_path
		], output, true)
	if exit_code != 0 or not FileAccess.file_exists(tmp_path):
		push_error("PersistenceService.generate_video_thumbnail: ffmpeg frame extract failed")
		return false
	var ok := generate_thumbnail(tmp_path, dest_png, max_size)
	DirAccess.remove_absolute(tmp_path)
	return ok


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
