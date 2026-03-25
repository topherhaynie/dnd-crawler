extends INetworkService
class_name NetworkService

# WebSocket server defaults
const WS_PORT: int = 9090
const OUTBOUND_PRESSURE_WARN_BYTES: int = 262144
const FOG_OUTBOUND_SOFT_LIMIT_BYTES: int = 786432
const FOG_SNAPSHOT_B64_CHUNK_CHARS: int = 262144

var _server: WebSocketMultiplayerPeer = null
var ws_bindings: Dictionary = {}
var ws_last_seen_token: Dictionary = {}
var ws_peer_roles: Dictionary = {}
var _display_peers: Array[int] = []
var _input_peers: Array[int] = []
var _fog_packet_bytes_by_type: Dictionary = {"fog_updated": 0, "fog_delta": 0}
var _fog_packet_count_by_type: Dictionary = {"fog_updated": 0, "fog_delta": 0}
var _last_fog_metrics_log_msec: int = 0
const JsonUtilsScript = preload("res://scripts/utils/JsonUtils.gd")


func _game_state() -> GameStateManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.game_state == null:
		return null
	return registry.game_state

func _ready() -> void:
	# NetworkService is the canonical implementation — consumers should
	# obtain the service from the `ServiceRegistry` and connect to signals
	# exposed by this node. No legacy signal mirroring is performed.
	pass


func start_server() -> void:
	if _server != null:
		return

	_server = WebSocketMultiplayerPeer.new()
	# Increase the outbound buffer so large fog snapshot chunks don't trigger
	# ERR_OUT_OF_MEMORY from the wslay layer on large maps.
	_server.outbound_buffer_size = 4 * 1024 * 1024 # 4 MiB
	_server.inbound_buffer_size = 2 * 1024 * 1024 # 2 MiB
	var err := _server.create_server(WS_PORT)
	if err != OK:
		push_error("NetworkService: failed to start WebSocket server on port %d (error %d)" % [WS_PORT, err])
		_server = null
		return
	_server.peer_connected.connect(Callable(self , "_on_peer_connected"))
	_server.peer_disconnected.connect(Callable(self , "_on_peer_disconnected"))
	print("NetworkService: WebSocket server listening on port %d" % WS_PORT)

func stop_server() -> void:
	if _server:
		_server.close()
		_server = null

func _process(_delta: float) -> void:
	if _server == null:
		return
	_server.poll()
	_drain_packets()

func _drain_packets() -> void:
	while _server and _server.get_available_packet_count() > 0:
		var peer_id := _server.get_packet_peer()
		var raw := _server.get_packet().get_string_from_utf8()
		_handle_packet(raw, peer_id)

func _handle_packet(raw: String, _peer_id: int) -> void:
	var peer_id: int = _peer_id
	var data = JsonUtilsScript.parse_json_text(raw)
	if data == null or not data is Dictionary:
		return

	# Protocol versioning: warn if client declares a non-default protocol_version
	if data.has("protocol_version"):
		var pv_raw: Variant = data.get("protocol_version")
		var pv: int = 0
		if pv_raw is int:
			pv = pv_raw
		else:
			pv = int(str(pv_raw))
		if pv != 1:
			push_warning("NetworkService: warning: peer uses protocol_version %d" % pv)
	if data.has("player_id"):
		var seen_token: String = str(data.get("player_id", "")).strip_edges()
		if seen_token != "":
			ws_last_seen_token[peer_id] = seen_token

	if data.get("type", "") == "display":
		var role := str(data.get("role", "")).strip_edges()
		if role != "":
			ws_peer_roles[peer_id] = role
		else:
			ws_peer_roles.erase(peer_id)
		print("NetworkService: handshake role=%s from peer %d" % [role, peer_id])
		var vp := Vector2(
			float(data.get("viewport_width", 1920)),
			float(data.get("viewport_height", 1080)))
		_register_display_peer(peer_id, vp)
		emit_signal("display_fullscreen_changed", peer_id, bool(data.get("fullscreen", false)))
		return

	if data.get("type", "") == "bind":
		if data.has("player_id"):
			var pid = str(data.get("player_id", "")).strip_edges()
			if pid != "":
				bind_peer(peer_id, pid)
		return

	if data.get("type", "") == "player_action":
		var pid: String = _resolve_packet_player_id(peer_id, data)
		var act: String = str(data.get("action", "")).strip_edges()
		if pid != "" and act != "":
			var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			if reg != null and reg.input != null and reg.input.service != null:
				reg.input.service.dispatch_action(pid, act)
		return

	if data.get("type", "") == "viewport_resize" and peer_id in _display_peers:
		var vp := Vector2(
			float(data.get("viewport_width", 1920)),
			float(data.get("viewport_height", 1080)))
		emit_signal("display_viewport_resized", peer_id, vp)
		if data.has("fullscreen"):
			emit_signal("display_fullscreen_changed", peer_id, bool(data.get("fullscreen")))
		return

	if data.get("type", "") == "display_sync_applied" and peer_id in _display_peers:
		emit_signal("display_sync_applied", peer_id, data)
		return

	# Input packet validation: when clients send input vectors we should
	# explicitly validate presence and numeric-ness of `x` and `y` and
	# log a debug warning when malformed instead of silently crashing.
	if data.get("type", "") == "input":
		if not data.has("x") or not data.has("y"):
			print_debug("NetworkService: ignoring malformed input packet from %d — missing x/y: %s" % [peer_id, str(data)])
			return
		var x_raw_check: Variant = data.get("x")
		var y_raw_check: Variant = data.get("y")
		if not _is_valid_axis_value(x_raw_check) or not _is_valid_axis_value(y_raw_check):
			print_debug("NetworkService: ignoring malformed input packet from %d — non-numeric x/y: %s" % [peer_id, str(data)])
			return

	if peer_id in _display_peers:
		return

	if not ("x" in data and "y" in data):
		return

	var player_id := _resolve_packet_player_id(peer_id, data)
	if player_id.is_empty():
		return

	var x_raw: Variant = data["x"]
	var y_raw: Variant = data["y"]
	if not _is_valid_axis_value(x_raw) or not _is_valid_axis_value(y_raw):
		return
	var x: float = clampf(float(x_raw), -1.0, 1.0)
	var y: float = clampf(float(y_raw), -1.0, 1.0)

	if not _is_known_player_id(player_id):
		return

	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.input != null and registry.input.service != null:
		registry.input.service.set_network_vector(player_id, Vector2(x, y))

func _resolve_packet_player_id(peer_id: int, data: Dictionary) -> String:
	var bound: Variant = ws_bindings.get(peer_id, "")
	if bound != null and str(bound) != "":
		if _is_known_player_id(str(bound)):
			return str(bound)
		var resolved_late := _lookup_profile_id(str(bound))
		if resolved_late != "":
			ws_bindings[peer_id] = resolved_late
			return resolved_late

	if not data.has("player_id"):
		return ""
	var raw: String = str(data.get("player_id", "")).strip_edges()
	if raw == "":
		return ""
	var gs := _game_state()
	if gs == null:
		return ""
	var profile := gs.get_profile_by_id(raw) as PlayerProfile
	if profile != null:
		return raw
	for p in gs.list_profiles():
		if not p is PlayerProfile:
			continue
		var pp := p as PlayerProfile
		if str(pp.input_id) == raw or str(pp.player_name) == raw:
			return pp.id
	return ""

func _lookup_profile_id(token: String) -> String:
	if token.is_empty():
		return ""
	var gs := _game_state()
	if gs == null:
		return ""
	var profile := gs.get_profile_by_id(token) as PlayerProfile
	if profile != null:
		return token
	for p in gs.list_profiles():
		if not p is PlayerProfile:
			continue
		var pp := p as PlayerProfile
		if str(pp.input_id) == token or str(pp.player_name) == token:
			return pp.id
	return ""

func _is_valid_axis_value(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var axis := float(value)
	if is_nan(axis) or is_inf(axis):
		return false
	return true

func _is_known_player_id(player_id: String) -> bool:
	if player_id.is_empty():
		return false
	if _game_state() != null and _game_state().player_locked.has(player_id):
		return true
	return _game_state() != null and _game_state().get_profile_by_id(player_id) != null

func _on_peer_connected(peer_id: int) -> void:
	if not peer_id in _input_peers:
		_input_peers.append(peer_id)
	emit_signal("client_connected", peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	ws_bindings.erase(peer_id)
	ws_peer_roles.erase(peer_id)
	_display_peers.erase(peer_id)
	_input_peers.erase(peer_id)
	emit_signal("client_disconnected", peer_id)

func bind_peer(peer_id: int, player_id) -> void:
	ws_bindings[peer_id] = player_id

func clear_all_peer_bindings() -> void:
	ws_bindings.clear()

func get_connected_input_peers() -> Array[int]:
	return _input_peers.duplicate()

func is_display_peer_connected(peer_id: int) -> bool:
	return peer_id in _display_peers

func get_display_peer_ids() -> Array:
	return _display_peers.duplicate()

func get_peer_role(peer_id: int) -> String:
	return str(ws_peer_roles.get(peer_id, ""))

func _register_display_peer(peer_id: int, viewport_size: Vector2) -> void:
	if peer_id in _display_peers:
		return
	_display_peers.append(peer_id)
	_input_peers.erase(peer_id)
	emit_signal("display_peer_registered", peer_id, viewport_size)
	var ws_peer := _server.get_peer(peer_id)
	if ws_peer and ws_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_peer.send_text(JSON.stringify({"msg": "ping"}))

func broadcast_to_displays(data: Dictionary) -> void:
	if _display_peers.is_empty() or _server == null:
		return
	var payload := JSON.stringify(data).to_utf8_buffer()
	var msg_type := str(data.get("msg", ""))
	if msg_type.begins_with("fog_") and displays_under_backpressure():
		return
	if msg_type == "fog_updated" or msg_type == "fog_delta":
		_track_fog_packet_metrics(msg_type, payload.size())
	for peer_id: int in _display_peers:
		var ws_peer := _server.get_peer(peer_id)
		if ws_peer:
			if ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
				continue
			ws_peer.send(payload)

func send_to_display(peer_id: int, data: Dictionary) -> void:
	if _server == null:
		return
	if not peer_id in _display_peers:
		return
	var ws_peer := _server.get_peer(peer_id)
	if ws_peer == null:
		return
	if ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var msg_type := str(data.get("msg", data.get("type", "")))
	if msg_type.begins_with("fog_") and _is_peer_under_backpressure(peer_id):
		return
	var payload := JSON.stringify(data).to_utf8_buffer()
	var err := ws_peer.send(payload)
	if err != OK:
		push_warning("NetworkService: send_to_display failed peer=%d err=%d msg=%s" % [peer_id, err, str(data.get("msg", data.get("type", "?")))])


## Send to a display peer, bypassing the fog backpressure gate.
## Used for fog snapshot chunks that must arrive in full.
func _send_to_display_forced(peer_id: int, data: Dictionary) -> void:
	if _server == null:
		return
	if not peer_id in _display_peers:
		return
	var ws_peer := _server.get_peer(peer_id)
	if ws_peer == null:
		return
	if ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := JSON.stringify(data).to_utf8_buffer()
	var err := ws_peer.send(payload)
	if err != OK:
		push_warning("NetworkService: _send_to_display_forced failed peer=%d err=%d msg=%s" % [peer_id, err, str(data.get("msg", data.get("type", "?")))])


func displays_under_backpressure() -> bool:
	for peer_id in _display_peers:
		if _is_peer_under_backpressure(peer_id):
			return true
	return false

func _is_peer_under_backpressure(peer_id: int) -> bool:
	if _server == null:
		return false
	var ws_peer := _server.get_peer(peer_id)
	if ws_peer == null:
		return false
	if not ws_peer.has_method("get_current_outbound_buffered_amount"):
		return false
	var queued := int(ws_peer.get_current_outbound_buffered_amount())
	return queued >= FOG_OUTBOUND_SOFT_LIMIT_BYTES

func get_peer_bound_player(peer_id: int) -> String:
	var v: String = str(ws_bindings.get(peer_id, ""))
	if v != "":
		return v
	var seen: String = str(ws_last_seen_token.get(peer_id, ""))
	if seen != "":
		return seen
	return ""

func get_peer_for_token(token: String) -> int:
	if token.is_empty():
		return -1
	for key in ws_bindings.keys():
		var val: String = str(ws_bindings.get(key, ""))
		if val != "" and val == token:
			return int(key)
	for key in ws_last_seen_token.keys():
		if str(ws_last_seen_token.get(key, "")) == token:
			return int(key)
	return -1

func send_map_to_display(peer_id: int, map: Object, is_update: bool = false, fog_snapshot: Dictionary = {}) -> void:
	if map == null:
		return
	var map_payload: Dictionary = map.to_dict()
	send_to_display(peer_id, {
		"msg": "map_updated" if is_update else "map_loaded",
		"map": map_payload,
	})
	if not fog_snapshot.is_empty():
		_send_fog_snapshot_to_display(peer_id, fog_snapshot)

func broadcast_map(map: Object) -> void:
	if map == null:
		return
	var map_payload: Dictionary = map.to_dict()
	broadcast_to_displays({"msg": "map_loaded", "map": map_payload})

func broadcast_map_update(map: Object) -> void:
	if map == null:
		return
	var map_payload: Dictionary = map.to_dict()
	broadcast_to_displays({"msg": "map_updated", "map": map_payload})

func _send_fog_snapshot_to_display(peer_id: int, fog_snapshot: Dictionary) -> void:
	var b64 := str(fog_snapshot.get("fog_state_png_b64", ""))
	if b64.is_empty():
		send_to_display(peer_id, fog_snapshot)
		return
	var snapshot_bytes := int(fog_snapshot.get("snapshot_bytes", -1))
	var snapshot_hash := int(fog_snapshot.get("snapshot_hash", -1))
	var total_chunks := int(ceil(float(b64.length()) / float(FOG_SNAPSHOT_B64_CHUNK_CHARS)))
	total_chunks = maxi(1, total_chunks)
	_send_to_display_forced(peer_id, {
		"msg": "fog_state_snapshot_begin",
		"snapshot_bytes": snapshot_bytes,
		"snapshot_hash": snapshot_hash,
		"chunks": total_chunks,
	})
	for i in range(total_chunks):
		var start := i * FOG_SNAPSHOT_B64_CHUNK_CHARS
		var count := mini(FOG_SNAPSHOT_B64_CHUNK_CHARS, b64.length() - start)
		var part := b64.substr(start, count)
		_send_to_display_forced(peer_id, {
			"msg": "fog_state_snapshot_chunk",
			"snapshot_hash": snapshot_hash,
			"index": i,
			"chunks": total_chunks,
			"fog_state_png_b64_chunk": part,
		})
	_send_to_display_forced(peer_id, {
		"msg": "fog_state_snapshot_end",
		"snapshot_bytes": snapshot_bytes,
		"snapshot_hash": snapshot_hash,
		"chunks": total_chunks,
	})

func _track_fog_packet_metrics(msg_type: String, payload_bytes: int) -> void:
	if not OS.is_debug_build():
		return
	_fog_packet_bytes_by_type[msg_type] = int(_fog_packet_bytes_by_type.get(msg_type, 0)) + payload_bytes
	_fog_packet_count_by_type[msg_type] = int(_fog_packet_count_by_type.get(msg_type, 0)) + 1
	var now := Time.get_ticks_msec()
	if _last_fog_metrics_log_msec == 0:
		_last_fog_metrics_log_msec = now
		return
	if now - _last_fog_metrics_log_msec < 2000:
		return
	print("NetworkService: fog metrics updated bytes=%d count=%d delta bytes=%d count=%d" % [
		int(_fog_packet_bytes_by_type.get("fog_updated", 0)),
		int(_fog_packet_count_by_type.get("fog_updated", 0)),
		int(_fog_packet_bytes_by_type.get("fog_delta", 0)),
		int(_fog_packet_count_by_type.get("fog_delta", 0)),
	])
	_last_fog_metrics_log_msec = now
