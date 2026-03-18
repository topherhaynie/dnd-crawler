extends Node

# handshake_role_test.gd
# Tiny manual test: connects to local DM WebSocket server and sends a
# display handshake with an explicit `role` field. Run with:
#
#   godot --headless --script scripts/tests/handshake_role_test.gd
#
const SERVER_URL := "ws://127.0.0.1:9090"
const CONNECT_TIMEOUT := 5.0

var _socket: WebSocketPeer = WebSocketPeer.new()
var _connected := false

func _ready() -> void:
    print("handshake_role_test: connecting to %s" % SERVER_URL)
    var err := _socket.connect_to_url(SERVER_URL)
    if err != OK:
        push_error("handshake_role_test: connect_to_url failed err=%d" % err)
        get_tree().quit()
        return
    set_process(true)
    get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(_on_connect_timeout, CONNECT_ONE_SHOT)

func _process(_delta: float) -> void:
    _socket.poll()
    match _socket.get_ready_state():
        WebSocketPeer.STATE_OPEN:
            if not _connected:
                _connected = true
                print("handshake_role_test: connected — sending handshake")
                _send_handshake()
                # allow server to log and echo if desired then quit
                get_tree().create_timer(0.5).timeout.connect(_on_quit_timer, CONNECT_ONE_SHOT)
        WebSocketPeer.STATE_CLOSED:
            if _connected:
                print("handshake_role_test: disconnected")
            get_tree().quit()

func _on_connect_timeout() -> void:
    if not _connected:
        push_warning("handshake_role_test: connect timeout")
        get_tree().quit()

func _send_handshake() -> void:
    var packet := JSON.stringify({
        "type": "display",
        "role": "test_handshake_role",
        "viewport_width": 800,
        "viewport_height": 600,
    })
    _socket.send_text(packet)
    print("handshake_role_test: sent: %s" % packet)

func _on_quit_timer() -> void:
    print("handshake_role_test: exiting")
    get_tree().quit()
