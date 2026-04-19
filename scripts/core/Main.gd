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


func _game_state() -> GameStateManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.game_state == null:
		return null
	return registry.game_state


func _network_manager() -> INetworkService:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.network == null:
		return null
	return registry.network.service


func _ready() -> void:
	# Prevent Godot from auto-quitting so we can show an unsaved-changes
	# prompt in the DM process before the window closes.
	get_tree().auto_accept_quit = false
	if _is_player_mode():
		_start_player_mode()
	else:
		_start_dm_mode()
	# Defer maximize so the root viewport isn't mid-layout while children are added.
	call_deferred("_size_window")


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
# Window sizing
# ---------------------------------------------------------------------------

func _size_window() -> void:
	# Maximized fills the available screen area while keeping the native macOS
	# menu bar and Dock visible.  True native fullscreen (green-button Space)
	# isn't exposed by Godot's DisplayServer — users can trigger it manually.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


# ---------------------------------------------------------------------------
# DM mode
# ---------------------------------------------------------------------------

func _start_dm_mode() -> void:
	get_tree().root.title = "The Vault — DM"
	var gs := _game_state()
	if gs == null:
		call_deferred("_deferred_register_window")
	else:
		gs.add_window(get_tree().root.get_window_id())
	# Start WS server before spawning the Player process so the child can connect.
	# NetworkService may be added deferred by ServiceBootstrap; retry until available.
	call_deferred("_ensure_network_started")
	add_child(DMWindowScene.instantiate())
	Log.info("Main", "running as DM host")


func _ensure_network_started() -> void:
	var nm := _network_manager()
	if nm != null:
		nm.start_server()
		return
	# Try again next idle until the service appears.
	call_deferred("_ensure_network_started")


func _deferred_register_window() -> void:
	var gs := _game_state()
	if gs == null:
		call_deferred("_deferred_register_window")
		return
	gs.add_window(get_tree().root.get_window_id())


# ---------------------------------------------------------------------------
# Player mode
# ---------------------------------------------------------------------------

func _start_player_mode() -> void:
	get_tree().root.title = "The Vault — Players"
	add_child(PlayerMainScene.instantiate())
	Log.info("Main", "running as Player display client")


# ---------------------------------------------------------------------------
# Shutdown
# ---------------------------------------------------------------------------

var _quit_pending: bool = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _quit_pending:
			return
		if _is_player_mode():
			get_tree().quit()
			return
		# DM mode — check for unsaved work before quitting.
		var dm_window: Node = get_node_or_null("DMWindow")
		if dm_window != null and dm_window.has_method("has_unsaved_changes") and dm_window.has_unsaved_changes():
			_quit_pending = true
			# prompt_save_before_quit is async; it either calls quit() when the
			# user confirms or returns silently on cancel.
			_begin_quit_prompt(dm_window)
		else:
			get_tree().quit()


func _begin_quit_prompt(dm_window: Node) -> void:
	await dm_window.prompt_save_before_quit()
	# If we reach here the user canceled — allow future quit attempts.
	_quit_pending = false
