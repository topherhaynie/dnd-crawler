extends CharacterBody2D

class_name PlayerSprite

enum VisionType {NORMAL, DARKVISION}

@onready var sprite: Sprite2D = $Sprite2D
@onready var vision_light: PointLight2D = $PointLight2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var player_id: String = ""
var player_name: String = ""
var base_speed: float = 30.0
var vision_type: int = VisionType.NORMAL
var darkvision_range: float = 60.0
var perception_mod: int = 0
var is_dashing: bool = false
var vision_scale: float = 1.0
var _movement_input: Vector2 = Vector2.ZERO
var _last_nonzero_dir: Vector2 = Vector2.RIGHT
var _remote_smoothing_enabled: bool = false
var _remote_target_position: Vector2 = Vector2.ZERO
var _remote_initialized: bool = false
var _remote_lerp_speed: float = 50.0
var _vision_radius_tween: Tween = null

static var _token_texture: Texture2D = null
static var _radial_light_texture: Texture2D = null
static var _cone_light_texture: Texture2D = null
const _TOKEN_TEXTURE_DIAMETER_PX: float = 48.0


func _ready() -> void:
	if sprite.texture == null:
		sprite.texture = _get_or_create_token_texture()
	vision_light.enabled = true
	vision_light.shadow_enabled = true
	vision_light.blend_mode = Light2D.BLEND_MODE_MIX
	vision_light.energy = 1.4
	vision_light.visibility_layer = 2
	vision_light.range_item_cull_mask = 2
	vision_light.shadow_item_cull_mask = 2
	_remote_target_position = global_position
	_update_visuals()


func _process(delta: float) -> void:
	if not _remote_smoothing_enabled:
		return
	var dist := global_position.distance_to(_remote_target_position)
	if dist > 36.0:
		global_position = _remote_target_position
		return
	global_position = global_position.lerp(_remote_target_position, clampf(delta * _remote_lerp_speed, 0.0, 1.0))


func apply_from_state(data: Dictionary) -> void:
	player_id = str(data.get("id", ""))
	player_name = str(data.get("name", ""))
	base_speed = float(data.get("base_speed", 30.0))
	vision_type = int(data.get("vision_type", VisionType.NORMAL))
	darkvision_range = float(data.get("darkvision_range", 60.0))
	perception_mod = int(data.get("perception_mod", 0))
	is_dashing = bool(data.get("is_dashing", false))
	var default_vision_scale := 0.5 if is_dashing else 1.0
	vision_scale = clampf(float(data.get("vision_scale", default_vision_scale)), 0.1, 4.0)
	var facing := float(data.get("facing", rotation))
	if vision_type == VisionType.NORMAL:
		_last_nonzero_dir = Vector2.RIGHT.rotated(facing).normalized()
	rotation = facing
	var token_diameter_px := float(data.get("token_diameter_px", _TOKEN_TEXTURE_DIAMETER_PX))
	set_token_diameter_px(token_diameter_px)
	var pos_d: Dictionary = data.get("position", {"x": 0.0, "y": 0.0})
	var pos := Vector2(float(pos_d.get("x", 0.0)), float(pos_d.get("y", 0.0)))
	if _remote_smoothing_enabled:
		_remote_target_position = pos
		if not _remote_initialized:
			_remote_initialized = true
			global_position = pos
	else:
		global_position = pos
		_remote_target_position = pos
	_update_visuals()


func set_movement_input(vec: Vector2) -> void:
	_movement_input = vec
	if vec.length_squared() > 0.000001:
		_last_nonzero_dir = vec.normalized()
		rotation = _last_nonzero_dir.angle()


func enable_remote_smoothing(enabled: bool) -> void:
	_remote_smoothing_enabled = enabled
	if not enabled:
		_remote_initialized = false


func get_fog_reveal_position() -> Vector2:
	if _remote_smoothing_enabled:
		return _remote_target_position
	return global_position


func set_token_diameter_px(diameter_px: float) -> void:
	var factor := maxf(diameter_px / _TOKEN_TEXTURE_DIAMETER_PX, 0.15)
	sprite.scale = Vector2.ONE * factor
	collision.scale = Vector2.ONE * factor


func step_authoritative_motion(_delta: float, speed_px_per_second: float, bounds: Vector2) -> void:
	velocity = _movement_input * speed_px_per_second
	move_and_slide()
	if bounds != Vector2.ZERO:
		global_position = Vector2(
			clampf(global_position.x, 0.0, bounds.x),
			clampf(global_position.y, 0.0, bounds.y)
		)


func _update_visuals() -> void:
	sprite.modulate = _color_from_id(player_id)
	if vision_type == VisionType.DARKVISION:
		vision_light.texture = _get_or_create_radial_light_texture()
	else:
		vision_light.texture = _get_or_create_cone_light_texture()
	var radius_px := darkvision_range if vision_type == VisionType.DARKVISION else 60.0
	radius_px *= vision_scale
	update_vision_radius(radius_px)
	if vision_type == VisionType.NORMAL:
		rotation = _last_nonzero_dir.angle()


func update_vision_radius(radius: float) -> void:
	var safe_radius := maxf(radius, 8.0)
	var target_scale := maxf(safe_radius / 60.0, 0.2) * 2.0
	if _vision_radius_tween and _vision_radius_tween.is_running():
		_vision_radius_tween.kill()
	_vision_radius_tween = create_tween()
	_vision_radius_tween.set_trans(Tween.TRANS_SINE)
	_vision_radius_tween.set_ease(Tween.EASE_OUT)
	_vision_radius_tween.tween_property(vision_light, "texture_scale", target_scale, 0.2)


func _color_from_id(id: String) -> Color:
	var id_hash := hash(id)
	var hue := absf(float(id_hash % 1000) / 1000.0)
	return Color.from_hsv(hue, 0.75, 1.0, 1.0)


static func _get_or_create_token_texture() -> Texture2D:
	if _token_texture != null:
		return _token_texture
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(24, 24)
	for y in range(48):
		for x in range(48):
			var d := center.distance_to(Vector2(x, y))
			if d <= 20.0:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
			elif d <= 22.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.9))
	_token_texture = ImageTexture.create_from_image(img)
	return _token_texture


static func _get_or_create_radial_light_texture() -> Texture2D:
	if _radial_light_texture != null:
		return _radial_light_texture
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	for y in range(size):
		for x in range(size):
			var d := center.distance_to(Vector2(x, y))
			if d > radius:
				continue
			var t := 1.0 - (d / radius)
			img.set_pixel(x, y, Color(1, 1, 1, t * t))
	_radial_light_texture = ImageTexture.create_from_image(img)
	return _radial_light_texture


static func _get_or_create_cone_light_texture() -> Texture2D:
	if _cone_light_texture != null:
		return _cone_light_texture
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	var half_angle := deg_to_rad(55.0)
	for y in range(size):
		for x in range(size):
			var v := Vector2(x, y) - center
			var d := v.length()
			if d > radius or d <= 0.01:
				continue
			var ang := absf(wrapf(v.angle(), -PI, PI))
			if ang > half_angle:
				continue
			var t := 1.0 - (d / radius)
			img.set_pixel(x, y, Color(1, 1, 1, t * t))
	_cone_light_texture = ImageTexture.create_from_image(img)
	return _cone_light_texture
