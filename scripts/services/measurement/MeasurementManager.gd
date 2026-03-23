extends RefCounted
class_name MeasurementManager

# ---------------------------------------------------------------------------
# MeasurementManager — typed coordinator for the measurement domain.
#
# Owned by ServiceRegistry.measurement.  All callers access measurement
# operations through manager methods — never via registry.measurement.service.
# ---------------------------------------------------------------------------

var service: IMeasurementService = null


func add(data: MeasurementData) -> void:
	if service == null:
		return
	service.add_measurement(data)


func remove(id: String) -> void:
	if service == null:
		return
	service.remove_measurement(id)


func move(id: String, new_start: Vector2, new_end: Vector2) -> void:
	if service == null:
		return
	service.move_measurement(id, new_start, new_end)


func update(data: MeasurementData) -> void:
	if service == null:
		return
	service.update_measurement(data)


func load_from_dicts(dicts: Array) -> void:
	if service == null:
		return
	service.load_measurements(dicts)


func clear() -> void:
	if service == null:
		return
	service.clear_measurements()


func get_all() -> Array:
	if service == null:
		return []
	return service.get_all_measurements()


func get_by_id(id: String) -> MeasurementData:
	if service == null:
		return null
	return service.get_measurement_by_id(id)
