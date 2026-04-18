extends ShaderEffectScene
class_name RingOfFireEffect

const _SHADER: Shader = preload("res://assets/effects/ring_of_fire.gdshader")

func _get_shader() -> Shader: return _SHADER
func _get_is_one_shot() -> bool: return false
