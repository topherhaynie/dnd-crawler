extends Node
class_name IMovementService

# ---------------------------------------------------------------------------
# IMovementService — protocol for the movement / speed domain.
#
# Centralises feet↔pixel conversion, round-duration timing, player walk/dash
# speed, and token roam speed so that all movement consumers share one source
# of truth.
# ---------------------------------------------------------------------------

## Duration of a single D&D round in seconds.  RAW is 6 s but we use a
## shorter value so dungeon-crawl movement feels responsive in real-time.
const ROUND_DURATION_SEC: float = 2.0
## Standard feet per grid cell (5 ft for D&D 5e).
const FEET_PER_CELL: float = 5.0


# --- Conversion helpers ----------------------------------------------------

func feet_to_px(_feet: float, _cell_px: float) -> float:
	push_error("IMovementService.feet_to_px: not implemented")
	return 0.0


func px_to_feet(_px: float, _cell_px: float) -> float:
	push_error("IMovementService.px_to_feet: not implemented")
	return 0.0


## Convert a speed expressed in feet-per-round into pixels-per-second.
func speed_fpr_to_px_per_sec(_speed_fpr: float, _cell_px: float) -> float:
	push_error("IMovementService.speed_fpr_to_px_per_sec: not implemented")
	return 0.0


# --- Player speed ----------------------------------------------------------

## Effective player movement speed in px/s, accounting for base speed and dash.
func get_player_speed_px_per_sec(_profile: PlayerProfile, _map: MapData) -> float:
	push_error("IMovementService.get_player_speed_px_per_sec: not implemented")
	return 0.0


## Return the pixels-per-5-ft calibration value for the given map, accounting
## for grid type (square vs hex).
func pixels_per_5ft(_map: MapData) -> float:
	push_error("IMovementService.pixels_per_5ft: not implemented")
	return 60.0


# --- Token roam speed ------------------------------------------------------

## Effective roam speed for a token in px/s.
func get_roam_speed_px_per_sec(_token: TokenData, _map: MapData) -> float:
	push_error("IMovementService.get_roam_speed_px_per_sec: not implemented")
	return 0.0
