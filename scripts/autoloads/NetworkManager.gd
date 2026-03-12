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

var _server: WebSocketMultiplayerPeer = null

# Maps WebSocket peer_id → player_id (set via DM profile bindings)
# { peer_id (int): player_id (Variant) }
var ws_bindings: Dictionary = {}

# Peer IDs of connected Player display processes (sent render state, not input)
var _display_peers: Array[int] = []
var _input_peers: Array[int] = []


func _game_state() -> Node:
	return get_node("/root/GameState")


func _input_manager() -> Node:
	return get_node("/root/InputManager")

signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)
signal display_peer_registered(peer_id: int, viewport_size: Vector2)
signal display_viewport_resized(peer_id: int, viewport_size: Vector2)

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
	var data = JSON.parse_string(raw)
	if data == null or not data is Dictionary:
		return # Silently discard malformed packets

	# Route display-client handshake before applying input validation
	if data.get("type", "") == "display":
		var vp := Vector2(
			float(data.get("viewport_width", 1920)),
			float(data.get("viewport_height", 1080)))
		_register_display_peer(peer_id, vp)
		return

	# Viewport resize report from an already-registered display peer
	if data.get("type", "") == "viewport_resize" and peer_id in _display_peers:
		var vp := Vector2(
			float(data.get("viewport_width", 1920)),
			float(data.get("viewport_height", 1080)))
		emit_signal("display_viewport_resized", peer_id, vp)
		return

	# Ignore all other packets from display peers (they only receive, never send input)
	if peer_id in _display_peers:
		return

	# Validate required movement fields
	if not ("x" in data and "y" in data):
		return

	var player_id = ws_bindings.get(peer_id, data.get("player_id", ""))
	var x: float = clampf(float(data["x"]), -1.0, 1.0)
	var y: float = clampf(float(data["y"]), -1.0, 1.0)

	# Only accept packets from player_ids that exist in profiles
	if player_id == "" or not _game_state().player_locked.has(player_id):
		return

	_input_manager().set_vector(player_id, Vector2(x, y))

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
	if ws_peer:
		ws_peer.send_text(JSON.stringify({"msg": "ping"}))

func broadcast_to_displays(data: Dictionary) -> void:
	## Send a state / delta packet to every connected Player display process.
	## Called by game systems whenever render-relevant state changes.
	if _display_peers.is_empty() or _server == null:
		return
	var payload := JSON.stringify(data).to_utf8_buffer()
	for peer_id: int in _display_peers:
		var ws_peer := _server.get_peer(peer_id)
		if ws_peer:
			ws_peer.send(payload)

func broadcast_map(map: MapData) -> void:
	## Full map broadcast — player reloads the image and resets its camera.
	## Use only for initial file load and late-joining peers.
	broadcast_to_displays({"msg": "map_loaded", "map": map.to_dict()})

func broadcast_map_update(map: MapData) -> void:
	## Lightweight update — sends grid/scale changes without triggering a
	## camera reset on the player side.
	broadcast_to_displays({"msg": "map_updated", "map": map.to_dict()})
