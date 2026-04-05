extends RefCounted
class_name TokenData

# ---------------------------------------------------------------------------
# TokenData — serialisable model for a single DM-placed map token.
#
# Tokens are things the DM places on the map: doors, traps, hidden objects,
# secret passages, monsters, NPCs, events, or generic markers.
#
# Stored in map.json as part of MapData.tokens (Array of plain dicts).
# JSON round-trip: to_dict() / from_dict().
# ---------------------------------------------------------------------------

enum TokenCategory {
	DOOR,
	TRAP,
	HIDDEN_OBJECT,
	SECRET_PASSAGE,
	MONSTER,
	EVENT,
	NPC,
	GENERIC,
}

enum TokenShape {
	ELLIPSE = 0,
	RECTANGLE = 1,
}

# --- Identity --------------------------------------------------------------
var id: String = "" ## Unique token ID; generated on creation
var label: String = "" ## Display name shown on the DM map

# --- Placement -------------------------------------------------------------
var category: int = TokenCategory.GENERIC ## TokenCategory enum value
var world_pos: Vector2 = Vector2.ZERO ## World-space centre position

# --- Visibility -----------------------------------------------------------
## When false the token is hidden from players (DM sees it at reduced alpha).
var is_visible_to_players: bool = false
## Perception DC required to auto-reveal this token when a player is nearby.
## -1 means the token can only be revealed by the DM manually toggling visibility.
var perception_dc: int = -1

# --- Interaction ----------------------------------------------------------
## Pause the session when the player camera enters this token's proximity.
var autopause: bool = false
## Pause the session when a player interacts with (clicks) this token.
var pause_on_interact: bool = false
## When true, meeting the perception DC auto-reveals this token to players.
## When false, meeting the DC only produces a detection indicator ("!").
var auto_reveal: bool = false
## When false, wall polygons overlapping this token's bounding rect are
## excluded from LOS/fog occluder construction. Only meaningful for DOOR
## and SECRET_PASSAGE categories. Defaults true so existing maps are unaffected.
var blocks_los: bool = true
## World-space radius (in pixels) for proximity triggers: autopause,
## pause-on-interact, and perception auto-reveal. Authored in feet via the
## token editor and converted to pixels on save using calibrated cell_px.
var trigger_radius_px: float = 96.0
## Maximum number of times an autopause trigger fires for this token.
## 0 = unlimited. Decremented at runtime by TokenService.
var autopause_max_triggers: int = 0
## When true, autopause only fires when a player overlaps the token’s body
## (collision) rather than when they enter trigger_radius_px.  This lets
## perception checks still use the larger radius while autopause requires
## actually stepping onto the token.  Defaults true for TRAP tokens.
var autopause_on_collision: bool = false
## Runtime-only autopause trigger count. NOT serialised.
@warning_ignore("unused_private_class_variable")
var _trigger_count: int = 0

# --- Notes ----------------------------------------------------------------
## Free-form DM notes attached to this token.
var notes: String = ""
## Ordered puzzle hints the DM can progressively reveal to players.
## Each element is a Dictionary: {"text": String, "revealed": bool}.
var puzzle_notes: Array = []

# --- Appearance -----------------------------------------------------------
## Creature space in feet (D&D 5e: 5 = Medium, 10 = Large, etc.).
## When > 0, width_px/height_px are derived from calibration.
## 0 = manual pixel sizing (doors, traps, passages, etc.).
var size_ft: float = 0.0
## Rendered size of the token in world-space pixels.
## 48 = one standard grid cell at 1:1 zoom.
var width_px: float = 48.0
var height_px: float = 48.0
## Rotation of the token around its centre, in degrees.
var rotation_deg: float = 0.0
## Key used to look up a sprite frame or icon resource path.
## Empty string = use the category default colour placeholder.
var icon_key: String = ""
## Rendering shape: ELLIPSE (0) or RECTANGLE (1). Defaults ELLIPSE for
## backwards compat; RECTANGLE is recommended for doors/passages.
var token_shape: int = TokenShape.ELLIPSE
## Relative path to a custom icon image inside the .map bundle
## (e.g. "token_icons/<id>.png"). Empty = no custom image.
var icon_image_path: String = ""
## Absolute filesystem path to the original source image used to create the
## icon.  Preserved so re-cropping operates on the full-resolution original
## rather than the 256×256 saved crop.  Empty = source unknown / legacy.
var icon_source_path: String = ""
## Crop editor state: pixel offset of the source image centre under the crop
## circle. Zero = auto-centred.
var icon_crop_offset: Vector2 = Vector2.ZERO
## Crop editor state: zoom factor applied before cropping. 1.0 = fit-to-circle.
var icon_crop_zoom: float = 1.0
## Direction the icon image faces, in degrees (0 = right, 90 = down).
## Used to correct rotation during movement so the image faces forward.
var icon_facing_deg: float = 0.0

# --- Passage geometry (SECRET_PASSAGE category only) ---------------------
## Array of polyline chains defining the passage corridor geometry.
## Each element is a PackedVector2Array of world-space points.
## Supports branching: multiple chains can share endpoints (junctions).
var passage_paths: Array = []
## Half-width of the rendered corridor in world-space pixels.
var passage_width_px: float = 48.0

# --- Roam path (MONSTER / NPC categories) ---------------------------------
## World-space waypoints defining the token's patrol / roam path.
var roam_path: PackedVector2Array = PackedVector2Array()
## Movement speed along the roam path, in feet per round.
var roam_speed: float = 30.0
## When true the token loops back to the start; when false it ping-pongs.
var roam_loop: bool = true


# ---------------------------------------------------------------------------
# Factory helpers
# ---------------------------------------------------------------------------

## Generate a token ID that is unique within a session.
static func generate_id() -> String:
	return "%d_%d" % [Time.get_ticks_msec(), randi()]


static func create(category_val: int, pos: Vector2, lbl: String = "") -> TokenData:
	var t := TokenData.new()
	t.id = generate_id()
	t.category = category_val
	t.world_pos = pos
	t.label = lbl
	if category_val == TokenCategory.MONSTER or category_val == TokenCategory.NPC:
		t.size_ft = 5.0
	return t


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": id,
		"label": label,
		"category": category,
		"world_pos": {"x": world_pos.x, "y": world_pos.y},
		"is_visible_to_players": is_visible_to_players,
		"perception_dc": perception_dc,
		"autopause": autopause,
		"pause_on_interact": pause_on_interact,
		"auto_reveal": auto_reveal,
		"notes": notes,
		"size_ft": size_ft,
		"width_px": width_px,
		"height_px": height_px,
		"rotation_deg": rotation_deg,
		"icon_key": icon_key,
		"token_shape": token_shape,
		"blocks_los": blocks_los,
		"trigger_radius_px": trigger_radius_px,
		"autopause_max_triggers": autopause_max_triggers,
		"autopause_on_collision": autopause_on_collision,
		"passage_paths": _serialize_passage_paths(),
		"passage_width_px": passage_width_px,
		"roam_path": _serialize_roam_path(),
		"roam_speed": roam_speed,
		"roam_loop": roam_loop,
		"puzzle_notes": _serialize_puzzle_notes(),
		"icon_image_path": icon_image_path,
		"icon_source_path": icon_source_path,
		"icon_crop_offset": {"x": icon_crop_offset.x, "y": icon_crop_offset.y},
		"icon_crop_zoom": icon_crop_zoom,
		"icon_facing_deg": icon_facing_deg,
	}


static func from_dict(d: Dictionary) -> TokenData:
	var t := TokenData.new()
	t.id = str(d.get("id", TokenData.generate_id()))
	t.label = str(d.get("label", ""))
	t.category = int(d.get("category", TokenCategory.GENERIC))
	var wp: Variant = d.get("world_pos", {"x": 0.0, "y": 0.0})
	if wp is Dictionary:
		var wpd := wp as Dictionary
		t.world_pos = Vector2(float(wpd.get("x", 0.0)), float(wpd.get("y", 0.0)))
	t.is_visible_to_players = bool(d.get("is_visible_to_players", false))
	t.perception_dc = int(d.get("perception_dc", -1))
	t.autopause = bool(d.get("autopause", false))
	t.pause_on_interact = bool(d.get("pause_on_interact", false))
	t.auto_reveal = bool(d.get("auto_reveal", false))
	t.notes = str(d.get("notes", ""))
	t.size_ft = float(d.get("size_ft", 0.0))
	var _compat_diam: float = float(d.get("diameter_px", 48.0))
	t.width_px = float(d.get("width_px", _compat_diam))
	t.height_px = float(d.get("height_px", _compat_diam))
	t.rotation_deg = float(d.get("rotation_deg", 0.0))
	t.icon_key = str(d.get("icon_key", ""))
	t.token_shape = int(d.get("token_shape", TokenShape.ELLIPSE))
	t.blocks_los = bool(d.get("blocks_los", true))
	t.trigger_radius_px = float(d.get("trigger_radius_px", 96.0))
	t.autopause_max_triggers = int(d.get("autopause_max_triggers", 0))
	t.autopause_on_collision = bool(d.get("autopause_on_collision", false))
	t.passage_width_px = float(d.get("passage_width_px", 48.0))
	t.passage_paths = _deserialize_passage_paths(d)
	t.roam_path = _deserialize_roam_path(d)
	t.roam_speed = float(d.get("roam_speed", 30.0))
	t.roam_loop = bool(d.get("roam_loop", true))
	t.puzzle_notes = _deserialize_puzzle_notes(d)
	t.icon_image_path = str(d.get("icon_image_path", ""))
	t.icon_source_path = str(d.get("icon_source_path", ""))
	var ico: Variant = d.get("icon_crop_offset", {"x": 0.0, "y": 0.0})
	if ico is Dictionary:
		var icd := ico as Dictionary
		t.icon_crop_offset = Vector2(float(icd.get("x", 0.0)), float(icd.get("y", 0.0)))
	t.icon_crop_zoom = float(d.get("icon_crop_zoom", 1.0))
	t.icon_facing_deg = float(d.get("icon_facing_deg", 0.0))
	return t


## Serialise passage_paths to a JSON-safe Array[Array[{x,y}]].
func _serialize_passage_paths() -> Array:
	var result: Array = []
	for raw in passage_paths:
		var chain: PackedVector2Array
		if raw is PackedVector2Array:
			chain = raw as PackedVector2Array
		else:
			continue
		var pts: Array = []
		for v: Vector2 in chain:
			pts.append({"x": v.x, "y": v.y})
		result.append(pts)
	return result


## Deserialise passage_paths from a dict, including backwards-compat for old
## "passage_path" key (flat Array[{x,y}] → wrapped as single-element array).
static func _deserialize_passage_paths(d: Dictionary) -> Array:
	var result: Array = []
	# Backwards-compat: old single-chain key
	if not d.has("passage_paths") and d.has("passage_path"):
		var old_raw: Variant = d.get("passage_path", [])
		if old_raw is Array:
			var chain := _pts_array_to_packed(old_raw as Array)
			if chain.size() > 0:
				result.append(chain)
		return result
	var raw_paths: Variant = d.get("passage_paths", [])
	if not raw_paths is Array:
		return result
	for raw_chain: Variant in raw_paths as Array:
		if not raw_chain is Array:
			continue
		var chain := _pts_array_to_packed(raw_chain as Array)
		if chain.size() > 0:
			result.append(chain)
	return result


static func _pts_array_to_packed(pts: Array) -> PackedVector2Array:
	var chain := PackedVector2Array()
	for raw_pt: Variant in pts:
		if not raw_pt is Dictionary:
			continue
		var pt := raw_pt as Dictionary
		chain.append(Vector2(float(pt.get("x", 0.0)), float(pt.get("y", 0.0))))
	return chain


## Serialise roam_path to a JSON-safe Array[{x,y}].
func _serialize_roam_path() -> Array:
	var result: Array = []
	for v: Vector2 in roam_path:
		result.append({"x": v.x, "y": v.y})
	return result


## Deserialise roam_path from a dict.
static func _deserialize_roam_path(d: Dictionary) -> PackedVector2Array:
	var raw: Variant = d.get("roam_path", [])
	if not raw is Array:
		return PackedVector2Array()
	return _pts_array_to_packed(raw as Array)


## Serialise puzzle_notes to a JSON-safe Array[{text, revealed}].
func _serialize_puzzle_notes() -> Array:
	var result: Array = []
	for raw: Variant in puzzle_notes:
		if raw is Dictionary:
			var d := raw as Dictionary
			result.append({"text": str(d.get("text", "")), "revealed": bool(d.get("revealed", false))})
	return result


## Deserialise puzzle_notes from a dict, returns empty array for old maps.
static func _deserialize_puzzle_notes(d: Dictionary) -> Array:
	var result: Array = []
	var raw: Variant = d.get("puzzle_notes", [])
	if not raw is Array:
		return result
	for entry: Variant in raw as Array:
		if not entry is Dictionary:
			continue
		var ed := entry as Dictionary
		result.append({"text": str(ed.get("text", "")), "revealed": bool(ed.get("revealed", false))})
	return result


## Human-readable category name for UI labels.
static func category_name(cat: int) -> String:
	match cat:
		TokenCategory.DOOR: return "Door"
		TokenCategory.TRAP: return "Trap"
		TokenCategory.HIDDEN_OBJECT: return "Hidden Object"
		TokenCategory.SECRET_PASSAGE: return "Secret Passage"
		TokenCategory.MONSTER: return "Monster"
		TokenCategory.EVENT: return "Event"
		TokenCategory.NPC: return "NPC"
		_: return "Generic"
