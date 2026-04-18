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
# Optional back-reference to a campaign image ID this icon was sourced from.
# Metadata only — rendering uses icon_image_path directly.
var icon_campaign_image_id: String = ""
# Creature space in feet (D&D 5e: 5 = Medium, 10 = Large, etc.).
# Controls the player token's rendered diameter on the map.
var size_ft: float = 5.0
# Optional ID of a StatblockData character linked to this profile.
# When set, get_passive_perception() and get_speed() prefer the statblock's
# computed values over the manually-typed profile fields.
var statblock_id: String = ""
# Future-proof payload for custom fields (status effects, inventory, etc.)
var extras: Dictionary = {}


func ensure_id() -> void:
	if id.is_empty():
		id = _generate_id()


func get_passive_perception() -> int:
	var sb: StatblockData = _resolve_statblock()
	if sb != null:
		var pp: Variant = sb.senses.get("passive_perception", null)
		if pp != null:
			return int(pp)
	return 10 + perception_mod


func get_speed() -> float:
	var sb: StatblockData = _resolve_statblock()
	if sb != null:
		var walk: Variant = sb.speed.get("walk", "")
		var walk_str: String = str(walk).strip_edges()
		if not walk_str.is_empty():
			# Parse "30 ft." or plain "30"
			var num: String = walk_str.split(" ")[0]
			if num.is_valid_float():
				return float(num)
	return base_speed


## Return the effective vision type from the linked statblock, or the profile field.
func get_vision_type() -> int:
	var sb: StatblockData = _resolve_statblock()
	if sb != null:
		var dv: Variant = sb.senses.get("darkvision", "")
		if not str(dv).is_empty():
			return VisionType.DARKVISION
	return vision_type


## Return the effective darkvision range from the linked statblock, or the profile field.
func get_darkvision_range() -> float:
	var sb: StatblockData = _resolve_statblock()
	if sb != null:
		var dv: String = str(sb.senses.get("darkvision", ""))
		if not dv.is_empty():
			var num: String = dv.split(" ")[0]
			if num.is_valid_float():
				return float(num)
	return darkvision_range


## Return the effective creature size from the linked statblock, or the profile field.
func get_size_ft() -> float:
	var sb: StatblockData = _resolve_statblock()
	if sb != null and not sb.size.is_empty():
		var ft: float = StatblockData.size_to_feet(sb.size)
		if ft > 0.0:
			return ft
	return size_ft


## Resolve the linked character statblock, if any.
func _resolve_statblock() -> StatblockData:
	if statblock_id.is_empty():
		return null
	var main_loop: Variant = Engine.get_main_loop()
	if main_loop == null:
		return null
	var tree: SceneTree = main_loop as SceneTree
	if tree == null:
		return null
	var reg: ServiceRegistry = tree.root.get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.character == null:
		return null
	return reg.character.get_character_by_id(statblock_id)


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
		"icon_campaign_image_id": icon_campaign_image_id,
		"size_ft": size_ft,
		"statblock_id": statblock_id,
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
	p.icon_campaign_image_id = str(d.get("icon_campaign_image_id", ""))
	p.size_ft = float(d.get("size_ft", 5.0))
	p.statblock_id = str(d.get("statblock_id", ""))

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
			"icon_campaign_image_id",
			"size_ft",
			"statblock_id",
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
