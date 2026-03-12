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
	GameState.windows.append(get_tree().root.get_window_id())
	add_child(DMWindowScene.instantiate())
	print("Main: running as DM host")
	# Defer launch so NetworkManager's _ready() finishes before the child
	# process tries to connect.
	call_deferred("_launch_player_process")


func _launch_player_process() -> void:
	var exe := OS.get_executable_path()
	var args: Array[String] = []
	# In editor/dev builds the executable is the Godot editor itself, so
	# we must tell it which project to open.
	if OS.has_feature("editor"):
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	# "--" marks the start of user args so the engine won't try to parse
	# "--player-window" as an engine flag.
	args.append_array(["--", "--player-window"])
	var pid := OS.create_process(exe, args)
	if pid > 0:
		print("Main: launched Player window process (pid=%d)" % pid)
	else:
		push_error("Main: failed to launch Player window process")


# ---------------------------------------------------------------------------
# Player mode
# ---------------------------------------------------------------------------

func _start_player_mode() -> void:
	get_tree().root.title = "Omni-Crawl — Players"
	add_child(PlayerMainScene.instantiate())
	print("Main: running as Player display client")


# ---------------------------------------------------------------------------
# Shutdown
# ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
