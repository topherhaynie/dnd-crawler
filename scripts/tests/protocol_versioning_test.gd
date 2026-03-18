extends Node

# Minimal test demonstrating protocol_version handling.
# Run this by adding the script to a scene or running with `godot --script`

func _ready() -> void:
    # Instantiate the NetworkService and call its packet handler directly.
    var svc := NetworkService.new()

    # Handshake with protocol_version 1 => no warning expected
    var pkt_v1 := JSON.stringify({
        "type": "display",
        "role": "player_window",
        "viewport_width": 800,
        "viewport_height": 600,
        "protocol_version": 1,
    })
    svc._handle_packet(pkt_v1, 123)

    # Handshake with protocol_version 2 => server should log a warning but accept
    var pkt_v2 := JSON.stringify({
        "type": "display",
        "role": "player_window",
        "viewport_width": 800,
        "viewport_height": 600,
        "protocol_version": 2,
    })
    # Expect: NetworkService: warning: peer uses protocol_version 2
    svc._handle_packet(pkt_v2, 124)

    # Test complete — quit the scene tree if running headless.
    if Engine.is_editor_hint() == false:
        get_tree().quit()
