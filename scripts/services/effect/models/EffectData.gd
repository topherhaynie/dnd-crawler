extends RefCounted
class_name EffectData

# ---------------------------------------------------------------------------
# EffectData — serialisable model for a single DM-placed magic effect.
#
# Effects are procedural shader-driven visual overlays placed on the map
# by the DM. They can be one-shot (play once, then auto-remove) or looping
# (persist until manually dismissed).
#
# JSON round-trip: to_dict() / from_dict().
# ---------------------------------------------------------------------------

enum EffectType {
	FIRE = 0,
	LIGHTNING_BOLT = 1,
	LIGHTNING_BOLT_WILD = 2,
	LIGHTNING_BALL = 3,
	FROST = 4,
	BLIZZARD = 5,
	POISON_CLOUD = 6,
	HOLY_RADIANCE = 7,
	MAGIC_AURA = 8,
}

enum EffectShape {
	CIRCLE = 0,
	LINE = 1,
	CONE = 2,
}

const EFFECT_LABELS: Array[String] = [
	"Fire",
	"Lightning Bolt",
	"Lightning Bolt (Wild)",
	"Lightning Ball",
	"Frost",
	"Blizzard",
	"Poison Cloud",
	"Holy Radiance",
	"Magic Aura",
]

const SHAPE_LABELS: Array[String] = ["Circle", "Line", "Cone"]

## Which shapes are available for each effect type.
## Key = EffectType value, Value = Array[int] of EffectShape values.
const AVAILABLE_SHAPES: Dictionary = {
	0: [0, 2], # Fire: Circle, Cone
	1: [0, 1], # Lightning Bolt: Circle, Line
	2: [0, 1], # Lightning Bolt (Wild): Circle, Line
	3: [0], # Lightning Ball: Circle only
	4: [0, 2], # Frost: Circle, Cone
	5: [0, 2], # Blizzard: Circle, Cone
	6: [0, 2], # Poison Cloud: Circle, Cone
	7: [0, 2], # Holy Radiance: Circle, Cone
	8: [0, 2], # Magic Aura: Circle, Cone
}

# --- Identity --------------------------------------------------------------
var id: String = ""

# --- Geometry --------------------------------------------------------------
var effect_type: int = EffectType.FIRE
var shape: int = EffectShape.CIRCLE
var world_pos: Vector2 = Vector2.ZERO
var world_end: Vector2 = Vector2.ZERO ## Second point for LINE (end) and CONE (tip direction).
var size_px: float = 96.0 ## Circle: diameter. Line: width. Cone: unused (length = drag).
var rotation_deg: float = 0.0

# --- Timing ----------------------------------------------------------------
## Duration in seconds for one-shot effects. Negative means looping (no auto-remove).
var duration_sec: float = -1.0

# --- Appearance ------------------------------------------------------------
var color_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
var intensity: float = 1.0


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

static func generate_id() -> String:
	return "%d_%d" % [Time.get_ticks_msec(), randi()]


static func create(type: int, pos: Vector2, size: float = 96.0, duration: float = -1.0) -> EffectData:
	var e := EffectData.new()
	e.id = generate_id()
	e.effect_type = type
	e.world_pos = pos
	e.size_px = size
	e.duration_sec = duration
	return e


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": id,
		"effect_type": effect_type,
		"shape": shape,
		"world_pos": {"x": world_pos.x, "y": world_pos.y},
		"world_end": {"x": world_end.x, "y": world_end.y},
		"size_px": size_px,
		"rotation_deg": rotation_deg,
		"duration_sec": duration_sec,
		"color_tint": {"r": color_tint.r, "g": color_tint.g, "b": color_tint.b, "a": color_tint.a},
		"intensity": intensity,
	}


static func from_dict(d: Dictionary) -> EffectData:
	var e := EffectData.new()
	e.id = str(d.get("id", EffectData.generate_id()))
	e.effect_type = int(d.get("effect_type", EffectType.FIRE))
	e.shape = int(d.get("shape", EffectShape.CIRCLE))
	var wp: Dictionary = d.get("world_pos", {"x": 0.0, "y": 0.0})
	e.world_pos = Vector2(float(wp.get("x", 0.0)), float(wp.get("y", 0.0)))
	var we: Dictionary = d.get("world_end", {"x": 0.0, "y": 0.0})
	e.world_end = Vector2(float(we.get("x", 0.0)), float(we.get("y", 0.0)))
	e.size_px = float(d.get("size_px", 96.0))
	e.rotation_deg = float(d.get("rotation_deg", 0.0))
	e.duration_sec = float(d.get("duration_sec", -1.0))
	var ct: Dictionary = d.get("color_tint", {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0})
	e.color_tint = Color(
		float(ct.get("r", 1.0)),
		float(ct.get("g", 1.0)),
		float(ct.get("b", 1.0)),
		float(ct.get("a", 1.0)))
	e.intensity = float(d.get("intensity", 1.0))
	return e
