extends Node2D
class_name EffectNode

# ---------------------------------------------------------------------------
# EffectNode — visual renderer for a single DM-placed magic effect.
#
# Contains a centered Sprite2D with a procedural shader material.
# One-shot effects auto-remove when their duration expires.
# Looping effects (duration_sec < 0) persist until manually removed.
# ---------------------------------------------------------------------------

signal effect_finished(id: String)

const FIRE_SHADER: Shader = preload("res://assets/effects/fire.gdshader")
const LIGHTNING_BOLT_SHADER: Shader = preload("res://assets/effects/lightning_bolt.gdshader")
const LIGHTNING_BALL_SHADER: Shader = preload("res://assets/effects/lightning_ball.gdshader")
const FROST_SHADER: Shader = preload("res://assets/effects/frost.gdshader")
const POISON_CLOUD_SHADER: Shader = preload("res://assets/effects/poison_cloud.gdshader")
const HOLY_RADIANCE_SHADER: Shader = preload("res://assets/effects/holy_radiance.gdshader")
const MAGIC_AURA_SHADER: Shader = preload("res://assets/effects/magic_aura.gdshader")
const LIGHTNING_BOLT_WILD_SHADER: Shader = preload("res://assets/effects/lightning_bolt_wild.gdshader")
const BLIZZARD_SHADER: Shader = preload("res://assets/effects/blizzard.gdshader")

## D&D 5e cone half-angle: width = length at the open end.
const CONE_HALF_ANGLE: float = 0.4636476090008172 ## atan(0.5) radians

var effect_id: String = ""
var effect_shape: int = EffectData.EffectShape.CIRCLE

var _sprite: Sprite2D = null
var _material: ShaderMaterial = null
var _elapsed: float = 0.0
var _duration: float = -1.0 ## Negative = looping
var _is_one_shot: bool = false

## 1×1 white pixel image reused for all effect quads.
static var _white_texture: ImageTexture = null

static func _get_white_texture() -> ImageTexture:
	if _white_texture == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color.WHITE)
		_white_texture = ImageTexture.create_from_image(img)
	return _white_texture


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = _get_white_texture()
	_sprite.centered = true
	add_child(_sprite)


func apply_from_data(data: EffectData) -> void:
	effect_id = data.id
	effect_shape = data.shape
	_duration = data.duration_sec
	_is_one_shot = data.duration_sec > 0.0
	_elapsed = 0.0

	# Assign shader
	_material = ShaderMaterial.new()
	_material.shader = _shader_for_type(data.effect_type)
	_material.set_shader_parameter("intensity", data.intensity)
	_material.set_shader_parameter("color_tint", data.color_tint)
	_material.set_shader_parameter("progress", 1.0)
	_material.set_shader_parameter("time_offset", randf() * 100.0)

	match data.shape:
		EffectData.EffectShape.LINE:
			_apply_line(data)
		EffectData.EffectShape.CONE:
			_apply_cone(data)
		_:
			_apply_circle(data)

	_sprite.material = _material


func _apply_circle(data: EffectData) -> void:
	position = data.world_pos
	rotation_degrees = data.rotation_deg
	_sprite.scale = Vector2(data.size_px, data.size_px)
	_material.set_shader_parameter("shape_mode", 0)


func _apply_line(data: EffectData) -> void:
	## LINE: sprite spans from world_pos to world_end. Width = size_px.
	var dir: Vector2 = data.world_end - data.world_pos
	var length: float = dir.length()
	if length < 1.0:
		length = 1.0
	position = (data.world_pos + data.world_end) * 0.5
	rotation = dir.angle() + PI * 0.5 # shader Y axis = along the line
	_sprite.scale = Vector2(data.size_px, length)
	_material.set_shader_parameter("shape_mode", 0)


func _apply_cone(data: EffectData) -> void:
	## CONE: apex at world_pos, direction toward world_end.
	## Bounding quad covers the triangle. Shader cone-masks the fragment.
	var dir: Vector2 = data.world_end - data.world_pos
	var length: float = dir.length()
	if length < 1.0:
		length = 1.0
	# D&D 5e cone: width at mouth = length (half-angle ≈ 26.6°)
	var mouth_width: float = length
	# Sprite centre at midpoint of apex→tip, covering the full triangle
	position = data.world_pos + dir * 0.5
	rotation = dir.angle() - PI * 0.5 # shader Y=0 at apex (click), Y=1 at mouth (drag end)
	_sprite.scale = Vector2(mouth_width, length)
	_material.set_shader_parameter("shape_mode", 1)


func _process(delta: float) -> void:
	if not _is_one_shot:
		return
	_elapsed += delta
	if _elapsed >= _duration:
		# Fade complete — signal removal
		if _material != null:
			_material.set_shader_parameter("progress", 0.0)
		effect_finished.emit(effect_id)
		queue_free()
		return
	# Fade out over the last 20% of duration
	var fade_start: float = _duration * 0.8
	if _elapsed > fade_start:
		var t: float = (_elapsed - fade_start) / (_duration - fade_start)
		if _material != null:
			_material.set_shader_parameter("progress", 1.0 - t)


func _shader_for_type(effect_type: int) -> Shader:
	match effect_type:
		EffectData.EffectType.FIRE:
			return FIRE_SHADER
		EffectData.EffectType.LIGHTNING_BOLT:
			return LIGHTNING_BOLT_SHADER
		EffectData.EffectType.LIGHTNING_BALL:
			return LIGHTNING_BALL_SHADER
		EffectData.EffectType.FROST:
			return FROST_SHADER
		EffectData.EffectType.POISON_CLOUD:
			return POISON_CLOUD_SHADER
		EffectData.EffectType.HOLY_RADIANCE:
			return HOLY_RADIANCE_SHADER
		EffectData.EffectType.MAGIC_AURA:
			return MAGIC_AURA_SHADER
		EffectData.EffectType.LIGHTNING_BOLT_WILD:
			return LIGHTNING_BOLT_WILD_SHADER
		EffectData.EffectType.BLIZZARD:
			return BLIZZARD_SHADER
		_:
			return FIRE_SHADER
