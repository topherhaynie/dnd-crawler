extends RefCounted
class_name GameSaveData

## Serialisable game session data — everything that is NOT the static map.
##
## Stored inside a `.sav` bundle alongside an embedded `.map` copy:
##   my_session.sav/
##     state.json       ← this model serialised via to_dict()
##     fog.png          ← L8 fog history image
##     map.map/         ← full embedded copy of the source .map bundle
##       map.json
##       image.<ext>

# --- Identity ---------------------------------------------------------------
var save_name: String = ""
var map_bundle_path: String = "" ## Original .map path (informational)

# --- Player runtime state ---------------------------------------------------
var player_positions: Dictionary = {} ## {player_id: {"x": float, "y": float}}
var player_locked: Dictionary = {} ## {player_id: bool}

# --- Player camera (DM-controlled viewport shown on player displays) -------
var player_camera_position: Vector2 = Vector2(960.0, 540.0)
var player_camera_zoom: float = 1.0
var player_camera_rotation: int = 0

# --- Fog reference ----------------------------------------------------------
var fog_image_path: String = "fog.png" ## Relative path within .sav bundle

# --- Token runtime state ----------------------------------------------------
## Runtime-toggleable token state keyed by token ID.
## Overrides the initial state loaded from the embedded map bundle on load.
## Format: {"<token_id>": {"is_visible_to_players": bool}}
var token_states: Dictionary = {}

# --- Session profile assignment --------------------------------------------
## IDs of profiles that are active in this save. Empty = no session loaded
## (all profiles behave as active for backward-compatibility).
var active_profile_ids: Array = []

# --- Timestamps -------------------------------------------------------------
var created_at: String = ""
var updated_at: String = ""

# --- Combat state -----------------------------------------------------------
## Serialised CombatState snapshot (initiative order, round, active turn).
## Empty dict when no combat is active.
var combat_state: Dictionary = {}


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var positions_out: Dictionary = {}
	for pid in player_positions.keys():
		var pos: Variant = player_positions[pid]
		if pos is Vector2:
			positions_out[pid] = {"x": (pos as Vector2).x, "y": (pos as Vector2).y}
		elif pos is Dictionary:
			positions_out[pid] = pos

	var locks_out: Dictionary = {}
	for pid in player_locked.keys():
		locks_out[pid] = bool(player_locked[pid])

	return {
		"save_name": save_name,
		"map_bundle_path": map_bundle_path,
		"player_positions": positions_out,
		"player_locked": locks_out,
		"player_camera_position": {
			"x": player_camera_position.x,
			"y": player_camera_position.y,
		},
		"player_camera_zoom": player_camera_zoom,
		"player_camera_rotation": player_camera_rotation,
		"fog_image_path": fog_image_path,
		"token_states": token_states,
		"active_profile_ids": active_profile_ids.duplicate(),
		"created_at": created_at,
		"updated_at": updated_at,
		"combat_state": combat_state,
	}


static func from_dict(d: Dictionary) -> GameSaveData:
	var s := GameSaveData.new()
	s.save_name = str(d.get("save_name", ""))
	s.map_bundle_path = str(d.get("map_bundle_path", ""))

	var raw_pos: Variant = d.get("player_positions", {})
	if raw_pos is Dictionary:
		for pid in (raw_pos as Dictionary).keys():
			var v: Variant = (raw_pos as Dictionary)[pid]
			if v is Dictionary:
				s.player_positions[pid] = Vector2(
					float((v as Dictionary).get("x", 0.0)),
					float((v as Dictionary).get("y", 0.0)),
				)
			else:
				s.player_positions[pid] = Vector2.ZERO

	var raw_lock: Variant = d.get("player_locked", {})
	if raw_lock is Dictionary:
		for pid in (raw_lock as Dictionary).keys():
			s.player_locked[pid] = bool((raw_lock as Dictionary)[pid])

	var cp: Dictionary = d.get("player_camera_position", {"x": 960.0, "y": 540.0})
	s.player_camera_position = Vector2(float(cp.get("x", 960.0)), float(cp.get("y", 540.0)))
	s.player_camera_zoom = float(d.get("player_camera_zoom", 1.0))
	s.player_camera_rotation = int(d.get("player_camera_rotation", 0))
	s.fog_image_path = str(d.get("fog_image_path", "fog.png"))
	var raw_ts: Variant = d.get("token_states", {})
	if raw_ts is Dictionary:
		s.token_states = raw_ts as Dictionary
	var raw_ids: Variant = d.get("active_profile_ids", [])
	if raw_ids is Array:
		for entry in (raw_ids as Array):
			s.active_profile_ids.append(str(entry))
	s.created_at = str(d.get("created_at", ""))
	s.updated_at = str(d.get("updated_at", ""))
	var raw_cs: Variant = d.get("combat_state", {})
	if raw_cs is Dictionary:
		s.combat_state = raw_cs as Dictionary
	return s
