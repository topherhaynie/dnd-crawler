extends IMeasurementService
class_name MeasurementService

# ---------------------------------------------------------------------------
# MeasurementService — concrete measurement domain service.
#
# Owns the canonical in-memory measurement collection (_measurements: Dictionary).
# All state mutations go through this service; callers receive change
# notifications via the signals declared in IMeasurementService.
# ---------------------------------------------------------------------------

## id (String) → MeasurementData
var _measurements: Dictionary = {}


# ---------------------------------------------------------------------------
# Mutation
# ---------------------------------------------------------------------------

func add_measurement(data: MeasurementData) -> void:
	if data == null or data.id.is_empty():
		push_error("MeasurementService.add_measurement: data is null or has empty id")
		return
	_measurements[data.id] = data
	measurement_added.emit(data)


func remove_measurement(id: String) -> void:
	if not _measurements.has(id):
		return
	_measurements.erase(id)
	measurement_removed.emit(id)


func move_measurement(id: String, new_start: Vector2, new_end: Vector2) -> void:
	var data: MeasurementData = _measurements.get(id, null) as MeasurementData
	if data == null:
		return
	data.world_start = new_start
	data.world_end = new_end
	measurement_moved.emit(id, new_start, new_end)


func update_measurement(data: MeasurementData) -> void:
	if data == null or data.id.is_empty():
		push_error("MeasurementService.update_measurement: data is null or has empty id")
		return
	_measurements[data.id] = data
	measurement_updated.emit(data)


# ---------------------------------------------------------------------------
# Bulk
# ---------------------------------------------------------------------------

func load_measurements(dicts: Array) -> void:
	_measurements.clear()
	for raw in dicts:
		if raw is Dictionary:
			var m: MeasurementData = MeasurementData.from_dict(raw as Dictionary)
			_measurements[m.id] = m
	measurements_reloaded.emit()


func clear_measurements() -> void:
	_measurements.clear()
	measurements_reloaded.emit()


# ---------------------------------------------------------------------------
# Query
# ---------------------------------------------------------------------------

func get_all_measurements() -> Array:
	return _measurements.values()


func get_measurement_by_id(id: String) -> MeasurementData:
	return _measurements.get(id, null) as MeasurementData
