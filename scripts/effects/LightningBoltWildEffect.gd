extends ShaderEffectScene
class_name LightningBoltWildEffect

const _SHADER: Shader = preload("res://assets/effects/lightning_bolt_wild.gdshader")

func _get_shader() -> Shader: return _SHADER
func _get_is_one_shot() -> bool: return true
func _get_one_shot_duration() -> float: return 1.5
