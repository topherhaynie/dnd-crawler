extends RefCounted
class_name INetworkService

"""
Protocol: INetworkService

Methods:
- func start_server() -> void
- func stop_server() -> void
- func broadcast_to_displays(data: Dictionary) -> void
- func send_to_display(peer_id: int, data: Dictionary) -> void
- func bind_peer(peer_id: int, player_id: Variant) -> void
- func get_connected_input_peers() -> Array
- func get_peer_bound_player(peer_id: int) -> String

Signals:
- signal client_connected(peer_id: int)
- signal client_disconnected(peer_id: int)
- signal display_peer_registered(peer_id: int, viewport_size: Vector2)

Notes:
- Keep implementations minimal; this file documents expected signatures.
"""

signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)
signal display_peer_registered(peer_id: int, viewport_size: Vector2)

func start_server() -> void:
	pass

func stop_server() -> void:
	pass

func broadcast_to_displays(_data: Dictionary) -> void:
	pass

func send_to_display(_peer_id: int, _data: Dictionary) -> void:
	pass

func bind_peer(_peer_id: int, _player_id: Variant) -> void:
	pass

func get_connected_input_peers() -> Array:
	return []

func get_peer_bound_player(_peer_id: int) -> String:
	return ""
