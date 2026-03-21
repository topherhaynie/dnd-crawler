extends Node2D
class_name TokenSprite

# ---------------------------------------------------------------------------
# TokenSprite — lightweight renderer for a single DM-placed token.
#
# Placed as a child of MapView's token_layer Node2D.
# The DM sees all tokens; hidden tokens appear at reduced alpha with a
# "hidden" modulation tint.  Player-side views hide tokens whose
# is_visible_to_players == false entirely.
#
# Children expected in the scene (or created procedurally if absent):
#   _icon   — ColorRect or Sprite2D (placeholder circle drawn via _draw)
#   _label  — Label (DM-only name overlay)
# ---------------------------------------------------------------------------

## Diameter used by MapView._hit_test_tokens() for SELECT/drag.
const TOKEN_DIAMETER_PX: float = 48.0

## Alpha for tokens that are hidden from players (DM view only).
const HIDDEN_ALPHA: float = 0.45

## Category → placeholder icon colour mapping.
const CATEGORY_COLORS: Dictionary = {
	0: Color(0.5, 0.35, 0.2, 1.0),   # DOOR          — brown
	1: Color(0.9, 0.1, 0.1, 1.0),   # TRAP          — red
	2: Color(0.3, 0.3, 0.8, 1.0),   # HIDDEN_OBJECT — blue
	3: Color(0.6, 0.1, 0.8, 1.0),   # SECRET_PASSAGE— purple
	4: Color(0.85, 0.2, 0.2, 1.0),  # MONSTER       — crimson
	5: Color(0.1, 0.7, 0.4, 1.0),   # EVENT         — teal
	6: Color(0.9, 0.7, 0.1, 1.0),   # NPC           — gold
	7: Color(0.5, 0.5, 0.5, 1.0),   # GENERIC       — grey
}

var token_id: String = ""

var _category: int = 0
var _is_dm: bool = false
var _is_visible_to_players: bool = false
var _label_node: Label = null


func _ready() -> void:
	_label_node = Label.new()
	_label_node.name = "TokenLabel"
	_label_node.add_theme_font_size_override("font_size", 11)
	_label_node.add_theme_color_override("font_color", Color.WHITE)
	_label_node.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_label_node.add_theme_constant_override("shadow_offset_x", 1)
	_label_node.add_theme_constant_override("shadow_offset_y", 1)
	_label_node.position = Vector2(-TOKEN_DIAMETER_PX * 0.5, TOKEN_DIAMETER_PX * 0.5 + 2.0)
	add_child(_label_node)


func _draw() -> void:
	var radius: float = TOKEN_DIAMETER_PX * 0.5
	var color: Color = CATEGORY_COLORS.get(_category, Color.GRAY)
	# Filled circle body
	draw_circle(Vector2.ZERO, radius, color)
	# Thin dark border
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, 0.6), 2.0)
	# Hidden badge: "?" overlay for DM when token is hidden from players
	if _is_dm and not _is_visible_to_players:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(-5.0, 6.0),
			"?",
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			14,
			Color(1.0, 1.0, 1.0, 0.9)
		)


## Apply all fields from a TokenData instance.
func apply_from_data(data: TokenData, is_dm: bool) -> void:
	token_id = data.id
	_category = data.category
	_is_dm = is_dm
	_is_visible_to_players = data.is_visible_to_players
	global_position = data.world_pos
	if _label_node != null:
		_label_node.text = data.label
		# Label is only rendered on the DM side.
		_label_node.visible = is_dm
	_refresh_visibility()
	queue_redraw()


## Returns the hit-test diameter for MapView._hit_test_tokens().
func get_token_diameter_px() -> float:
	return TOKEN_DIAMETER_PX


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _refresh_visibility() -> void:
	if _is_dm:
		# DM always sees the token; hidden ones are desaturated/transparent.
		self.visible = true
		self.modulate = Color(1.0, 1.0, 1.0, HIDDEN_ALPHA if not _is_visible_to_players else 1.0)
	else:
		# Player only sees tokens explicitly the DM has revealed.
		self.visible = _is_visible_to_players
		self.modulate = Color.WHITE
