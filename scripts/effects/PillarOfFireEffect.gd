extends ShaderEffectScene
class_name PillarOfFireEffect

const _SHADER: Shader = preload("res://assets/effects/pillar_of_fire.gdshader")

func _get_shader() -> Shader: return _SHADER
func _get_is_one_shot() -> bool: return true
func _get_one_shot_duration() -> float: return 2.0
