extends Resource

# ---------------------------------------------------------------------------
# MapData — serialisable map metadata resource.
#
# Holds everything needed to reconstruct a map:
#   - source image path
#   - grid type and calibration
#   - DM editing viewport state (camera_position, camera_zoom)
#   - wall occluder polygon data (painted in Phase 6 editor)
#   - spawn point markers for player initial placement
#
# Runtime session data (player positions, fog, player camera rotation) lives
# in GameSaveData, not here. camera_rotation is kept for backward compat
# on load but is no longer the authoritative source — see GameSaveData.
#
# GridType enum
#   SQUARE    — rectangular grid, calibrated by cell_px (pixels per cell)
#   HEX_FLAT  — flat-top hexagons, calibrated by hex_size (outer radius px)
#   HEX_POINTY— pointy-top hexagons, calibrated by hex_size
#
# JSON round-trip: to_dict() / from_dict() so maps persist in data/maps/.
# ---------------------------------------------------------------------------

class_name MapData

enum GridType {SQUARE, HEX_FLAT, HEX_POINTY}

const SUPPORTED_IMAGE_EXTENSIONS: Array = ["png", "jpg", "jpeg", "webp", "bmp", "tga"]
const SUPPORTED_VIDEO_EXTENSIONS: Array = ["mp4", "m4v", "webm", "avi", "mkv", "mov", "ogv", "ogg"]

# --- Identity --------------------------------------------------------------
var map_name: String = "" ## Display name / filename stem
var image_path: String = "" ## Absolute or project-relative image/video path

# --- Grid ------------------------------------------------------------------
var grid_type: int = GridType.SQUARE
var cell_px: float = 64.0 ## Pixels per cell (square grids)
var hex_size: float = 32.0 ## Outer radius in pixels (hex grids)
var grid_offset: Vector2 = Vector2.ZERO ## Pixel offset so grid aligns to tiles

# --- Wall data (Phase 6) ---------------------------------------------------
# Each entry is an Array of Vector2-compatible dicts {"x":float,"y":float}
# representing one polygon. Populated by the wall-paint editor in Phase 6.
var wall_polygons: Array = []

# --- Fog data (Phase 4) ----------------------------------------------------
# Cell pixel size used by GPU fog seed/delta operations.
var fog_cell_px: int = 4
# Master fog-of-war toggle.  When false the fog overlay is hidden on both
# DM and player views and history accumulation is paused.
var fog_enabled: bool = true

# --- Spawn points ----------------------------------------------------------
# Each entry is a Dictionary: {"x": float, "y": float, "label": String}
# DM places these markers to define where players initially spawn.
# When empty, BackendRuntime falls back to centre-of-map placement.
var spawn_points: Array = []

# --- Map objects (Phase 6) ------------------------------------------------
# Array of serialised MapObject dictionaries placed by DM in editor mode.
# Kept here so save/load round-trips without Phase 6 code loaded.
var map_objects: Array = []

# --- Tokens ---------------------------------------------------------------
# Array of serialised TokenData dictionaries (see TokenData.to_dict()).
# Persisted in map.json so tokens survive map bundle reloads.
var tokens: Array = []

# --- Measurements ---------------------------------------------------------
# Array of serialised MeasurementData dictionaries (see MeasurementData.to_dict()).
# Persisted in map.json so measurement overlays survive map bundle reloads.
var measurements: Array = []

# --- Effects --------------------------------------------------------------
# Array of serialised EffectData dictionaries (see EffectData.to_dict()).
# Persisted in map.json so placed magic effects survive map bundle reloads.
var effects: Array = []

# --- Statblocks -----------------------------------------------------------
# Array of serialised StatblockData dictionaries for map-scoped statblocks.
# Token statblock_refs resolve against this array plus SRD and campaign.
var statblocks: Array = []

# --- Audio (video map backgrounds) -----------------------------------------
var audio_volume_db: float = 0.0 ## Background video volume in dB (0 = full)

# --- Viewport state (optional, remembered across sessions) -----------------
var camera_position: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var camera_rotation: int = 0 ## Map rotation in degrees (0, 90, 180, 270)


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"map_name": map_name,
		"image_path": image_path,
		"grid_type": grid_type,
		"cell_px": cell_px,
		"hex_size": hex_size,
		"grid_offset": {"x": grid_offset.x, "y": grid_offset.y},
		"wall_polygons": _serialise_polygons(wall_polygons),
		"fog_cell_px": fog_cell_px,
		"fog_enabled": fog_enabled,
		"spawn_points": _serialise_points(spawn_points),
		"map_objects": map_objects.duplicate(true),
		"tokens": tokens.duplicate(true),
		"measurements": measurements.duplicate(true),
		"effects": effects.duplicate(true),
		"statblocks": statblocks.duplicate(true),
		"audio_volume_db": audio_volume_db,
		"camera_position": {"x": camera_position.x, "y": camera_position.y},
		"camera_zoom": camera_zoom,
		"camera_rotation": camera_rotation,
	}


static func from_dict(d: Dictionary) -> MapData:
	var m := MapData.new()
	m.map_name = d.get("map_name", "")
	m.image_path = d.get("image_path", "")
	m.grid_type = int(d.get("grid_type", GridType.SQUARE))
	m.cell_px = float(d.get("cell_px", 64.0))
	m.hex_size = float(d.get("hex_size", 32.0))
	var go: Dictionary = d.get("grid_offset", {"x": 0.0, "y": 0.0})
	m.grid_offset = Vector2(float(go.get("x", 0.0)), float(go.get("y", 0.0)))
	m.wall_polygons = _deserialise_polygons(d.get("wall_polygons", []))
	m.fog_cell_px = int(d.get("fog_cell_px", 4))
	m.fog_enabled = bool(d.get("fog_enabled", true))
	m.spawn_points = _deserialise_points(d.get("spawn_points", []))
	m.map_objects = d.get("map_objects", []).duplicate(true)
	m.tokens = d.get("tokens", []).duplicate(true)
	m.measurements = d.get("measurements", []).duplicate(true)
	m.effects = d.get("effects", []).duplicate(true)
	m.statblocks = d.get("statblocks", []).duplicate(true)
	m.audio_volume_db = float(d.get("audio_volume_db", 0.0))
	var cp: Dictionary = d.get("camera_position", {"x": 0.0, "y": 0.0})
	m.camera_position = Vector2(float(cp.get("x", 0.0)), float(cp.get("y", 0.0)))
	m.camera_zoom = float(d.get("camera_zoom", 1.0))
	m.camera_rotation = int(d.get("camera_rotation", 0))
	return m


# --- helpers ---------------------------------------------------------------

static func _serialise_polygons(polys: Array) -> Array:
	var out: Array = []
	for poly in polys:
		var pts: Array = []
		for v in poly:
			pts.append({"x": float(v.x), "y": float(v.y)})
		out.append(pts)
	return out


static func _deserialise_polygons(raw: Array) -> Array:
	var out: Array = []
	for poly in raw:
		var pts: Array = []
		for pt in poly:
			pts.append(Vector2(float(pt.get("x", 0.0)), float(pt.get("y", 0.0))))
		out.append(pts)
	return out


static func _serialise_points(pts: Array) -> Array:
	var out: Array = []
	for pt in pts:
		if pt is Dictionary:
			out.append(pt.duplicate())
		elif pt is Vector2:
			out.append({"x": float((pt as Vector2).x), "y": float((pt as Vector2).y), "label": ""})
	return out


static func _deserialise_points(raw: Array) -> Array:
	var out: Array = []
	for pt in raw:
		if pt is Dictionary:
			out.append({
				"x": float(pt.get("x", 0.0)),
				"y": float(pt.get("y", 0.0)),
				"label": str(pt.get("label", "")),
			})
	return out


# ---------------------------------------------------------------------------
# Grid helpers (used by GridOverlay and calibration tool)
# ---------------------------------------------------------------------------

func is_video() -> bool:
	## Returns true when image_path refers to a video file rather than a static image.
	var ext: String = image_path.get_extension().to_lower()
	return ext in SUPPORTED_VIDEO_EXTENSIONS


func grid_type_name() -> String:
	match grid_type:
		GridType.SQUARE: return "Square"
		GridType.HEX_FLAT: return "Hex (flat-top)"
		GridType.HEX_POINTY: return "Hex (pointy-top)"
	return "Unknown"
