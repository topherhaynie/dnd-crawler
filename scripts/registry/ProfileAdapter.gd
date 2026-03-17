extends Node
class_name ProfileAdapter

var _service: Object = null

func set_service(s: Object) -> void:
	_service = s

func get_profiles() -> Array:
	if _service and _service.has_method("get_profiles"):
		return _service.get_profiles()
	return []

func get_profile_by_id(id: String):
	if _service and _service.has_method("get_profile_by_id"):
		return _service.get_profile_by_id(id)
	return null

func add_profile(profile: Dictionary) -> void:
	if _service and _service.has_method("add_profile"):
		_service.add_profile(profile)

func remove_profile(id: String) -> void:
	if _service and _service.has_method("remove_profile"):
		_service.remove_profile(id)

func save_profiles() -> void:
	if _service and _service.has_method("save_profiles"):
		_service.save_profiles()

func load_profiles() -> void:
	if _service and _service.has_method("load_profiles"):
		_service.load_profiles()

func register_player(player_id: String) -> void:
	if _service and _service.has_method("register_player"):
		_service.register_player(player_id)
