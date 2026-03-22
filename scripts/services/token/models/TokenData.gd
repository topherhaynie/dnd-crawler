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
## When false, wall polygons overlapping this token's bounding rect are
## excluded from LOS/fog occluder construction. Only meaningful for DOOR
## and SECRET_PASSAGE categories. Defaults true so existing maps are unaffected.
var blocks_los: bool = true

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
		"notes": notes,
		"width_px": width_px,
		"height_px": height_px,
		"rotation_deg": rotation_deg,
		"icon_key": icon_key,
		"token_shape": token_shape,
		"blocks_los": blocks_los,
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
	t.notes = str(d.get("notes", ""))
	var _compat_diam: float = float(d.get("diameter_px", 48.0))
	t.width_px = float(d.get("width_px", _compat_diam))
	t.height_px = float(d.get("height_px", _compat_diam))
	t.rotation_deg = float(d.get("rotation_deg", 0.0))
	t.icon_key = str(d.get("icon_key", ""))
	t.token_shape = int(d.get("token_shape", TokenShape.ELLIPSE))
	t.blocks_los = bool(d.get("blocks_los", true))
	return t


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
