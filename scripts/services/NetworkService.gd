extends Node
class_name NetworkService

signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)
signal display_peer_registered(peer_id: int, viewport_size: Vector2)

# Minimal NetworkService wrapper. During migration this delegates to the
# legacy autoload `NetworkManager` when present so startup and runtime remain
# stable. Future iterations should lift logic from `scripts/autoloads/NetworkManager.gd`
# into this service and remove the legacy autoload.

func _legacy() -> Node:
    if has_node("/root/NetworkManager"):
        return get_node("/root/NetworkManager")
    return null

func _ready() -> void:
    # If the legacy NetworkManager exists, mirror its signals so consumers
    # connected to this service see the same events and analyzer warnings
    # for unused signals are avoided.
    var legacy := _legacy()
    if legacy != null:
        if legacy.has_signal("client_connected") and not legacy.is_connected("client_connected", Callable(self , "_on_legacy_client_connected")):
            legacy.connect("client_connected", Callable(self , "_on_legacy_client_connected"))
        if legacy.has_signal("client_disconnected") and not legacy.is_connected("client_disconnected", Callable(self , "_on_legacy_client_disconnected")):
            legacy.connect("client_disconnected", Callable(self , "_on_legacy_client_disconnected"))
        if legacy.has_signal("display_peer_registered") and not legacy.is_connected("display_peer_registered", Callable(self , "_on_legacy_display_peer_registered")):
            legacy.connect("display_peer_registered", Callable(self , "_on_legacy_display_peer_registered"))

func _on_legacy_client_connected(peer_id: int) -> void:
    emit_signal("client_connected", peer_id)

func _on_legacy_client_disconnected(peer_id: int) -> void:
    emit_signal("client_disconnected", peer_id)

func _on_legacy_display_peer_registered(peer_id: int, viewport_size: Vector2) -> void:
    emit_signal("display_peer_registered", peer_id, viewport_size)

func start_server() -> void:
    var legacy = _legacy()
    if legacy and legacy.has_method("start_server"):
        legacy.start_server()

func stop_server() -> void:
    var legacy = _legacy()
    if legacy and legacy.has_method("stop_server"):
        legacy.stop_server()

func broadcast_to_displays(data: Dictionary) -> void:
    var legacy = _legacy()
    if legacy and legacy.has_method("broadcast_to_displays"):
        legacy.broadcast_to_displays(data)

func send_to_display(peer_id: int, data: Dictionary) -> void:
    var legacy = _legacy()
    if legacy and legacy.has_method("send_to_display"):
        legacy.send_to_display(peer_id, data)

func bind_peer(peer_id: int, player_id: Variant) -> void:
    var legacy = _legacy()
    if legacy and legacy.has_method("bind_peer"):
        legacy.bind_peer(peer_id, player_id)

func get_connected_input_peers() -> Array:
    var legacy = _legacy()
    if legacy and legacy.has_method("get_connected_input_peers"):
        return legacy.get_connected_input_peers()
    return []

func get_peer_bound_player(peer_id: int) -> String:
    var legacy = _legacy()
    if legacy and legacy.has_method("get_peer_bound_player"):
        return str(legacy.get_peer_bound_player(peer_id))
    return ""

func is_display_peer_connected(peer_id: int) -> bool:
    var legacy = _legacy()
    if legacy and legacy.has_method("is_display_peer_connected"):
        return legacy.is_display_peer_connected(peer_id)
    return false

func get_peer_for_token(token: String) -> int:
    var legacy = _legacy()
    if legacy and legacy.has_method("get_peer_for_token"):
        return int(legacy.get_peer_for_token(token))
    return -1

func send_map_to_display(peer_id: int, map: Object, is_update: bool = false, fog_snapshot: Dictionary = {}) -> void:
    var legacy = _legacy()
    if legacy and legacy.has_method("send_map_to_display"):
        legacy.send_map_to_display(peer_id, map, is_update, fog_snapshot)

func broadcast_map(map: Object) -> void:
    var legacy = _legacy()
    if legacy and legacy.has_method("broadcast_map"):
        legacy.broadcast_map(map)

func broadcast_map_update(map: Object) -> void:
    var legacy = _legacy()
    if legacy and legacy.has_method("broadcast_map_update"):
        legacy.broadcast_map_update(map)
