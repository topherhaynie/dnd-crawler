extends RefCounted
class_name SRDLibraryManager

# ---------------------------------------------------------------------------
# SRDLibraryManager — typed coordinator for the SRD library domain.
#
# Owned by ServiceRegistry.srd.  All callers access SRD operations
# through manager methods — never via `registry.srd.service` directly.
# ---------------------------------------------------------------------------

var service: ISRDLibraryService = null


func load_library() -> void:
	if service == null:
		return
	service.load_library()


func get_monsters(p_ruleset: String) -> Array:
	if service == null:
		return []
	return service.get_monsters(p_ruleset)


func get_monster(index: String, p_ruleset: String) -> StatblockData:
	if service == null:
		return null
	return service.get_monster(index, p_ruleset)


func get_spells(p_ruleset: String) -> Array:
	if service == null:
		return []
	return service.get_spells(p_ruleset)


func get_spell(index: String, p_ruleset: String) -> SpellData:
	if service == null:
		return null
	return service.get_spell(index, p_ruleset)


func get_equipment(p_ruleset: String) -> Array:
	if service == null:
		return []
	return service.get_equipment(p_ruleset)


func get_conditions(p_ruleset: String) -> Array:
	if service == null:
		return []
	return service.get_conditions(p_ruleset)


func get_classes(p_ruleset: String) -> Array:
	if service == null:
		return []
	return service.get_classes(p_ruleset)


func get_races(p_ruleset: String) -> Array:
	if service == null:
		return []
	return service.get_races(p_ruleset)


func get_feats(p_ruleset: String) -> Array:
	if service == null:
		return []
	return service.get_feats(p_ruleset)


func get_feat(index: String, p_ruleset: String) -> Dictionary:
	if service == null:
		return {}
	return service.get_feat(index, p_ruleset)


func search(query: String, category: String, p_ruleset: String) -> Array:
	if service == null:
		return []
	return service.search(query, category, p_ruleset)


func get_version() -> String:
	if service == null:
		return ""
	return service.get_version()


func get_monster_image_url(index: String) -> String:
	if service == null:
		return ""
	return service.get_monster_image_url(index)


func get_cached_monster_image(index: String) -> Image:
	if service == null:
		return null
	return service.get_cached_monster_image(index)


func prefetch_all_monster_images() -> void:
	if service == null:
		return
	service.prefetch_all_monster_images()


func check_for_updates(version_url: String) -> void:
	if service == null:
		return
	service.check_for_updates(version_url)
