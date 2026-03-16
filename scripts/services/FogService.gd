extends Node
class_name FogService

signal fog_updated(state: Dictionary)

var _fog_state: Dictionary = {
    "enabled": true,
    "revealed": []
}

func _ready() -> void:
    # no-op ready hook; services should be registered by bootstrap/autoload
    pass

func reveal_area(pos: Vector2, radius: float) -> void:
    # Minimal implementation: record a reveal entry and emit update
    _fog_state.revealed.append({"pos": pos, "radius": radius})
    emit_signal("fog_updated", _fog_state)

func set_fog_enabled(enabled: bool) -> void:
    _fog_state.enabled = enabled
    emit_signal("fog_updated", _fog_state)

func get_fog_state() -> Dictionary:
    return _fog_state.duplicate(true)
