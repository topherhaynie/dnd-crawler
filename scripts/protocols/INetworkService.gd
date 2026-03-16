extends RefCounted
class_name INetworkService

"""
Protocol: INetworkService

Expected public methods (examples):
- func start_server() -> void
- func stop_server() -> void
- func broadcast_to_displays(data: Dictionary) -> void
- func send_to_display(peer_id: int, data: Dictionary) -> void
- func bind_peer(peer_id: int, player_id: Variant) -> void
- func get_connected_input_peers() -> Array
- func get_peer_bound_player(peer_id: int) -> String

Expected signals:
- signal client_connected(peer_id: int)
- signal client_disconnected(peer_id: int)
- signal display_peer_registered(peer_id: int, viewport_size: Vector2)

Implementations should keep behavior minimal and document edge cases.
"""
