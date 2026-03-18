extends RefCounted
class_name IFogService

"""
Protocol: IFogService

Methods:
- func reveal_area(pos: Vector2, radius: float) -> void
- func set_fog_enabled(enabled: bool) -> void
- func get_fog_state() -> PackedByteArray
- func get_fog_state_size() -> Vector2i
- func set_fog_state(data: PackedByteArray) -> bool

Signals:
- signal fog_updated(state: Dictionary)

Notes:
- Protocol files should remain minimal (signatures only).
"""

signal fog_updated(state: Dictionary)

func reveal_area(_pos: Vector2, _radius: float) -> void:
	pass

func set_fog_enabled(_enabled: bool) -> void:
	pass

func get_fog_state() -> PackedByteArray:
	return PackedByteArray()

func get_fog_state_size() -> Vector2i:
	return Vector2i.ZERO

func set_fog_state(_data: PackedByteArray) -> bool:
	return false


func _protocol_signal_marker() -> void:
	# Reference protocol signals in a never-run branch to keep analyzer quiet.
	if false:
		emit_signal("fog_updated", {})
