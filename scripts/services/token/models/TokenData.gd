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
## Runtime-only autopause trigger count. NOT serialised.
@warning_ignore("unused_private_class_variable")
var _trigger_count: int = 0

# --- Notes ----------------------------------------------------------------
## Free-form DM notes attached to this token.
var notes: String = ""

# --- Appearance -----------------------------------------------------------
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

# --- Passage geometry (SECRET_PASSAGE category only) ---------------------
## Array of polyline chains defining the passage corridor geometry.
## Each element is a PackedVector2Array of world-space points.
## Supports branching: multiple chains can share endpoints (junctions).
var passage_paths: Array = []
## Half-width of the rendered corridor in world-space pixels.
var passage_width_px: float = 48.0


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
		"width_px": width_px,
		"height_px": height_px,
		"rotation_deg": rotation_deg,
		"icon_key": icon_key,
		"token_shape": token_shape,
		"blocks_los": blocks_los,
		"trigger_radius_px": trigger_radius_px,
		"autopause_max_triggers": autopause_max_triggers,
		"passage_paths": _serialize_passage_paths(),
		"passage_width_px": passage_width_px,
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
	var _compat_diam: float = float(d.get("diameter_px", 48.0))
	t.width_px = float(d.get("width_px", _compat_diam))
	t.height_px = float(d.get("height_px", _compat_diam))
	t.rotation_deg = float(d.get("rotation_deg", 0.0))
	t.icon_key = str(d.get("icon_key", ""))
	t.token_shape = int(d.get("token_shape", TokenShape.ELLIPSE))
	t.blocks_los = bool(d.get("blocks_los", true))
	t.trigger_radius_px = float(d.get("trigger_radius_px", 96.0))
	t.autopause_max_triggers = int(d.get("autopause_max_triggers", 0))
	t.passage_width_px = float(d.get("passage_width_px", 48.0))
	t.passage_paths = _deserialize_passage_paths(d)
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
