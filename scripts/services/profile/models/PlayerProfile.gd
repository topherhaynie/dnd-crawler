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
# Relative path to a custom icon image (e.g. "profile_icons/<id>.png").
# Stored under user://data/. Empty = no custom image.
var icon_image_path: String = ""
# Absolute filesystem path to the original source image for re-cropping.
var icon_source_path: String = ""
# Crop editor state for the icon image.
var icon_crop_offset: Vector2 = Vector2.ZERO
var icon_crop_zoom: float = 1.0
# Forward-facing direction of the icon in degrees (0 = right, 90 = down, etc.).
var icon_facing_deg: float = 0.0
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
		"icon_image_path": icon_image_path,
		"icon_source_path": icon_source_path,
		"icon_crop_offset": {"x": icon_crop_offset.x, "y": icon_crop_offset.y},
		"icon_crop_zoom": icon_crop_zoom,
		"icon_facing_deg": icon_facing_deg,
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
	p.icon_image_path = str(d.get("icon_image_path", ""))
	p.icon_source_path = str(d.get("icon_source_path", ""))
	var ico: Variant = d.get("icon_crop_offset", {"x": 0.0, "y": 0.0})
	if ico is Dictionary:
		var icd := ico as Dictionary
		p.icon_crop_offset = Vector2(float(icd.get("x", 0.0)), float(icd.get("y", 0.0)))
	p.icon_crop_zoom = float(d.get("icon_crop_zoom", 1.0))
	p.icon_facing_deg = float(d.get("icon_facing_deg", 0.0))

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
			"icon_image_path",
			"icon_source_path",
			"icon_crop_offset",
			"icon_crop_zoom",
			"icon_facing_deg",
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
