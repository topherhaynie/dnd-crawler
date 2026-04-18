extends RefCounted
class_name Log

## Lightweight structured logger.
##
## Usage:
##   Log.info("MapView", "loaded map '%s'" % map.map_name)
##   Log.warn("FogSystem", "viewport not ready")
##   Log.error("Network", "peer %d lost" % peer_id)
##   Log.debug("FogSystem", "bake took %.1fms" % elapsed)
##
## Log levels:
##   DEBUG < INFO < WARN < ERROR
##
## Debug mode:
##   Enabled automatically when running from the editor or with --debug,
##   or by setting the environment variable THE_VAULT_DEBUG=1.
##   Debug mode sets the log level to DEBUG and enables developer features
##   (e.g. DM arrow-key player movement).
##
## At release, set `Log.level = Log.Level.WARN` to suppress chatty output.

enum Level {DEBUG, INFO, WARN, ERROR, NONE}

## True when the game is running in a debug context.
static var debug_mode: bool = _detect_debug_mode()

## Current threshold — messages below this level are silently dropped.
static var level: Level = Level.DEBUG if debug_mode else Level.INFO


static func _detect_debug_mode() -> bool:
	if OS.is_debug_build():
		return true
	var env: String = OS.get_environment("THE_VAULT_DEBUG")
	return env == "1" or env.to_lower() == "true"


static func debug(tag: String, msg: String) -> void:
	if level <= Level.DEBUG:
		print("[DEBUG] %s: %s" % [tag, msg])


static func info(tag: String, msg: String) -> void:
	if level <= Level.INFO:
		print("[INFO]  %s: %s" % [tag, msg])


static func warn(tag: String, msg: String) -> void:
	if level <= Level.WARN:
		push_warning("%s: %s" % [tag, msg])


static func error(tag: String, msg: String) -> void:
	if level <= Level.ERROR:
		push_error("%s: %s" % [tag, msg])
