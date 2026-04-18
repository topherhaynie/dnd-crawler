extends RefCounted
class_name NetworkManager

## Typed manager for the network service.
## All view-layer callers use these proxy methods.
## Exception: signal connections must target `registry.network.service` directly,
## because INetworkService extends Node and signals are emitted on that Node
## instance; a RefCounted manager cannot re-emit them without its own Node scaffold.

var service: INetworkService = null


func start_server() -> void:
	if service == null:
		return
	service.start_server()


func stop_server() -> void:
	if service == null:
		return
	service.stop_server()


func broadcast_to_displays(data: Dictionary) -> void:
	if service == null:
		return
	service.broadcast_to_displays(data)


func send_to_display(peer_id: int, data: Dictionary) -> void:
	if service == null:
		return
	service.send_to_display(peer_id, data)


func send_map_to_display(peer_id: int, map: Object, is_update: bool = false, fog_snapshot: Dictionary = {}) -> void:
	if service == null:
		return
	service.send_map_to_display(peer_id, map, is_update, fog_snapshot)


func bind_peer(peer_id: int, player_id: Variant) -> void:
	if service == null:
		return
	service.bind_peer(peer_id, player_id)


func get_connected_input_peers() -> Array:
	if service == null:
		return []
	return service.get_connected_input_peers()


func get_peer_bound_player(peer_id: int) -> String:
	if service == null:
		return ""
	return service.get_peer_bound_player(peer_id)


func send_to_peer(peer_id: int, data: Dictionary) -> void:
	if service == null:
		return
	service.send_to_peer(peer_id, data)


func get_peer_for_player(player_id: String) -> int:
	if service == null:
		return -1
	return service.get_peer_for_player(player_id)


func clear_all_peer_bindings() -> void:
	if service == null:
		return
	service.clear_all_peer_bindings()


func displays_under_backpressure() -> bool:
	if service == null:
		return false
	return service.displays_under_backpressure()


func is_display_peer_connected(peer_id: int) -> bool:
	if service == null:
		return false
	return service.is_display_peer_connected(peer_id)


func get_display_peer_ids() -> Array:
	if service == null:
		return []
	return service.get_display_peer_ids()


func get_peer_role(peer_id: int) -> String:
	if service == null:
		return ""
	return service.get_peer_role(peer_id)
