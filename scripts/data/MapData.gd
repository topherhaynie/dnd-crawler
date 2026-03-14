extends Resource

# ---------------------------------------------------------------------------
# MapData — serialisable map metadata resource.
#
# Holds everything needed to reconstruct a map session:
#   - source image path
#   - grid type and calibration
#   - viewport pan/zoom state
#   - wall occluder polygon data (painted in Phase 6 editor)
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

# --- Identity --------------------------------------------------------------
var map_name: String = "" ## Display name / filename stem
var image_path: String = "" ## Absolute or project-relative image path

# --- Grid ------------------------------------------------------------------
var grid_type: int = GridType.SQUARE
var cell_px: float = 64.0 ## Pixels per cell (square grids)
var hex_size: float = 40.0 ## Outer radius in pixels (hex grids)
var grid_offset: Vector2 = Vector2.ZERO ## Pixel offset so grid aligns to tiles

# --- Wall data (Phase 6) ---------------------------------------------------
# Each entry is an Array of Vector2-compatible dicts {"x":float,"y":float}
# representing one polygon. Populated by the wall-paint editor in Phase 6.
var wall_polygons: Array = []

# --- Fog data (Phase 4) ----------------------------------------------------
# Fog is stored as hidden grid cells. Revealed cells are absent from this list.
# Each entry serializes as {"x": int, "y": int} cell coordinates.
var fog_cell_px: int = 4
var fog_hidden_cells: Array = []

# --- Map objects (Phase 6) ------------------------------------------------
# Array of serialised MapObject dictionaries placed by DM in editor mode.
# Kept here so save/load round-trips without Phase 6 code loaded.
var map_objects: Array = []

# --- Viewport state (optional, remembered across sessions) -----------------
var camera_position: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0


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
		"fog_hidden_cells": _serialise_fog_cells(fog_hidden_cells),
		"map_objects": map_objects.duplicate(true),
		"camera_position": {"x": camera_position.x, "y": camera_position.y},
		"camera_zoom": camera_zoom,
	}


static func from_dict(d: Dictionary) -> MapData:
	var m := MapData.new()
	m.map_name = d.get("map_name", "")
	m.image_path = d.get("image_path", "")
	m.grid_type = int(d.get("grid_type", GridType.SQUARE))
	m.cell_px = float(d.get("cell_px", 64.0))
	m.hex_size = float(d.get("hex_size", 40.0))
	var go: Dictionary = d.get("grid_offset", {"x": 0.0, "y": 0.0})
	m.grid_offset = Vector2(float(go.get("x", 0.0)), float(go.get("y", 0.0)))
	m.wall_polygons = _deserialise_polygons(d.get("wall_polygons", []))
	m.fog_cell_px = int(d.get("fog_cell_px", 4))
	m.fog_hidden_cells = _deserialise_fog_cells(d.get("fog_hidden_cells", []))
	m.map_objects = d.get("map_objects", []).duplicate(true)
	var cp: Dictionary = d.get("camera_position", {"x": 0.0, "y": 0.0})
	m.camera_position = Vector2(float(cp.get("x", 0.0)), float(cp.get("y", 0.0)))
	m.camera_zoom = float(d.get("camera_zoom", 1.0))
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


static func _serialise_fog_cells(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		if c is Vector2i:
			out.append({"x": c.x, "y": c.y})
		elif c is Dictionary:
			out.append({"x": int(c.get("x", 0)), "y": int(c.get("y", 0))})
	return out


static func _deserialise_fog_cells(raw: Array) -> Array:
	var out: Array = []
	for cell in raw:
		if cell is Vector2i:
			out.append(cell)
		elif cell is Dictionary:
			out.append(Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0))))
	return out


# ---------------------------------------------------------------------------
# Grid helpers (used by GridOverlay and calibration tool)
# ---------------------------------------------------------------------------

func grid_type_name() -> String:
	match grid_type:
		GridType.SQUARE: return "Square"
		GridType.HEX_FLAT: return "Hex (flat-top)"
		GridType.HEX_POINTY: return "Hex (pointy-top)"
	return "Unknown"
