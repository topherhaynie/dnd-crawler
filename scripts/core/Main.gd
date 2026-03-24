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
const SPLASH_ICON: Texture2D = preload("res://assets/icon.png")

var _splash: CanvasLayer = null


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
	_show_splash()
	if _is_player_mode():
		_start_player_mode()
	else:
		_start_dm_mode()
	# Remove splash after one frame so the scene tree is visible underneath.
	call_deferred("_fade_splash")


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
	get_tree().root.title = "The Vault — DM"
	var gs := _game_state()
	if gs == null:
		call_deferred("_deferred_register_window")
	else:
		gs.add_window(get_tree().root.get_window_id())
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
# Splash overlay
# ---------------------------------------------------------------------------

func _show_splash() -> void:
	_splash = CanvasLayer.new()
	_splash.layer = 100

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash.add_child(bg)

	var icon := TextureRect.new()
	icon.texture = SPLASH_ICON
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.custom_minimum_size = Vector2(256, 256)
	icon.offset_left = -128
	icon.offset_top = -128
	icon.offset_right = 128
	icon.offset_bottom = 128
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash.add_child(icon)

	add_child(_splash)


func _fade_splash() -> void:
	if _splash == null:
		return
	var tween: Tween = create_tween()
	# Brief pause then fade over 0.4s
	tween.tween_interval(0.3)
	for child: Node in _splash.get_children():
		if child is CanvasItem:
			tween.parallel().tween_property(child, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_splash.queue_free)
	tween.tween_callback(func() -> void: _splash = null)


# ---------------------------------------------------------------------------
# Shutdown
# ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
