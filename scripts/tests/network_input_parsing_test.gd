extends Node

# Manual test script for NetworkService input packet parsing.
# To run manually in the editor attach this script to a scene root and run,
# or execute Godot with `--script` pointing at a small runner that instantiates
# this node. This is a smoke test demonstrating logging behavior only.

func _ready():
    print("network_input_parsing_test: starting")
    var svc = preload("res://scripts/services/NetworkService.gd").new()

    var cases = {
        "valid": '{"type":"input","x":0.5,"y":-0.25,"player_id":"player-123"}',
        "missing_x": '{"type":"input","y":0.0,"player_id":"player-123"}',
        "missing_y": '{"type":"input","x":0.0,"player_id":"player-123"}',
        "non_numeric": '{"type":"input","x":"NaN","y":0.0,"player_id":"player-123"}'
    }

    for case_name in cases.keys():
        var payload = cases[case_name]
        print("--- case: %s ---" % case_name)
        svc._handle_packet(payload, 42)

    print("network_input_parsing_test: finished")
