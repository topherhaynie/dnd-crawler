extends Node
class_name NetworkAdapter

var _service: Node = null

func set_service(s: Node) -> void:
    _service = s

func _service_or_legacy() -> Node:
    if _service != null:
        return _service
    if has_node("/root/NetworkManager"):
        return get_node("/root/NetworkManager")
    return null

func start_server() -> void:
    var s := _service_or_legacy()
    if s and s.has_method("start_server"):
        s.start_server()

func stop_server() -> void:
    var s := _service_or_legacy()
    if s and s.has_method("stop_server"):
        s.stop_server()

func broadcast_to_displays(data: Dictionary) -> void:
    var s := _service_or_legacy()
    if s and s.has_method("broadcast_to_displays"):
        s.broadcast_to_displays(data)

func send_to_display(peer_id: int, data: Dictionary) -> void:
    var s := _service_or_legacy()
    if s and s.has_method("send_to_display"):
        s.send_to_display(peer_id, data)

func bind_peer(peer_id: int, player_id: Variant) -> void:
    var s := _service_or_legacy()
    if s and s.has_method("bind_peer"):
        s.bind_peer(peer_id, player_id)

func get_connected_input_peers() -> Array:
    var s := _service_or_legacy()
    if s and s.has_method("get_connected_input_peers"):
        return s.get_connected_input_peers()
    return []

func get_peer_bound_player(peer_id: int) -> String:
    var s := _service_or_legacy()
    if s and s.has_method("get_peer_bound_player"):
        return str(s.get_peer_bound_player(peer_id))
    return ""

func is_display_peer_connected(peer_id: int) -> bool:
    var s := _service_or_legacy()
    if s and s.has_method("is_display_peer_connected"):
        return s.is_display_peer_connected(peer_id)
    return false

func get_peer_for_token(token: String) -> int:
    var s := _service_or_legacy()
    if s and s.has_method("get_peer_for_token"):
        return int(s.get_peer_for_token(token))
    return -1
