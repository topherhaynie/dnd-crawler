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

var _client: PlayerClient = null
var _player_window: PlayerWindow = null


func _ready() -> void:
	_player_window = PlayerWindowScene.instantiate() as PlayerWindow
	_player_window.name = "PlayerWindow"
	add_child(_player_window)
	if _player_window.has_signal("fog_snapshot_applied"):
		_player_window.fog_snapshot_applied.connect(_on_fog_snapshot_applied)

	# WebSocket client — connect to DM host
	_client = load("res://scripts/player/PlayerClient.gd").new() as PlayerClient
	_client.name = "PlayerClient"
	_client.state_received.connect(_on_state_received)
	add_child(_client)

	Log.info("PlayerMain", "ready — connecting to DM server")


# ---------------------------------------------------------------------------
# State updates from DM
# ---------------------------------------------------------------------------

func _on_state_received(data: Dictionary) -> void:
	if _player_window != null:
		_player_window.on_state(data)


func _on_fog_snapshot_applied(payload: Dictionary) -> void:
	if _client != null:
		Log.debug("PlayerMain", "sending display_sync_applied (stamp_bytes=%d stamp_hash=%d)" % [int(payload.get("snapshot_bytes", -1)), int(payload.get("snapshot_hash", -1))])
		_client.send_display_sync_applied(payload)
