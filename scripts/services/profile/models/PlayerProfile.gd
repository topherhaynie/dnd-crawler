extends Resource
class_name PlayerProfile

# ---------------------------------------------------------------------------
# PlayerProfile — persistent player identity + movement/input metadata.
#
# Design goals (Phase 3):
#   - Stable typed core fields for gameplay and input routing.
#   - Extensible extras dictionary for future attributes with no schema refactor.
# ---------------------------------------------------------------------------

enum VisionType {NORMAL, DARKVISION}
enum InputType {NONE, GAMEPAD, WEBSOCKET}


var id: String = ""
var player_name: String = "New Player"
var base_speed: float = 30.0
var vision_type: int = VisionType.NORMAL
var darkvision_range: float = 60.0
var perception_mod: int = 0
var input_id: String = ""
var input_type: int = InputType.NONE
# Table orientation in degrees (0 = default, 90 = right, 180 = top, 270 = left)
var table_orientation: int = 0
# Indicator color shown on the DM freeze panel and token overlay.
var indicator_color: Color = Color.WHITE
# Future-proof payload for custom fields (status effects, inventory, etc.)
var extras: Dictionary = {}


func ensure_id() -> void:
	if id.is_empty():
		id = _generate_id()


func get_passive_perception() -> int:
	return 10 + perception_mod


func to_dict() -> Dictionary:
	ensure_id()
	return {
		"id": id,
		"player_name": player_name,
		"base_speed": base_speed,
		"vision_type": vision_type,
		"darkvision_range": darkvision_range,
		"perception_mod": perception_mod,
		"passive_perception": get_passive_perception(),
		"input_id": input_id,
		"input_type": input_type,
		"table_orientation": table_orientation,
		"indicator_color": indicator_color.to_html(false),
		"extras": extras.duplicate(true),
	}


static func from_dict(d: Dictionary) -> PlayerProfile:
	var p := new()
	p.id = str(d.get("id", ""))
	p.player_name = str(d.get("player_name", "New Player"))
	p.base_speed = float(d.get("base_speed", 30.0))
	p.vision_type = int(d.get("vision_type", VisionType.NORMAL))
	p.darkvision_range = float(d.get("darkvision_range", 60.0))
	p.perception_mod = int(d.get("perception_mod", 0))
	p.input_id = str(d.get("input_id", ""))
	p.input_type = int(d.get("input_type", InputType.NONE))
	p.table_orientation = int(d.get("table_orientation", 0))
	var color_raw: Variant = d.get("indicator_color", "ffffff")
	p.indicator_color = Color.html(str(color_raw)) if (str(color_raw).length() >= 6) else Color.WHITE

	# Keep explicit extras, then absorb unknown top-level keys so future schema
	# additions survive load/save even before code knows about them.
	var ext: Dictionary = {}
	if d.has("extras") and d["extras"] is Dictionary:
		ext = (d["extras"] as Dictionary).duplicate(true)
	for key in d.keys():
		if key in [
			"id",
			"player_name",
			"base_speed",
			"vision_type",
			"darkvision_range",
			"perception_mod",
			"passive_perception",
			"input_id",
			"input_type",
			"table_orientation",
			"indicator_color",
			"extras",
		]:
			continue
		ext[key] = d[key]
	p.extras = ext
	p.ensure_id()
	return p


static func _generate_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%d-%08x%08x" % [Time.get_unix_time_from_system(), rng.randi(), rng.randi()]
