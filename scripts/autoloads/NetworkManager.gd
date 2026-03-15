extends Node

# ---------------------------------------------------------------------------
# NetworkManager — runs a WebSocket server on port 9090.
# Receives JSON movement packets from mobile clients and routes them to
# InputManager. Full packet parsing wired in Phase 5; this phase establishes
# the server lifecycle.
#
# Expected packet format (Phase 5):
#   { "player_id": int, "x": float, "y": float }
# ---------------------------------------------------------------------------

const WS_PORT: int = 9090
const MAX_PENDING_CONNECTIONS: int = 8
const DEBUG_FOG_TELEMETRY: bool = false
const OUTBOUND_PRESSURE_WARN_BYTES: int = 262144
const FOG_OUTBOUND_SOFT_LIMIT_BYTES: int = 786432
const FOG_SNAPSHOT_B64_CHUNK_CHARS: int = 12000

var _server: WebSocketMultiplayerPeer = null

# Maps WebSocket peer_id → player_id (set via DM profile bindings)
# { peer_id (int): player_id (Variant) }
var ws_bindings: Dictionary = {}
## Last-seen player token (player_id field) per WS peer_id — helps the DM UI
## show mobile Player IDs even when clients don't send an explicit 'bind'.
var ws_last_seen_token: Dictionary = {}

# Peer IDs of connected Player display processes (sent render state, not input)
var _display_peers: Array[int] = []
var _input_peers: Array[int] = []
var _fog_packet_bytes_by_type: Dictionary = {"fog_updated": 0, "fog_delta": 0}
var _fog_packet_count_by_type: Dictionary = {"fog_updated": 0, "fog_delta": 0}
var _last_fog_metrics_log_msec: int = 0


func _game_state() -> Node:
	return get_node("/root/GameState")


func _input_manager() -> Node:
	return get_node("/root/InputManager")

signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)
signal display_peer_registered(peer_id: int, viewport_size: Vector2)
signal display_viewport_resized(peer_id: int, viewport_size: Vector2)
signal display_sync_applied(peer_id: int, payload: Dictionary)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Server is started explicitly by Main._start_dm_mode() so the Player
	# process (which also loads this autoload) never tries to bind port 9090.
	pass

func start_server() -> void:
	_server = WebSocketMultiplayerPeer.new()
	var err := _server.create_server(WS_PORT)
	if err != OK:
		push_error("NetworkManager: failed to start WebSocket server on port %d (error %d)" % [WS_PORT, err])
		_server = null
		return
	_server.peer_connected.connect(_on_peer_connected)
	_server.peer_disconnected.connect(_on_peer_disconnected)
	print("NetworkManager: WebSocket server listening on port %d" % WS_PORT)

func stop_server() -> void:
	if _server:
		_server.close()
		_server = null

func _process(_delta: float) -> void:
	if _server == null:
		return
	_server.poll()
	_drain_packets()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_server()

# ---------------------------------------------------------------------------
# Packet handling
# ---------------------------------------------------------------------------

func _drain_packets() -> void:
	while _server and _server.get_available_packet_count() > 0:
		var peer_id := _server.get_packet_peer()
		var raw := _server.get_packet().get_string_from_utf8()
		_handle_packet(raw, peer_id)

func _handle_packet(raw: String, _peer_id: int) -> void:
	var peer_id: int = _peer_id
	# print("NetworkManager: raw packet from %d => %s" % [peer_id, raw])
	var data = JSON.parse_string(raw)
	if data == null or not data is Dictionary:
		return # Silently discard malformed packets

	# Record last-seen player_id token so UI can display it even without a bind
	if data.has("player_id"):
		var seen_token: String = str(data.get("player_id", "")).strip_edges()
		if seen_token != "":
			ws_last_seen_token[peer_id] = seen_token

	# Route display-client handshake before applying input validation
	if data.get("type", "") == "display":
		var vp := Vector2(
			float(data.get("viewport_width", 1920)),
			float(data.get("viewport_height", 1080)))
		_register_display_peer(peer_id, vp)
		return

	# Allow mobile clients to bind their WebSocket peer to a player_id
	if data.get("type", "") == "bind":
		if data.has("player_id"):
			var pid = str(data.get("player_id", "")).strip_edges()
			if pid != "":
				bind_peer(peer_id, pid)
				print("NetworkManager: bound peer %d to player_id %s" % [peer_id, pid])
		return

	# Viewport resize report from an already-registered display peer
	if data.get("type", "") == "viewport_resize" and peer_id in _display_peers:
		var vp := Vector2(
			float(data.get("viewport_width", 1920)),
			float(data.get("viewport_height", 1080)))
		emit_signal("display_viewport_resized", peer_id, vp)
		return

	# Display confirms it received + applied initial fog/map snapshot.
	if data.get("type", "") == "display_sync_applied" and peer_id in _display_peers:
		emit_signal("display_sync_applied", peer_id, data)
		return

	# Ignore all other packets from display peers (they only receive, never send input)
	if peer_id in _display_peers:
		return

	# Validate required movement fields
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

	# Only accept packets from player_ids that exist in profiles
	if not _is_known_player_id(player_id):
		return

	_input_manager().set_network_vector(player_id, Vector2(x, y))


func _resolve_packet_player_id(peer_id: int, data: Dictionary) -> String:
	var bound: Variant = ws_bindings.get(peer_id, "")
	if bound != null and str(bound) != "":
		# If the stored binding is already a canonical profile id, return it.
		if _is_known_player_id(str(bound)):
			return str(bound)
		# Attempt to resolve a previously-bound token to a profile id in case
		# the DM saved the profile after the client first connected.
		var resolved_late := _lookup_profile_id(str(bound))
		if resolved_late != "":
			ws_bindings[peer_id] = resolved_late
			print("NetworkManager: upgraded binding for peer %d -> profile %s (was %s)" % [peer_id, resolved_late, str(bound)])
			return resolved_late
		# Otherwise fall through to inspect the packet payload

	if not data.has("player_id"):
		return ""

	var raw: String = str(data.get("player_id", "")).strip_edges()
	if raw == "":
		return ""

	# If the incoming value is already a canonical profile id, accept it.
	var profile: PlayerProfile = _game_state().get_profile_by_id(raw) as PlayerProfile
	if profile != null:
		return raw

	# Otherwise attempt to match by profile.input_id or profile.player_name
	for p in _game_state().profiles:
		if not p is PlayerProfile:
			continue
		var pp := p as PlayerProfile
		if str(pp.input_id) == raw or str(pp.player_name) == raw:
			return pp.id

	# No match found
	return ""


func _lookup_profile_id(token: String) -> String:
	if token.is_empty():
		return ""
	# Direct id
	var profile: PlayerProfile = _game_state().get_profile_by_id(token) as PlayerProfile
	if profile != null:
		return token
	# Match input_id or player_name
	for p in _game_state().profiles:
		if not p is PlayerProfile:
			continue
		var pp := p as PlayerProfile
		if str(pp.input_id) == token or str(pp.player_name) == token:
			return pp.id
	return ""


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
	# First look for explicit binding
	for key in ws_bindings.keys():
		var val: String = str(ws_bindings.get(key, ""))
		if val != "" and val == token:
			return int(key)
	# Then look for last-seen tokens
	for key in ws_last_seen_token.keys():
		if str(ws_last_seen_token.get(key, "")) == token:
			return int(key)
	return -1


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
	if _game_state().player_locked.has(player_id):
		return true
	return _game_state().get_profile_by_id(player_id) != null

# ---------------------------------------------------------------------------
# Connection events
# ---------------------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: client connected — peer_id %d" % peer_id)
	if not peer_id in _input_peers:
		_input_peers.append(peer_id)
	emit_signal("client_connected", peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: client disconnected — peer_id %d" % peer_id)
	ws_bindings.erase(peer_id)
	_display_peers.erase(peer_id)
	_input_peers.erase(peer_id)
	emit_signal("client_disconnected", peer_id)

# ---------------------------------------------------------------------------
# Bind a WebSocket peer to a player profile id (called from DM UI in Phase 5)
# ---------------------------------------------------------------------------

func bind_peer(peer_id: int, player_id) -> void:
	ws_bindings[peer_id] = player_id


func clear_all_peer_bindings() -> void:
	ws_bindings.clear()


func get_connected_input_peers() -> Array[int]:
	return _input_peers.duplicate()


func is_display_peer_connected(peer_id: int) -> bool:
	return peer_id in _display_peers

# ---------------------------------------------------------------------------
# Display peer management
# ---------------------------------------------------------------------------

func _register_display_peer(peer_id: int, viewport_size: Vector2) -> void:
	if peer_id in _display_peers:
		return
	_display_peers.append(peer_id)
	_input_peers.erase(peer_id)
	print("NetworkManager: display peer registered — peer_id %d (total: %d)" % [peer_id, _display_peers.size()])
	# Signal DMWindow so it can re-push current map + camera to this new peer.
	emit_signal("display_peer_registered", peer_id, viewport_size)
	# Send an initial ping so the Player window confirms connectivity
	var ws_peer := _server.get_peer(peer_id)
	if ws_peer and ws_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_peer.send_text(JSON.stringify({"msg": "ping"}))

func broadcast_to_displays(data: Dictionary) -> void:
	## Send a state / delta packet to every connected Player display process.
	## Called by game systems whenever render-relevant state changes.
	if _display_peers.is_empty() or _server == null:
		return
	var payload := JSON.stringify(data).to_utf8_buffer()
	var msg_type := str(data.get("msg", ""))
	if _is_fog_message(msg_type) and displays_under_backpressure():
		if DEBUG_FOG_TELEMETRY and OS.is_debug_build():
			print("NetworkManager: skipped fog broadcast under backpressure (msg=%s bytes=%d)" % [msg_type, payload.size()])
		return
	if msg_type == "fog_updated" or msg_type == "fog_delta":
		_track_fog_packet_metrics(msg_type, payload.size())
	for peer_id: int in _display_peers:
		var ws_peer := _server.get_peer(peer_id)
		if ws_peer:
			if ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
				continue
			if DEBUG_FOG_TELEMETRY and OS.is_debug_build() and payload.size() >= OUTBOUND_PRESSURE_WARN_BYTES:
				print("NetworkManager: outbound pressure event (msg=%s, peer=%d, bytes=%d)" % [msg_type, peer_id, payload.size()])
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
	if _is_fog_message(msg_type) and _is_peer_under_backpressure(peer_id):
		if DEBUG_FOG_TELEMETRY and OS.is_debug_build():
			print("NetworkManager: skipped fog send under backpressure (peer=%d msg=%s)" % [peer_id, msg_type])
		return
	var payload := JSON.stringify(data).to_utf8_buffer()
	var err := ws_peer.send(payload)
	if err != OK:
		push_warning("NetworkManager: send_to_display failed peer=%d err=%d msg=%s" % [peer_id, err, str(data.get("msg", data.get("type", "?")))])


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


func _is_fog_message(msg_type: String) -> bool:
	return msg_type.begins_with("fog_")


func send_map_to_display(peer_id: int, map: MapData, is_update: bool = false, fog_snapshot: Dictionary = {}) -> void:
	if map == null:
		return
	var map_payload: Dictionary = map.to_dict()
	map_payload["fog_hidden_cells"] = []
	send_to_display(peer_id, {
		"msg": "map_updated" if is_update else "map_loaded",
		"map": map_payload,
	})
	if not fog_snapshot.is_empty():
		_send_fog_snapshot_to_display(peer_id, fog_snapshot)


func _send_fog_snapshot_to_display(peer_id: int, fog_snapshot: Dictionary) -> void:
	var b64 := str(fog_snapshot.get("fog_state_png_b64", ""))
	if b64.is_empty():
		send_to_display(peer_id, fog_snapshot)
		return

	var snapshot_bytes := int(fog_snapshot.get("snapshot_bytes", -1))
	var snapshot_hash := int(fog_snapshot.get("snapshot_hash", -1))
	var total_chunks := int(ceil(float(b64.length()) / float(FOG_SNAPSHOT_B64_CHUNK_CHARS)))
	total_chunks = maxi(1, total_chunks)

	send_to_display(peer_id, {
		"msg": "fog_state_snapshot_begin",
		"snapshot_bytes": snapshot_bytes,
		"snapshot_hash": snapshot_hash,
		"chunks": total_chunks,
	})

	for i in range(total_chunks):
		var start := i * FOG_SNAPSHOT_B64_CHUNK_CHARS
		var count := mini(FOG_SNAPSHOT_B64_CHUNK_CHARS, b64.length() - start)
		var part := b64.substr(start, count)
		send_to_display(peer_id, {
			"msg": "fog_state_snapshot_chunk",
			"snapshot_hash": snapshot_hash,
			"index": i,
			"chunks": total_chunks,
			"fog_state_png_b64_chunk": part,
		})

	send_to_display(peer_id, {
		"msg": "fog_state_snapshot_end",
		"snapshot_bytes": snapshot_bytes,
		"snapshot_hash": snapshot_hash,
		"chunks": total_chunks,
	})


func _track_fog_packet_metrics(msg_type: String, payload_bytes: int) -> void:
	if not DEBUG_FOG_TELEMETRY or not OS.is_debug_build():
		return
	_fog_packet_bytes_by_type[msg_type] = int(_fog_packet_bytes_by_type.get(msg_type, 0)) + payload_bytes
	_fog_packet_count_by_type[msg_type] = int(_fog_packet_count_by_type.get(msg_type, 0)) + 1

	var now := Time.get_ticks_msec()
	if _last_fog_metrics_log_msec == 0:
		_last_fog_metrics_log_msec = now
		return
	if now - _last_fog_metrics_log_msec < 2000:
		return

	print("NetworkManager: fog metrics updated bytes=%d count=%d delta bytes=%d count=%d" % [
		int(_fog_packet_bytes_by_type.get("fog_updated", 0)),
		int(_fog_packet_count_by_type.get("fog_updated", 0)),
		int(_fog_packet_bytes_by_type.get("fog_delta", 0)),
		int(_fog_packet_count_by_type.get("fog_delta", 0)),
	])
	_last_fog_metrics_log_msec = now

func broadcast_map(map: MapData) -> void:
	## Full map broadcast — player reloads the image and resets its camera.
	## Use only for initial file load and late-joining peers.
	var map_payload: Dictionary = map.to_dict()
	map_payload["fog_hidden_cells"] = []
	broadcast_to_displays({"msg": "map_loaded", "map": map_payload})

func broadcast_map_update(map: MapData) -> void:
	## Lightweight update — sends grid/scale changes without triggering a
	## camera reset on the player side.
	var map_payload: Dictionary = map.to_dict()
	map_payload["fog_hidden_cells"] = []
	broadcast_to_displays({"msg": "map_updated", "map": map_payload})
