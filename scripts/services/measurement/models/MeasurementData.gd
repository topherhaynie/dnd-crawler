extends RefCounted
class_name MeasurementData

# ---------------------------------------------------------------------------
# MeasurementData — serialisable model for a single DM-placed measurement.
#
# Measurements are geometric overlays (line, circle, cone, square, rectangle)
# drawn by the DM or players to communicate distances and areas on the map.
# They are always visible to players and persist in the map bundle.
#
# Geometry encoding:
#   LINE      — world_start/world_end are the two endpoints
#   CIRCLE    — world_start is the centre; world_end defines the radius
#                 (radius_px = world_start.distance_to(world_end))
#   CONE      — world_start is the apex; world_end is the tip-direction point
#                 D&D 5e RAW: width = length at the open end (half-angle ≈ 26.6°)
#   SQUARE    — world_start is one corner; world_end is the opposite corner
#                 rotation encoded by angle of world_start→world_end diagonal
#   RECTANGLE — world_start is anchor corner; world_end is the drag end
#                 extra_value stores the width-perpendicular half-extent in px
#
# JSON round-trip: to_dict() / from_dict().
# ---------------------------------------------------------------------------

enum ShapeType {
	LINE = 0,
	CIRCLE = 1,
	CONE = 2,
	SQUARE = 3,
	RECTANGLE = 4,
}

# --- Identity --------------------------------------------------------------
var id: String = ""

# --- Geometry --------------------------------------------------------------
var shape_type: int = ShapeType.LINE
var world_start: Vector2 = Vector2.ZERO
var world_end: Vector2 = Vector2.ZERO
## General-purpose scalar; meaning depends on shape_type.
## RECTANGLE: perpendicular half-width in world-space pixels.
## All other shapes: unused (0).
var extra_value: float = 0.0

# --- Appearance -----------------------------------------------------------
## Stroke colour; default white. Stored for future colour-picker support.
var color: Color = Color(1.0, 1.0, 1.0, 0.85)


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

static func generate_id() -> String:
	return "%d_%d" % [Time.get_ticks_msec(), randi()]


static func create(type: int, start: Vector2, end: Vector2, extra: float = 0.0) -> MeasurementData:
	var m := MeasurementData.new()
	m.id = generate_id()
	m.shape_type = type
	m.world_start = start
	m.world_end = end
	m.extra_value = extra
	return m


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": id,
		"shape_type": shape_type,
		"world_start": {"x": world_start.x, "y": world_start.y},
		"world_end": {"x": world_end.x, "y": world_end.y},
		"extra_value": extra_value,
		"color": {"r": color.r, "g": color.g, "b": color.b, "a": color.a},
	}


static func from_dict(d: Dictionary) -> MeasurementData:
	var m := MeasurementData.new()
	m.id = str(d.get("id", MeasurementData.generate_id()))
	m.shape_type = int(d.get("shape_type", ShapeType.LINE))
	var ws: Dictionary = d.get("world_start", {"x": 0.0, "y": 0.0})
	m.world_start = Vector2(float(ws.get("x", 0.0)), float(ws.get("y", 0.0)))
	var we: Dictionary = d.get("world_end", {"x": 0.0, "y": 0.0})
	m.world_end = Vector2(float(we.get("x", 0.0)), float(we.get("y", 0.0)))
	m.extra_value = float(d.get("extra_value", 0.0))
	var cd: Dictionary = d.get("color", {"r": 1.0, "g": 1.0, "b": 1.0, "a": 0.85})
	m.color = Color(
		float(cd.get("r", 1.0)),
		float(cd.get("g", 1.0)),
		float(cd.get("b", 1.0)),
		float(cd.get("a", 0.85)))
	return m
