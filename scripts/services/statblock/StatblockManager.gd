extends RefCounted
class_name StatblockManager

# ---------------------------------------------------------------------------
# StatblockManager — typed coordinator for the statblock domain.
#
# Owned by ServiceRegistry.statblock.  All callers access statblock operations
# through manager methods — never via `registry.statblock.service` directly.
# ---------------------------------------------------------------------------

var service: IStatblockService = null


func add_statblock(data: StatblockData, scope: String) -> void:
	if service == null:
		return
	service.add_statblock(data, scope)


func update_statblock(data: StatblockData) -> void:
	if service == null:
		return
	service.update_statblock(data)


func remove_statblock(id: String) -> void:
	if service == null:
		return
	service.remove_statblock(id)


func get_statblock(id: String) -> StatblockData:
	if service == null:
		return null
	return service.get_statblock(id)


func search_all(query: String, category: String, filters: Dictionary) -> Array:
	if service == null:
		return []
	return service.search_all(query, category, filters)


func get_all_by_scope(scope: String) -> Array:
	if service == null:
		return []
	return service.get_all_by_scope(scope)


func duplicate_from_srd(srd_index: String, ruleset: String) -> StatblockData:
	if service == null:
		return null
	return service.duplicate_from_srd(srd_index, ruleset)


func create_blank() -> StatblockData:
	if service == null:
		return null
	return service.create_blank()


func roll_statblock_hp(statblock: StatblockData) -> int:
	if service == null:
		return 0
	return service.roll_statblock_hp(statblock)
