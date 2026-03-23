extends Node
class_name IMeasurementService

# ---------------------------------------------------------------------------
# IMeasurementService — protocol (interface) for the measurement domain.
#
# All public methods are declared here with push_error stubs.
# Concrete implementations must override them.
# Signals are declared here; concrete services must NOT redeclare them.
# ---------------------------------------------------------------------------

# --- Signals ---------------------------------------------------------------
@warning_ignore("unused_signal")
signal measurement_added(data: MeasurementData)
@warning_ignore("unused_signal")
signal measurement_removed(id: String)
@warning_ignore("unused_signal")
signal measurement_moved(id: String, new_start: Vector2, new_end: Vector2)
@warning_ignore("unused_signal")
signal measurement_updated(data: MeasurementData)
@warning_ignore("unused_signal")
signal measurements_reloaded


# --- Mutation --------------------------------------------------------------

func add_measurement(_data: MeasurementData) -> void:
	push_error("IMeasurementService.add_measurement: not implemented")


func remove_measurement(_id: String) -> void:
	push_error("IMeasurementService.remove_measurement: not implemented")


func move_measurement(_id: String, _new_start: Vector2, _new_end: Vector2) -> void:
	push_error("IMeasurementService.move_measurement: not implemented")


func update_measurement(_data: MeasurementData) -> void:
	push_error("IMeasurementService.update_measurement: not implemented")


# --- Bulk ------------------------------------------------------------------

func load_measurements(_dicts: Array) -> void:
	push_error("IMeasurementService.load_measurements: not implemented")


func clear_measurements() -> void:
	push_error("IMeasurementService.clear_measurements: not implemented")


# --- Query -----------------------------------------------------------------

func get_all_measurements() -> Array:
	push_error("IMeasurementService.get_all_measurements: not implemented")
	return []


func get_measurement_by_id(_id: String) -> MeasurementData:
	push_error("IMeasurementService.get_measurement_by_id: not implemented")
	return null
