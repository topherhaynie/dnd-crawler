extends ShaderEffectScene
class_name PoisonCloudEffect

const _SHADER: Shader = preload("res://assets/effects/poison_cloud.gdshader")

func _get_shader() -> Shader: return _SHADER
func _get_is_one_shot() -> bool: return false
