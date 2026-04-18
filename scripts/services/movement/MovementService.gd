extends IMovementService
class_name MovementService

# ---------------------------------------------------------------------------
# MovementService — concrete implementation of the movement / speed domain.
# ---------------------------------------------------------------------------


# --- Conversion helpers ----------------------------------------------------

func feet_to_px(feet: float, cell_px: float) -> float:
	return feet / FEET_PER_CELL * cell_px


func px_to_feet(px: float, cell_px: float) -> float:
	if cell_px <= 0.0:
		return 0.0
	return px / cell_px * FEET_PER_CELL


func speed_fpr_to_px_per_sec(speed_fpr: float, cell_px: float) -> float:
	return feet_to_px(speed_fpr, cell_px) / ROUND_DURATION_SEC


# --- Player speed ----------------------------------------------------------

func get_player_speed_px_per_sec(profile: PlayerProfile, map: MapData) -> float:
	var cell_px: float = pixels_per_5ft(map)
	var speed: float = speed_fpr_to_px_per_sec(maxf(profile.get_speed(), 5.0), cell_px)
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.input != null and registry.input.is_dashing(profile.id):
		speed *= 2.0
	return speed


func pixels_per_5ft(map: MapData) -> float:
	if map == null:
		return 60.0
	return map.cell_px if map.grid_type == MapData.GridType.SQUARE else map.hex_size * 2.0


# --- Token roam speed ------------------------------------------------------

func get_roam_speed_px_per_sec(token: TokenData, map: MapData) -> float:
	return speed_fpr_to_px_per_sec(token.roam_speed, pixels_per_5ft(map))
