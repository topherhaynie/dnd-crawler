extends Node

# ---------------------------------------------------------------------------
# PlayerMain — root controller for the Player display process.
#
# Responsibilities (Phase 1):
#   • Instantiate the PlayerWindow viewport
#   • Instantiate PlayerClient and start the WS connection to the DM host
#   • Wire PlayerClient's state_received signal to the viewport renderer
#
# Phase 4 will expand the viewport rendering substantially; for now we just
# confirm that the process launches, the window appears, and the WS handshake
# succeeds.
# ---------------------------------------------------------------------------

const PlayerWindowScene: PackedScene = preload("res://scenes/PlayerWindow.tscn")

var _client: Node = null


func _ready() -> void:
	# Viewport (the actual display shown on the TV)
	add_child(PlayerWindowScene.instantiate())

	# WebSocket client — connect to DM host
	_client = load("res://scripts/PlayerClient.gd").new()
	_client.name = "PlayerClient"
	_client.state_received.connect(_on_state_received)
	add_child(_client)

	print("PlayerMain: ready — connecting to DM server")


# ---------------------------------------------------------------------------
# State updates from DM
# ---------------------------------------------------------------------------

func _on_state_received(data: Dictionary) -> void:
	# Placeholder: Phase 4 will route data to the map/token/FoW renderers.
	var msg_type: String = data.get("msg", "unknown")
	print("PlayerMain: received state packet (msg=%s)" % msg_type)
