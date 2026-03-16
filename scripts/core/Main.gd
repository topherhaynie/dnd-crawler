extends Node

# ---------------------------------------------------------------------------
# Main — entry point.  Detects whether this OS process should run as the
# DM host or as a Player display client based on the "--player-window"
# command-line user argument.
#
# Architecture:
#   DM process     — authoritative server; runs game logic, hosts the WS
#                    server on port 9090, auto-launches a sibling Player
#                    process at startup.
#   Player process — dumb renderer; connects to the DM's WS server and draws
#                    whatever state it receives.  No game logic lives here.
#
# Spawning an additional Player window later is just one more
# _launch_player_process() call — each process is a fully independent OS
# window, which avoids all macOS window-grouping issues.
# ---------------------------------------------------------------------------

const DMWindowScene: PackedScene = preload("res://scenes/DMWindow.tscn")
const PlayerMainScene: PackedScene = preload("res://scenes/PlayerMain.tscn")


func _game_state() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var svc := registry.get_service("GameState") as Node
		if svc == null:
			svc = registry.get_service("GameStateAdapter") as Node
		return svc
	return null


func _network_manager() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var svc := registry.get_service("Network") as Node
		if svc == null:
			svc = registry.get_service("NetworkAdapter") as Node
		if svc != null:
			return svc
	return null


func _ready() -> void:
	if _is_player_mode():
		_start_player_mode()
	else:
		_start_dm_mode()


# ---------------------------------------------------------------------------
# Mode detection
# ---------------------------------------------------------------------------

func _is_player_mode() -> bool:
	# User args are passed after the "--" separator, e.g.:
	#   godot --path /project -- --player-window
	# and are read with get_cmdline_user_args() to avoid clashing with
	# any Godot engine flags.
	return "--player-window" in OS.get_cmdline_user_args()


# ---------------------------------------------------------------------------
# DM mode
# ---------------------------------------------------------------------------

func _start_dm_mode() -> void:
	get_tree().root.title = "Omni-Crawl — DM"
	var gs_node: Node = _game_state()
	if gs_node == null:
		call_deferred("_deferred_register_window")
	else:
		gs_node.windows.append(get_tree().root.get_window_id())
	# Resize and position the DM window at ~85% of screen
	var screen_size := DisplayServer.screen_get_size()
	var win_size := Vector2i(
		int(screen_size.x * 0.85),
		int(screen_size.y * 0.85))
	DisplayServer.window_set_size(win_size)
	var center_pos := Vector2i(
		int((screen_size.x - win_size.x) * 0.5),
		int((screen_size.y - win_size.y) * 0.5))
	DisplayServer.window_set_position(center_pos)
	# Start WS server before spawning the Player process so the child can connect.
	# NetworkService may be added deferred by ServiceBootstrap; retry until available.
	call_deferred("_ensure_network_started")
	add_child(DMWindowScene.instantiate())
	print("Main: running as DM host")


func _ensure_network_started() -> void:
	var nm := _network_manager()
	if nm != null and nm.has_method("start_server"):
		nm.start_server()
		return
	# Try again next idle until the service appears.
	call_deferred("_ensure_network_started")


func _deferred_register_window() -> void:
	var gs_node: Node = _game_state()
	if gs_node == null:
		call_deferred("_deferred_register_window")
		return
	gs_node.windows.append(get_tree().root.get_window_id())


# ---------------------------------------------------------------------------
# Player mode
# ---------------------------------------------------------------------------

func _start_player_mode() -> void:
	get_tree().root.title = "Omni-Crawl — Players"
	# Offset from centre so both windows are visible side-by-side on start
	var screen_size := DisplayServer.screen_get_size()
	var win_size := Vector2i(
		int(screen_size.x * 0.85),
		int(screen_size.y * 0.85))
	DisplayServer.window_set_size(win_size)
	var center_pos := Vector2i(
		int((screen_size.x - win_size.x) * 0.5),
		int((screen_size.y - win_size.y) * 0.5))
	DisplayServer.window_set_position(center_pos + Vector2i(80, 80))
	add_child(PlayerMainScene.instantiate())
	print("Main: running as Player display client")


# ---------------------------------------------------------------------------
# Shutdown
# ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
