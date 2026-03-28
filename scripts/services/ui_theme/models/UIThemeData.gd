extends RefCounted
class_name UIThemeData

## UIThemeData — theme preset enum, display names, shader config, and accent palettes.
##
## Themes use a static procedural chrome shader for the full-window background
## (brushed metal, curved chrome, forged hammered, iridescent) plus
## StyleBoxFlat panel/button colours derived from the game icon's palette:
## dark steel-blue base RGB(23,26,31) → mid RGB(73,82,92) → highlight RGB(198,202,205).

enum ThemePreset {
	FLAT_DARK = 0,
	BRUSHED_DARK_METAL = 1,
	BRIGHT_CHROME = 2,
	FORGED_METAL = 3,
	HOLOGRAPHIC = 4,
}


static func get_display_name(preset: int) -> String:
	match preset:
		ThemePreset.FLAT_DARK:          return "Flat Dark"
		ThemePreset.BRUSHED_DARK_METAL: return "Steel Vault"
		ThemePreset.BRIGHT_CHROME:      return "Silver Chrome"
		ThemePreset.FORGED_METAL:       return "Forged Iron"
		ThemePreset.HOLOGRAPHIC:        return "Arcane"
	return "Unknown"


static func get_all_presets() -> Array[int]:
	return [
		ThemePreset.FLAT_DARK,
		ThemePreset.BRUSHED_DARK_METAL,
		ThemePreset.BRIGHT_CHROME,
		ThemePreset.FORGED_METAL,
		ThemePreset.HOLOGRAPHIC,
	]


static func get_shader_mode(preset: int) -> int:
	## Returns the chrome_ui.gdshader theme_mode uniform value (1-4),
	## or 0 for FLAT_DARK which uses no shader.
	match preset:
		ThemePreset.BRUSHED_DARK_METAL: return 1
		ThemePreset.BRIGHT_CHROME:      return 2
		ThemePreset.FORGED_METAL:       return 3
		ThemePreset.HOLOGRAPHIC:        return 4
	return 0


static func get_shader_colors(preset: int) -> Dictionary:
	## Returns { "base": Color, "highlight": Color, "edge_glow": Color }
	## for the chrome_ui.gdshader uniforms.
	## base_color is the darkest the surface gets; highlight_color is the
	## brightest (at peak grain + peak band, ~60-65% toward highlight).
	match preset:
		ThemePreset.BRUSHED_DARK_METAL:
			return {
				"base":       Color(0.05, 0.06, 0.08),
				"highlight":  Color(0.52, 0.58, 0.68),
				"edge_glow":  Color(0.28, 0.42, 0.65),
			}
		ThemePreset.BRIGHT_CHROME:
			return {
				"base":       Color(0.07, 0.08, 0.10),
				"highlight":  Color(0.62, 0.68, 0.78),
				"edge_glow":  Color(0.35, 0.50, 0.75),
			}
		ThemePreset.FORGED_METAL:
			return {
				"base":       Color(0.06, 0.05, 0.04),
				"highlight":  Color(0.58, 0.42, 0.28),
				"edge_glow":  Color(0.55, 0.35, 0.12),
			}
		ThemePreset.HOLOGRAPHIC:
			return {
				"base":       Color(0.06, 0.05, 0.09),
				"highlight":  Color(0.46, 0.36, 0.62),
				"edge_glow":  Color(0.40, 0.25, 0.65),
			}
	# FLAT_DARK has no shader — return empty (should not be called)
	return {}


static func get_accent_palette(preset: int) -> Dictionary:
	## Returns a dictionary of accent colours for the given theme.
	##
	## Keys:
	##   pressed_bg      — Color for pressed/active button background
	##   pressed_border  — Color for pressed/active button left-border
	##   hover_bg        — Color for button hover state background
	##   normal_bg       — Color for button normal state background
	##   disabled_bg     — Color for button disabled state background
	##   label_tint      — Color for section header / context labels
	##   selected_bg     — Color for selected card background (BundleBrowser)
	##   selected_border — Color for selected card border
	##   panel_bg        — Color for panel background
	##   panel_border    — Color for panel border
	match preset:
		ThemePreset.BRUSHED_DARK_METAL:
			# Steel-blue palette matching the game icon
			return {
				"pressed_bg":      Color(0.20, 0.38, 0.65, 0.35),
				"pressed_border":  Color(0.35, 0.55, 0.85, 0.65),
				"hover_bg":        Color(0.16, 0.18, 0.22, 1.0),
				"normal_bg":       Color(0.12, 0.13, 0.16, 1.0),
				"disabled_bg":     Color(0.09, 0.10, 0.12, 1.0),
				"label_tint":      Color(0.68, 0.72, 0.78),
				"selected_bg":     Color(0.16, 0.26, 0.44, 1.0),
				"selected_border": Color(0.35, 0.55, 0.85),
				"panel_bg":        Color(0.09, 0.10, 0.12, 0.92),
				"panel_border":    Color(0.22, 0.26, 0.32),
			}
		ThemePreset.BRIGHT_CHROME:
			# Lighter silver tones with cool-blue accent
			return {
				"pressed_bg":      Color(0.25, 0.45, 0.78, 0.35),
				"pressed_border":  Color(0.40, 0.60, 0.95, 0.65),
				"hover_bg":        Color(0.22, 0.23, 0.26, 1.0),
				"normal_bg":       Color(0.17, 0.18, 0.20, 1.0),
				"disabled_bg":     Color(0.13, 0.14, 0.16, 1.0),
				"label_tint":      Color(0.75, 0.78, 0.84),
				"selected_bg":     Color(0.20, 0.32, 0.50, 1.0),
				"selected_border": Color(0.40, 0.60, 0.95),
				"panel_bg":        Color(0.13, 0.14, 0.16, 0.92),
				"panel_border":    Color(0.30, 0.33, 0.38),
			}
		ThemePreset.FORGED_METAL:
			# Dark warm iron with amber accent
			return {
				"pressed_bg":      Color(0.60, 0.38, 0.12, 0.35),
				"pressed_border":  Color(0.75, 0.50, 0.18, 0.65),
				"hover_bg":        Color(0.18, 0.15, 0.12, 1.0),
				"normal_bg":       Color(0.14, 0.12, 0.10, 1.0),
				"disabled_bg":     Color(0.10, 0.09, 0.08, 1.0),
				"label_tint":      Color(0.75, 0.66, 0.52),
				"selected_bg":     Color(0.28, 0.20, 0.10, 1.0),
				"selected_border": Color(0.75, 0.50, 0.18),
				"panel_bg":        Color(0.10, 0.08, 0.07, 0.92),
				"panel_border":    Color(0.26, 0.20, 0.14),
			}
		ThemePreset.HOLOGRAPHIC:
			# Dark violet with purple accent
			return {
				"pressed_bg":      Color(0.45, 0.25, 0.70, 0.30),
				"pressed_border":  Color(0.55, 0.35, 0.85, 0.60),
				"hover_bg":        Color(0.16, 0.14, 0.22, 1.0),
				"normal_bg":       Color(0.12, 0.10, 0.17, 1.0),
				"disabled_bg":     Color(0.09, 0.08, 0.13, 1.0),
				"label_tint":      Color(0.70, 0.65, 0.82),
				"selected_bg":     Color(0.22, 0.16, 0.36, 1.0),
				"selected_border": Color(0.55, 0.35, 0.85),
				"panel_bg":        Color(0.08, 0.07, 0.12, 0.92),
				"panel_border":    Color(0.22, 0.18, 0.32),
			}
	# FLAT_DARK (default / fallback) — neutral dark grey
	return {
		"pressed_bg":      Color(0.25, 0.45, 0.78, 0.35),
		"pressed_border":  Color(0.35, 0.55, 0.85, 0.70),
		"hover_bg":        Color(0.22, 0.22, 0.24, 1.0),
		"normal_bg":       Color(0.16, 0.16, 0.18, 1.0),
		"disabled_bg":     Color(0.12, 0.12, 0.14, 1.0),
		"label_tint":      Color(0.68, 0.68, 0.70),
		"selected_bg":     Color(0.18, 0.28, 0.48, 1.0),
		"selected_border": Color(0.35, 0.55, 0.85),
		"panel_bg":        Color(0.12, 0.12, 0.14, 1.0),
		"panel_border":    Color(0.24, 0.24, 0.26),
	}
