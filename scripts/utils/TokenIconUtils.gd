extends RefCounted
class_name TokenIconUtils

# ---------------------------------------------------------------------------
# TokenIconUtils — static utility for token/profile icon image processing.
#
# Handles: load from disk, centre-crop, resize, circular alpha mask,
# base64 encode/decode for network transfer, and shared texture caching.
#
# Stored PNGs are 256×256 *square* crops (no circular mask on disk) so the
# crop editor can re-open with full corner data.  The circular alpha mask is
# applied at texture-creation time for rendering.
# ---------------------------------------------------------------------------

## Maximum pixel dimension for stored icon images.
const MAX_ICON_SIZE: int = 256

## Supported image file extensions (lowercase, no dot).
static var SUPPORTED_EXTENSIONS: PackedStringArray = PackedStringArray(["png", "jpg", "jpeg", "webp"])

## FileDialog filter string for the image picker.
static var FILE_DIALOG_FILTERS: PackedStringArray = PackedStringArray([
	"*.png, *.jpg, *.jpeg, *.webp ; Image files",
])

# --- Shared texture caches (static) ----------------------------------------

## Textures loaded from local file paths, keyed by absolute path.
## Populated lazily on first draw; evicted on icon change or map unload.
static var _texture_cache: Dictionary = {}

## Textures decoded from network base64, keyed by CRC32 hash of the b64 string.
## Evicted on disconnect or map unload.
static var _net_cache: Dictionary = {}

## DM-side base64 encode cache — avoids re-reading files on every broadcast.
## Keyed by absolute path; evicted when the icon changes.
static var _b64_cache: Dictionary = {}


# ---------------------------------------------------------------------------
# Image loading
# ---------------------------------------------------------------------------

## Load an image from an absolute filesystem path or user:// path.
## Returns null on failure (unsupported format, missing file, etc.).
static func load_image_from_path(path: String) -> Image:
	if path.is_empty():
		return null
	var ext: String = path.get_extension().to_lower()
	if ext not in SUPPORTED_EXTENSIONS:
		push_error("TokenIconUtils: unsupported image format '%s'" % ext)
		return null
	var img := Image.new()
	var err: Error = img.load(path)
	if err != OK:
		push_error("TokenIconUtils: failed to load image '%s' (error %d)" % [path, err])
		return null
	return img


# ---------------------------------------------------------------------------
# Image processing pipeline
# ---------------------------------------------------------------------------

## Crop an image to the largest centred square.
static func center_crop_to_square(img: Image) -> Image:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w == h:
		return img
	var side: int = mini(w, h)
	@warning_ignore("integer_division")
	var x0: int = (w - side) / 2
	@warning_ignore("integer_division")
	var y0: int = (h - side) / 2
	return img.get_region(Rect2i(x0, y0, side, side))


## Crop with offset and zoom.  offset is how many pixels the user has panned
## the source image (in source-pixel space) from the default auto-centre.
## zoom > 1 means the source is enlarged (tighter crop), < 1 is invalid.
static func crop_with_params(img: Image, offset: Vector2, zoom: float) -> Image:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var side: int = mini(w, h)
	# Effective crop size in source pixels (zoom > 1 = smaller region = tighter).
	var crop_size: int = maxi(1, int(float(side) / maxf(zoom, 0.01)))
	# Default centre of the crop region.
	var cx: float = float(w) * 0.5 + offset.x
	var cy: float = float(h) * 0.5 + offset.y
	# Clamp so the crop region stays inside the image.
	var half: float = float(crop_size) * 0.5
	var x0: int = clampi(int(cx - half), 0, maxi(0, w - crop_size))
	var y0: int = clampi(int(cy - half), 0, maxi(0, h - crop_size))
	return img.get_region(Rect2i(x0, y0, crop_size, crop_size))


## Downscale an image so both dimensions are ≤ max_size.
## Does nothing if already within limits.
static func resize_to_max(img: Image, max_size: int) -> Image:
	if img.get_width() <= max_size and img.get_height() <= max_size:
		return img
	img.resize(max_size, max_size, Image.INTERPOLATE_LANCZOS)
	return img


## Apply a circular alpha mask to a *square* image.  Pixels outside the
## inscribed circle become fully transparent.  A 1-pixel anti-aliased edge
## is applied for smooth rendering.
static func apply_circular_alpha_mask(img: Image) -> Image:
	var size: int = img.get_width()
	var center := Vector2(float(size) * 0.5, float(size) * 0.5)
	var radius: float = float(size) * 0.5
	# Ensure we have an alpha channel.
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var dist: float = center.distance_to(Vector2(float(x) + 0.5, float(y) + 0.5))
			if dist > radius:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			elif dist > radius - 1.0:
				# Anti-aliased edge: blend existing alpha with distance falloff.
				var edge_alpha: float = clampf(radius - dist, 0.0, 1.0)
				var c: Color = img.get_pixel(x, y)
				c.a *= edge_alpha
				img.set_pixel(x, y, c)
	return img


## Full pipeline: load from path → auto-centre-crop → resize → circular mask → ImageTexture.
## Returns null on failure.
static func create_circular_texture_from_path(path: String) -> ImageTexture:
	var img: Image = load_image_from_path(path)
	if img == null:
		return null
	return create_circular_texture(img)


## Convert an already-loaded Image into a circular ImageTexture (crop → resize → mask).
static func create_circular_texture(img: Image) -> ImageTexture:
	img = center_crop_to_square(img)
	img = resize_to_max(img, MAX_ICON_SIZE)
	img = apply_circular_alpha_mask(img)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Disk persistence
# ---------------------------------------------------------------------------

## Full import pipeline: load source → crop (with params) → resize to 256×256 → save PNG.
## The saved file is a *square* PNG (no circular mask) to preserve crop-edit data.
## Returns OK on success.
static func process_and_save_icon(
	source_path: String,
	dest_path: String,
	crop_offset: Vector2 = Vector2.ZERO,
	crop_zoom: float = 1.0,
) -> Error:
	var img: Image = load_image_from_path(source_path)
	if img == null:
		return ERR_FILE_CANT_OPEN
	# Crop with editor params (default = auto-centre).
	if crop_offset != Vector2.ZERO or crop_zoom != 1.0:
		img = crop_with_params(img, crop_offset, crop_zoom)
	else:
		img = center_crop_to_square(img)
	img = resize_to_max(img, MAX_ICON_SIZE)
	# Ensure dest directory exists.
	var parent_dir: String = dest_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_dir):
		DirAccess.make_dir_recursive_absolute(parent_dir)
	return img.save_png(dest_path)


## Delete an icon file from disk.  Used when changing or clearing profile/token icons.
static func delete_icon_file(path: String) -> void:
	if path.is_empty():
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Base64 encode / decode for network transfer
# ---------------------------------------------------------------------------

## Read a PNG file from disk and return its bytes as a base64 string.
## Returns empty string on failure.
static func encode_icon_to_b64(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var cached: Variant = _b64_cache.get(path, null)
	if cached is String:
		return cached as String
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var raw: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	var b64: String = Marshalls.raw_to_base64(raw)
	if not b64.is_empty():
		_b64_cache[path] = b64
	return b64


## Decode a base64 PNG string into a circular-masked ImageTexture.
## Returns null on failure.
static func decode_b64_to_texture(b64: String) -> ImageTexture:
	if b64.is_empty():
		return null
	var raw: PackedByteArray = Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		return null
	var img := Image.new()
	var err: Error = img.load_png_from_buffer(raw)
	if err != OK:
		# Try JPEG if PNG fails.
		err = img.load_jpg_from_buffer(raw)
		if err != OK:
			err = img.load_webp_from_buffer(raw)
			if err != OK:
				push_error("TokenIconUtils: failed to decode icon from base64")
				return null
	return create_circular_texture(img)


# ---------------------------------------------------------------------------
# Shared texture cache — local file paths
# ---------------------------------------------------------------------------

## Get a circular texture for a local file path, loading lazily on first access.
## Multiple callers sharing the same path get the same ImageTexture instance.
static func get_or_load_circular_texture(abs_path: String) -> ImageTexture:
	if abs_path.is_empty():
		return null
	var cached: Variant = _texture_cache.get(abs_path, null)
	if cached is ImageTexture:
		return cached as ImageTexture
	var tex: ImageTexture = create_circular_texture_from_path(abs_path)
	if tex != null:
		_texture_cache[abs_path] = tex
	return tex


## Remove a single entry from the file-path cache (e.g. when the icon changes).
static func evict(abs_path: String) -> void:
	_texture_cache.erase(abs_path)
	_b64_cache.erase(abs_path)


## Flush the entire file-path cache (e.g. on map unload).
static func clear_cache() -> void:
	_texture_cache.clear()
	_b64_cache.clear()


# ---------------------------------------------------------------------------
# Shared texture cache — network (base64)
# ---------------------------------------------------------------------------

## Get or decode a circular texture from a base64 string using CRC32 caching.
## Avoids redundant decode on every state update if the image hasn't changed.
static func get_or_decode_network_texture(b64: String) -> ImageTexture:
	if b64.is_empty():
		return null
	var crc: int = b64.hash()
	var cached: Variant = _net_cache.get(crc, null)
	if cached is ImageTexture:
		return cached as ImageTexture
	var tex: ImageTexture = decode_b64_to_texture(b64)
	if tex != null:
		_net_cache[crc] = tex
	return tex


## Flush the network texture cache (e.g. on disconnect or map unload).
static func clear_network_cache() -> void:
	_net_cache.clear()
