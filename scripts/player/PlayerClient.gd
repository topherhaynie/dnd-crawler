extends Node
class_name PlayerClient

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

const JsonUtilsScript = preload("res://scripts/utils/JsonUtils.gd")


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
	# Match the DM server's buffer sizes so large map payloads and fog
	# snapshot chunks can be received without dropping the connection.
	_socket.inbound_buffer_size = 4 * 1024 * 1024 # 4 MiB
	_socket.outbound_buffer_size = 1 * 1024 * 1024 # 1 MiB
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
	var vp_size := get_viewport().get_visible_rect().size
	var mode := DisplayServer.window_get_mode()
	var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var packet := JSON.stringify({
		"type": "display",
		"role": "player_window",
		"viewport_width": vp_size.x,
		"viewport_height": vp_size.y,
		"fullscreen": is_fs,
		"protocol_version": 1,
	})
	_socket.send_text(packet)
	# Watch for subsequent window resizes and report them to the DM so its
	# indicator box stays in sync with the actual visible area.
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	if not _connected:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var mode := DisplayServer.window_get_mode()
	var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	_socket.send_text(JSON.stringify({
		"type": "viewport_resize",
		"viewport_width": vp_size.x,
		"viewport_height": vp_size.y,
		"fullscreen": is_fs,
		"protocol_version": 1,
	}))


func send_display_sync_applied(payload: Dictionary) -> void:
	if not _connected:
		return
	var packet := {
		"type": "display_sync_applied",
		"snapshot_bytes": int(payload.get("snapshot_bytes", -1)),
		"snapshot_hash": int(payload.get("snapshot_hash", -1)),
		"protocol_version": 1,
	}
	_socket.send_text(JSON.stringify(packet))


# ---------------------------------------------------------------------------
# Packet handling
# ---------------------------------------------------------------------------

func _drain_packets() -> void:
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		# WebSocketMultiplayerPeer sends a binary framing packet to every new
		# connection as part of Godot's multiplayer handshake. Our protocol is
		# JSON-only (starts with '{'), so we silently skip anything else.
		if bytes.is_empty() or bytes[0] != 123: # 123 == ord('{')
			continue
		_handle_packet(bytes.get_string_from_utf8())


func _handle_packet(raw: String) -> void:
	var data = JsonUtilsScript.parse_json_text(raw)
	if not data is Dictionary:
		push_warning("PlayerClient: received non-dict packet, ignoring")
		return

	var msg_type: String = data.get("msg", "")
	match msg_type:
		"ping":
			# DM heartbeat — acknowledge liveness, no render update needed
			print("PlayerClient: ping from DM")
		"map_loaded":
			# Map broadcast from DM — forward to PlayerWindow
			state_received.emit(data)
		"map_updated":
			# Grid/scale change — forward without triggering camera reset
			state_received.emit(data)
		"fog_updated":
			# Fog-only update — lightweight DM-authoritative reveal state
			state_received.emit(data)
		"fog_delta":
			# Fog delta update — highest-frequency visibility channel
			state_received.emit(data)
		"fog_brush_stroke":
			# Real-time GPU fog brush stroke from DM
			state_received.emit(data)
		"fog_state_snapshot":
			# Atomic fog gamestate snapshot (initial sync / manual resync)
			state_received.emit(data)
		"fog_state_snapshot_begin":
			# Chunked fog snapshot start marker
			state_received.emit(data)
		"fog_state_snapshot_chunk":
			# Chunked fog snapshot payload
			state_received.emit(data)
		"fog_state_snapshot_end":
			# Chunked fog snapshot completion marker
			state_received.emit(data)
		"camera_update":
			# DM moved the player view — apply immediately
			state_received.emit(data)
		"fog_overlay_toggle":
			# DM toggled fog overlay effect
			state_received.emit(data)
		"flashlights_only_toggle":
			# DM toggled flashlights-only fog mode
			state_received.emit(data)
		"window_resize":
			# DM requests a specific window size — only honour when not fullscreen
			var w := int(data.get("width", 0))
			var h := int(data.get("height", 0))
			if w > 0 and h > 0:
				var mode := DisplayServer.window_get_mode()
				var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
				if not is_fs:
					DisplayServer.window_set_size(Vector2i(w, h))
		"token_state":
			# Full token snapshot — sent on initial display connect
			state_received.emit(data)
		"token_added":
			# A new visible token was placed on the map
			state_received.emit(data)
		"token_updated":
			# An existing token's properties changed (position, LOS, shape…)
			state_received.emit(data)
		"token_removed":
			# A token was deleted or hidden from players
			state_received.emit(data)
		"token_moved":
			# Lightweight position update for a live token
			state_received.emit(data)
		"puzzle_notes_state":
			# Revealed puzzle notes from all tokens (independent of visibility)
			state_received.emit(data)
		"measurement_state", "measurement_added", "measurement_removed", \
		"measurement_moved", "measurement_updated":
			state_received.emit(data)
		"state":
			# Full render-state snapshot (Phase 4 will flesh this out)
			state_received.emit(data)
		"delta":
			# Incremental update (Phase 4)
			state_received.emit(data)
		_:
			if msg_type != "":
				push_warning("PlayerClient: unknown msg type '%s'" % msg_type)
