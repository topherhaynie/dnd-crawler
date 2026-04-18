extends ShaderEffectScene
class_name FireWallEffect

const _SHADER: Shader = preload("res://assets/effects/fire_wall.gdshader")

func _get_shader() -> Shader: return _SHADER
func _get_is_one_shot() -> bool: return false
