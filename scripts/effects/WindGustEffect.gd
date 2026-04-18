extends ShaderEffectScene
class_name WindGustEffect

# Wind Gust uses the magic_aura shader (swirling motion).
const _SHADER: Shader = preload("res://assets/effects/magic_aura.gdshader")

func _get_shader() -> Shader: return _SHADER
func _get_is_one_shot() -> bool: return false
