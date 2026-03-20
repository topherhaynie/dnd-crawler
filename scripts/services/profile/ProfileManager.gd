extends RefCounted
class_name ProfileManager

## Profile domain coordinator.
##
## Owns ProfileModel (the authoritative profiles array shared with
## ProfileService via injection). Exposes typed profile operations that save
## via IProfileService and emit profiles_changed.
##
## Access via: get_node("/root/ServiceRegistry").profile

signal profiles_changed()

var service: IProfileService = null
var model: ProfileModel = null

## Direct array access convenience — callers may read model.profiles or use
## this property.  Mutations to the returned Array affect the model in-place
## since Array is a reference type; call save() afterward if persistence is
## required.
var profiles: Array:
	get: return model.profiles if model != null else []
	set(v):
		if model != null:
			model.profiles = v


func get_profiles() -> Array:
	if model != null:
		return model.profiles.duplicate(true)
	if service != null:
		return service.get_profiles()
	return []


func get_profile_by_id(id: String) -> Variant:
	if model != null:
		for p in model.profiles:
			if p is PlayerProfile and str((p as PlayerProfile).id) == id:
				return p
			if p is Dictionary and str((p as Dictionary).get("id", "")) == id:
				return p
	if service != null:
		return service.get_profile_by_id(id)
	return null


func add_profile(profile: PlayerProfile) -> void:
	if service == null:
		return
	service.add_profile(profile)
	if model != null:
		model.profiles = service.get_profiles()
	profiles_changed.emit()


func remove_profile(id: String) -> void:
	if service == null:
		return
	service.remove_profile(id)
	if model != null:
		model.profiles = service.get_profiles()
	profiles_changed.emit()


func update_profile_at(idx: int, profile: PlayerProfile) -> void:
	## Replace the profile at the given index and persist.
	if model == null or idx < 0 or idx >= model.profiles.size():
		return
	model.profiles[idx] = profile
	if service != null:
		service.save_profiles()
	profiles_changed.emit()


## Import: replace all profiles at once (used by the profile import dialog).
func set_all_profiles(arr: Array) -> void:
	if model != null:
		model.profiles = arr
	if service != null:
		service.save_profiles()
	profiles_changed.emit()


func save() -> void:
	if service != null:
		service.save_profiles()


## Alias for call-sites that still use the old save_profiles() name.
func save_profiles() -> void:
	save()


func load() -> void:
	if service == null:
		return
	service.load_profiles()
	if model != null:
		model.profiles = service.get_profiles()
	profiles_changed.emit()
