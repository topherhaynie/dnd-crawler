extends Node

# ---------------------------------------------------------------------------
# PlayerMain — root controller for the Player display process.
#
# Phase 2 responsibilities:
#   • Instantiate PlayerWindow (hosts MapView)
#   • Instantiate PlayerClient and start the WS connection to the DM host
#   • Route state packets → PlayerWindow.on_state()
# ---------------------------------------------------------------------------

const PlayerWindowScene: PackedScene = preload("res://scenes/PlayerWindow.tscn")

var _client: Node = null
var _player_window: Node = null


func _ready() -> void:
	_player_window = PlayerWindowScene.instantiate()
	_player_window.name = "PlayerWindow"
	add_child(_player_window)

	# WebSocket client — connect to DM host
	_client = load("res://scripts/network/PlayerClient.gd").new()
	_client.name = "PlayerClient"
	_client.state_received.connect(_on_state_received)
	add_child(_client)

	print("PlayerMain: ready — connecting to DM server")


# ---------------------------------------------------------------------------
# State updates from DM
# ---------------------------------------------------------------------------

func _on_state_received(data: Dictionary) -> void:
	var msg_type: String = data.get("msg", "unknown")
	if _player_window and _player_window.has_method("on_state"):
		_player_window.on_state(data)
	print("PlayerMain: received state packet (msg=%s)" % msg_type)
