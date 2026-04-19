extends RefCounted
class_name BundleIO

## BundleIO — transparent ZIP / directory bundle I/O utility.
##
## .map and .sav bundles are stored as ZIP archives on disk so they appear as
## regular files to OS file dialogs on every platform.  When opened at runtime
## the contents are extracted to a cache directory; all existing code works with
## the extracted directory.  On save the cache directory is packed back to ZIP.
##
## Legacy directory bundles (pre-ZIP era) are read transparently — any
## directory with a `.map` or `.sav` extension is treated as a valid bundle.

const _CACHE_ROOT: String = "user://data/_cache"


# ---------------------------------------------------------------------------
# Format detection
# ---------------------------------------------------------------------------

static func is_zip(path: String) -> bool:
	## True when *path* is a regular file (assumed ZIP) — not a directory.
	var abs_path: String = _abs(path)
	return FileAccess.file_exists(abs_path) and not DirAccess.dir_exists_absolute(abs_path)


static func is_dir_bundle(path: String) -> bool:
	## True when *path* is a directory bundle (legacy format).
	return DirAccess.dir_exists_absolute(_abs(path))


static func bundle_exists(path: String) -> bool:
	## True when a bundle exists at *path* as either a ZIP file or directory.
	var abs_path: String = _abs(path)
	return FileAccess.file_exists(abs_path) or DirAccess.dir_exists_absolute(abs_path)


# ---------------------------------------------------------------------------
# Open — extract ZIP to cache, or return existing dir as-is
# ---------------------------------------------------------------------------

static func open_bundle(bundle_path: String) -> String:
	## If *bundle_path* is a ZIP, extract it to a cache directory and return the
	## cache path.  If it is already a directory, return it unchanged.
	## Returns "" on failure.
	var abs_path: String = _abs(bundle_path)
	if DirAccess.dir_exists_absolute(abs_path):
		return abs_path # legacy directory bundle — use directly

	if not FileAccess.file_exists(abs_path):
		Log.error("BundleIO", "bundle not found: %s" % abs_path)
		return ""

	var cache_dir: String = _cache_dir_for(abs_path)
	# Skip extraction if cache already exists and is newer than the ZIP.
	if DirAccess.dir_exists_absolute(cache_dir):
		var zip_mtime: int = FileAccess.get_modified_time(abs_path)
		var marker: String = cache_dir.path_join(".bundle_mtime")
		if FileAccess.file_exists(marker):
			var fa := FileAccess.open(marker, FileAccess.READ)
			if fa != null:
				var cached_mtime: int = fa.get_as_text().strip_edges().to_int()
				fa.close()
				if cached_mtime >= zip_mtime:
					return cache_dir
		# Cache is stale — remove it and re-extract.
		_remove_dir_recursive(cache_dir)

	if not _extract_zip(abs_path, cache_dir):
		return ""

	# Write mtime marker so we can skip re-extraction next time.
	var mtime_file := FileAccess.open(cache_dir.path_join(".bundle_mtime"), FileAccess.WRITE)
	if mtime_file != null:
		mtime_file.store_string(str(FileAccess.get_modified_time(abs_path)))
		mtime_file.close()

	return cache_dir


# ---------------------------------------------------------------------------
# Save — pack a working directory into a ZIP archive
# ---------------------------------------------------------------------------

static func save_bundle(work_dir: String, zip_path: String) -> Error:
	## Pack *work_dir* into a ZIP archive at *zip_path*.
	## An existing file at *zip_path* is overwritten atomically.
	var abs_dir: String = _abs(work_dir)
	var abs_zip: String = _abs(zip_path)

	# Ensure parent directory exists.
	var parent: String = abs_zip.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)

	# Write to a temp file first, then rename for atomicity.
	var tmp_zip: String = abs_zip + ".tmp"
	var packer := ZIPPacker.new()
	var err: Error = packer.open(tmp_zip)
	if err != OK:
		Log.error("BundleIO", "cannot create ZIP '%s' (err %d)" % [tmp_zip, err])
		return err

	err = _pack_dir(packer, abs_dir, "")
	if err != OK:
		packer.close()
		DirAccess.remove_absolute(tmp_zip)
		return err

	err = packer.close()
	if err != OK:
		DirAccess.remove_absolute(tmp_zip)
		return err

	# Atomic replace: remove old ZIP (or placeholder file), rename tmp.
	if FileAccess.file_exists(abs_zip) and not DirAccess.dir_exists_absolute(abs_zip):
		DirAccess.remove_absolute(abs_zip)
	var rename_err: Error = DirAccess.rename_absolute(tmp_zip, abs_zip)
	if rename_err != OK:
		Log.error("BundleIO", "rename '%s' → '%s' failed (err %d)" % [tmp_zip, abs_zip, rename_err])
		DirAccess.remove_absolute(tmp_zip)
		return rename_err

	# Update cache mtime marker so open_bundle() won't re-extract.
	var cache_dir: String = _cache_dir_for(abs_zip)
	if DirAccess.dir_exists_absolute(cache_dir):
		var marker := FileAccess.open(cache_dir.path_join(".bundle_mtime"), FileAccess.WRITE)
		if marker != null:
			marker.store_string(str(FileAccess.get_modified_time(abs_zip)))
			marker.close()

	return OK


# ---------------------------------------------------------------------------
# Direct read helpers (no full extraction needed)
# ---------------------------------------------------------------------------

static func read_text(bundle_path: String, inner_path: String) -> String:
	## Read a text file from inside a bundle (ZIP or directory).
	var data: PackedByteArray = read_bytes(bundle_path, inner_path)
	if data.is_empty():
		return ""
	return data.get_string_from_utf8()


static func read_bytes(bundle_path: String, inner_path: String) -> PackedByteArray:
	## Read raw bytes from inside a bundle (ZIP or directory).
	var abs_path: String = _abs(bundle_path)

	if DirAccess.dir_exists_absolute(abs_path):
		# Directory bundle — read file directly.
		var file_path: String = abs_path.path_join(inner_path)
		var fa := FileAccess.open(file_path, FileAccess.READ)
		if fa == null:
			return PackedByteArray()
		var buf: PackedByteArray = fa.get_buffer(fa.get_length())
		fa.close()
		return buf

	# ZIP bundle.
	if not FileAccess.file_exists(abs_path):
		return PackedByteArray()
	var reader := ZIPReader.new()
	if reader.open(abs_path) != OK:
		return PackedByteArray()
	var files: PackedStringArray = reader.get_files()
	# Normalise inner_path slashes for comparison.
	var target: String = inner_path.replace("\\", "/")
	var zip_buf: PackedByteArray = PackedByteArray()
	if target in files:
		zip_buf = reader.read_file(target)
	reader.close()
	return zip_buf


# ---------------------------------------------------------------------------
# Listing bundles in a directory (ZIP files + legacy directories)
# ---------------------------------------------------------------------------

static func list_bundles(parent_dir: String, extension: String) -> PackedStringArray:
	## List bundle base-names under *parent_dir* that have the given extension.
	## Recognises both ZIP files and legacy directories.
	## Returns base-names (e.g. "my_map" for "my_map.map").
	var abs_dir: String = _abs(parent_dir)
	var out: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(abs_dir):
		return out

	var ext_dot: String = "." + extension # e.g. ".map"
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(ext_dot):
			if dir.current_is_dir():
				out.append(fname.get_basename())
			elif not dir.current_is_dir():
				# Regular file — assume ZIP bundle.
				out.append(fname.get_basename())
		fname = dir.get_next()
	dir.list_dir_end()
	return out


# ---------------------------------------------------------------------------
# Bundle deletion (ZIP or directory)
# ---------------------------------------------------------------------------

static func delete_bundle(bundle_path: String) -> bool:
	## Delete a bundle at the given path (ZIP file or directory).
	## Also removes any corresponding cache directory.
	var abs_path: String = _abs(bundle_path)
	var ok: bool = false
	if DirAccess.dir_exists_absolute(abs_path):
		ok = _remove_dir_recursive(abs_path)
	elif FileAccess.file_exists(abs_path):
		ok = DirAccess.remove_absolute(abs_path) == OK
	# Remove cache dir too.
	var cache: String = _cache_dir_for(abs_path)
	if DirAccess.dir_exists_absolute(cache):
		_remove_dir_recursive(cache)
	return ok


# ---------------------------------------------------------------------------
# Cache management
# ---------------------------------------------------------------------------

static func clear_cache() -> void:
	## Delete the entire bundle cache tree.
	var abs_root: String = _abs(_CACHE_ROOT)
	if DirAccess.dir_exists_absolute(abs_root):
		_remove_dir_recursive(abs_root)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _abs(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


static func _cache_dir_for(abs_zip_path: String) -> String:
	## Derive a cache directory path from a ZIP path.
	## e.g. /data/maps/my_map.map → <cache_root>/maps/my_map.map/
	var cache_abs: String = _abs(_CACHE_ROOT)
	# Determine the bundle type from the parent dir name.
	var parent_name: String = abs_zip_path.get_base_dir().get_file()
	var bundle_name: String = abs_zip_path.get_file()
	return cache_abs.path_join(parent_name).path_join(bundle_name)


static func _extract_zip(abs_zip: String, dest_dir: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(abs_zip) != OK:
		Log.error("BundleIO", "cannot open ZIP '%s'" % abs_zip)
		return false
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var files: PackedStringArray = reader.get_files()
	for file_path: String in files:
		# Skip directory entries (they end with /).
		if file_path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(dest_dir.path_join(file_path))
			continue
		var data: PackedByteArray = reader.read_file(file_path)
		var dest_file: String = dest_dir.path_join(file_path)
		var parent: String = dest_file.get_base_dir()
		if not DirAccess.dir_exists_absolute(parent):
			DirAccess.make_dir_recursive_absolute(parent)
		var fa := FileAccess.open(dest_file, FileAccess.WRITE)
		if fa == null:
			Log.error("BundleIO", "cannot write '%s'" % dest_file)
			reader.close()
			return false
		fa.store_buffer(data)
		fa.close()
	reader.close()
	return true


static func _pack_dir(packer: ZIPPacker, abs_dir: String, prefix: String) -> Error:
	## Recursively add all files from *abs_dir* into the packer with *prefix*.
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return ERR_CANT_OPEN
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname == "." or fname == ".." or fname == ".bundle_mtime":
			fname = dir.get_next()
			continue
		var full_path: String = abs_dir.path_join(fname)
		var zip_path: String = (prefix + fname) if prefix.is_empty() else (prefix + "/" + fname)
		if dir.current_is_dir():
			var err: Error = _pack_dir(packer, full_path, zip_path)
			if err != OK:
				dir.list_dir_end()
				return err
		else:
			var fa := FileAccess.open(full_path, FileAccess.READ)
			if fa == null:
				dir.list_dir_end()
				return ERR_FILE_CANT_OPEN
			var data: PackedByteArray = fa.get_buffer(fa.get_length())
			fa.close()
			packer.start_file(zip_path)
			packer.write_file(data)
			packer.close_file()
		fname = dir.get_next()
	dir.list_dir_end()
	return OK


static func _remove_dir_recursive(dir_path: String) -> bool:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname == "." or fname == "..":
			fname = dir.get_next()
			continue
		var full: String = dir_path.path_join(fname)
		if dir.current_is_dir():
			if not _remove_dir_recursive(full):
				dir.list_dir_end()
				return false
		else:
			if DirAccess.remove_absolute(full) != OK:
				dir.list_dir_end()
				return false
		fname = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(dir_path) == OK
