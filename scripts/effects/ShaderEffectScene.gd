extends Node2D
class_name ShaderEffectScene

# ---------------------------------------------------------------------------
# ShaderEffectScene — base class for all manifest-driven shader effect scenes.
#
# Phase 11 scene contract:
#   • @export var size: float  — uniform radius in pixels applied to the sprite
#   • signal effect_finished   — emitted when a ONE_SHOT effect completes
#
# Concrete subclass must implement _get_shader() → Shader.
# Override _get_is_one_shot() → bool and _get_one_shot_duration() → float
# to make the effect auto-remove after playing once.
# ---------------------------------------------------------------------------

signal effect_finished

## Radius in pixels — set by the placement system before or after _ready().
@export var size: float = 100.0:
	set(v):
		size = v
		_update_scale()

var _sprite: Sprite2D = null
var _material: ShaderMaterial = null
var _elapsed: float = 0.0
var _one_shot: bool = false
var _duration: float = 3.0

static var _white_tex: ImageTexture = null


static func _get_white_tex() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


# ---------------------------------------------------------------------------
# Subclass overrides
# ---------------------------------------------------------------------------

## Return the shader to apply to this effect.  Subclasses must implement this.
func _get_shader() -> Shader:
	return null


## Return true to make this effect auto-remove after _get_one_shot_duration().
func _get_is_one_shot() -> bool:
	return false


## Duration in seconds for ONE_SHOT effects.
func _get_one_shot_duration() -> float:
	return 3.0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_one_shot = _get_is_one_shot()
	_duration = _get_one_shot_duration()

	_sprite = Sprite2D.new()
	_sprite.texture = _get_white_tex()
	_sprite.centered = true
	add_child(_sprite)

	var shader: Shader = _get_shader()
	if shader != null:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("intensity", 1.0)
		_material.set_shader_parameter("progress", 1.0)
		_material.set_shader_parameter("time_offset", randf() * 100.0)
		_material.set_shader_parameter("shape_mode", 0)
		_sprite.material = _material

	_update_scale()


func _update_scale() -> void:
	if _sprite == null:
		return
	_sprite.scale = Vector2(size, size)


func _process(delta: float) -> void:
	if not _one_shot:
		return
	_elapsed += delta
	if _elapsed >= _duration:
		if _material != null:
			_material.set_shader_parameter("progress", 0.0)
		effect_finished.emit()
		queue_free()
		return
	var fade_start: float = _duration * 0.8
	if _elapsed > fade_start and _material != null:
		var t: float = (_elapsed - fade_start) / (_duration - fade_start)
		_material.set_shader_parameter("progress", 1.0 - t)
