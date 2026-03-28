extends IUIThemeService
class_name UIThemeService

## UIThemeService — concrete service that stores the active theme preset
## and persists the choice to disk via ConfigFile.

const _CFG_PATH: String = "user://data/ui_theme.cfg"
const _SECTION: String = "ui_theme"
const _KEY: String = "preset"

var _current_theme: int = UIThemeData.ThemePreset.FLAT_DARK


func load_persisted() -> void:
	## Load the persisted theme from disk.  Called eagerly by ServiceBootstrap
	## so the theme is available before any UI reads it.  Safe to call before
	## the node enters the tree (ConfigFile does not require tree access).
	_load()


func get_theme() -> int:
	return _current_theme


func set_theme(preset: int) -> void:
	if preset == _current_theme:
		return
	_current_theme = preset
	_save()
	theme_changed.emit(preset)


func get_available_themes() -> Array[int]:
	return UIThemeData.get_all_presets()


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func _save() -> void:
	var dir_path: String = _CFG_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION, _KEY, _current_theme)
	var err: Error = cfg.save(_CFG_PATH)
	if err != OK:
		push_warning("UIThemeService._save: failed to write %s (error %d)" % [_CFG_PATH, err])


func _load() -> void:
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(_CFG_PATH)
	if err != OK:
		return # file missing or corrupt — keep default
	var val: Variant = cfg.get_value(_SECTION, _KEY, UIThemeData.ThemePreset.FLAT_DARK)
	if val is int:
		_current_theme = val as int
