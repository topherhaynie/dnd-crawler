extends Node

# ---------------------------------------------------------------------------
# PlayerClient — WebSocket client that runs inside the Player display process.
#
# Connects to the DM host's WebSocket server (port 9090), sends a
# "display" handshake so the server can classify this peer, then receives
# rendered-state packets and emits them as signals for PlayerMain to forward
# to the viewport.
#
# Reconnect loop: if the connection drops (e.g. DM not yet started) the
# client retries every RECONNECT_DELAY seconds.
# ---------------------------------------------------------------------------

signal state_received(data: Dictionary) ## Emitted for every valid state packet from DM

const SERVER_URL := "ws://127.0.0.1:9090"
const RECONNECT_DELAY := 2.0 ## seconds between reconnect attempts

var _socket: WebSocketPeer = WebSocketPeer.new()
var _connected: bool = false


func _ready() -> void:
	_connect_to_server()


func _process(_delta: float) -> void:
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				print("PlayerClient: connected to DM server at %s" % SERVER_URL)
				_send_handshake()
			_drain_packets()

		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				var code := _socket.get_close_code()
				print("PlayerClient: disconnected (code=%d) — retrying in %.1fs" % [code, RECONNECT_DELAY])
			_schedule_reconnect()

		WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_CLOSING:
			pass # wait


# ---------------------------------------------------------------------------
# Connection helpers
# ---------------------------------------------------------------------------

func _connect_to_server() -> void:
	_socket = WebSocketPeer.new() # fresh peer each attempt
	var err := _socket.connect_to_url(SERVER_URL)
	if err != OK:
		push_warning("PlayerClient: could not initiate connection to %s (err=%d)" % [SERVER_URL, err])
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	# Prevents tight reconnect loops by awaiting a timer, then tries again.
	# Uses a one-shot SceneTree timer so it survives process() calls.
	set_process(false)
	get_tree().create_timer(RECONNECT_DELAY).timeout.connect(_on_reconnect_timer, CONNECT_ONE_SHOT)


func _on_reconnect_timer() -> void:
	set_process(true)
	_connect_to_server()


# ---------------------------------------------------------------------------
# Handshake
# ---------------------------------------------------------------------------

func _send_handshake() -> void:
	var packet := JSON.stringify({"type": "display", "role": "player_window"})
	_socket.send_text(packet)


# ---------------------------------------------------------------------------
# Packet handling
# ---------------------------------------------------------------------------

func _drain_packets() -> void:
	while _socket.get_available_packet_count() > 0:
		var raw := _socket.get_packet().get_string_from_utf8()
		_handle_packet(raw)


func _handle_packet(raw: String) -> void:
	var data = JSON.parse_string(raw)
	if not data is Dictionary:
		push_warning("PlayerClient: received non-dict packet, ignoring")
		return

	var msg_type: String = data.get("msg", "")
	match msg_type:
		"ping":
			# DM heartbeat — acknowledge liveness, no render update needed
			print("PlayerClient: ping from DM")
		"state":
			# Full render-state snapshot (Phase 4 will flesh this out)
			state_received.emit(data)
		"delta":
			# Incremental update (Phase 4)
			state_received.emit(data)
		_:
			if msg_type != "":
				push_warning("PlayerClient: unknown msg type '%s'" % msg_type)
