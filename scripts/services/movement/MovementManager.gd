extends RefCounted
class_name MovementManager

# ---------------------------------------------------------------------------
# MovementManager — typed coordinator for the movement / speed domain.
#
# Owned by ServiceRegistry.movement.  All callers access movement operations
# through manager methods — never via registry.movement.service directly.
# ---------------------------------------------------------------------------

var service: IMovementService = null


func feet_to_px(feet: float, cell_px: float) -> float:
	if service == null:
		return 0.0
	return service.feet_to_px(feet, cell_px)


func px_to_feet(px: float, cell_px: float) -> float:
	if service == null:
		return 0.0
	return service.px_to_feet(px, cell_px)


func speed_fpr_to_px_per_sec(speed_fpr: float, cell_px: float) -> float:
	if service == null:
		return 0.0
	return service.speed_fpr_to_px_per_sec(speed_fpr, cell_px)


func get_player_speed_px_per_sec(profile: PlayerProfile, map: MapData) -> float:
	if service == null:
		return 0.0
	return service.get_player_speed_px_per_sec(profile, map)


func pixels_per_5ft(map: MapData) -> float:
	if service == null:
		return 60.0
	return service.pixels_per_5ft(map)


func get_roam_speed_px_per_sec(token: TokenData, map: MapData) -> float:
	if service == null:
		return 0.0
	return service.get_roam_speed_px_per_sec(token, map)
