extends RefCounted
class_name IFogService

"""
Protocol: IFogService

Expected public methods:
- func reveal_area(pos: Vector2, radius: float) -> void
- func set_fog_enabled(enabled: bool) -> void
- func get_fog_state() -> Dictionary

Expected signals:
- signal fog_updated(state: Dictionary)

Implementations should keep behavior minimal and document edge cases.
"""
