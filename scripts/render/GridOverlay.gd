extends Node2D

# ---------------------------------------------------------------------------
# GridOverlay — GPU-accelerated square / hex grid rendered via a single-quad
# fragment shader.  Replaces the old _draw()-per-cell approach that could
# exhaust the rendering element pool on large maps or small cell sizes.
#
# Usage:
#   - Add as a child of the map Node2D (above the TextureRect, below tokens)
#   - Call apply_map_data(map: MapData) whenever the active map changes
# ---------------------------------------------------------------------------

const GRID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.25)
const GRID_LINE_WIDTH: float = 1.0

var _map: MapData = null
var _rect: ColorRect = null
var _material: ShaderMaterial = null


func _ready() -> void:
	var shader: Shader = preload("res://assets/effects/grid_overlay.gdshader")
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect = ColorRect.new()
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	add_child(_rect)


func apply_map_data(map: MapData) -> void:
	_map = map
	if _rect == null:
		return
	if _map == null:
		_rect.visible = false
		return
	var tex_size: Vector2 = _get_texture_size()
	_rect.visible = true
	_rect.position = Vector2.ZERO
	_rect.size = tex_size
	_material.set_shader_parameter("grid_type", _map.grid_type)
	_material.set_shader_parameter("cell_size", _map.cell_px)
	_material.set_shader_parameter("hex_radius", _map.hex_size)
	_material.set_shader_parameter("grid_offset", _map.grid_offset)
	_material.set_shader_parameter("grid_color", GRID_COLOR)
	_material.set_shader_parameter("line_width", GRID_LINE_WIDTH)
	_material.set_shader_parameter("map_size", tex_size)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_texture_size() -> Vector2:
	var parent_node := get_parent()
	if parent_node == null:
		return Vector2(4096, 4096)
	var img_node: Node = parent_node.get_node_or_null("MapImage")
	if img_node and img_node is TextureRect and img_node.texture:
		return img_node.texture.get_size()
	return Vector2(4096, 4096)
