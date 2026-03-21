extends Node
class_name INetworkService

## Protocol: INetworkService
##
## Base class for WebSocket server implementations. Handles DM-to-player
## display peer management and input peer routing.
##
## Signals:
##   client_connected, client_disconnected, display_peer_registered,
##   display_viewport_resized, display_sync_applied

@warning_ignore("unused_signal")
signal client_connected(peer_id: int)
@warning_ignore("unused_signal")
signal client_disconnected(peer_id: int)
@warning_ignore("unused_signal")
signal display_peer_registered(peer_id: int, viewport_size: Vector2)
@warning_ignore("unused_signal")
signal display_viewport_resized(peer_id: int, viewport_size: Vector2)
@warning_ignore("unused_signal")
signal display_fullscreen_changed(peer_id: int, is_fullscreen: bool)
@warning_ignore("unused_signal")
signal display_sync_applied(peer_id: int, payload: Dictionary)

func start_server() -> void:
	push_error("INetworkService.start_server: not implemented")

func stop_server() -> void:
	push_error("INetworkService.stop_server: not implemented")

func broadcast_to_displays(_data: Dictionary) -> void:
	push_error("INetworkService.broadcast_to_displays: not implemented")

func send_to_display(_peer_id: int, _data: Dictionary) -> void:
	push_error("INetworkService.send_to_display: not implemented")

func bind_peer(_peer_id: int, _player_id: Variant) -> void:
	push_error("INetworkService.bind_peer: not implemented")

func get_connected_input_peers() -> Array:
	push_error("INetworkService.get_connected_input_peers: not implemented")
	return []

func get_peer_bound_player(_peer_id: int) -> String:
	push_error("INetworkService.get_peer_bound_player: not implemented")
	return ""

func clear_all_peer_bindings() -> void:
	push_error("INetworkService.clear_all_peer_bindings: not implemented")

func displays_under_backpressure() -> bool:
	push_error("INetworkService.displays_under_backpressure: not implemented")
	return false

func is_display_peer_connected(_peer_id: int) -> bool:
	push_error("INetworkService.is_display_peer_connected: not implemented")
	return false
