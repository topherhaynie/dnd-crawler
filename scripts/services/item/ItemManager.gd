extends RefCounted
class_name ItemManager

# ---------------------------------------------------------------------------
# ItemManager — typed coordinator for the item domain.
#
# Owned by ServiceRegistry.item.  All callers access item operations through
# manager methods — never via `registry.item.service` directly.
# ---------------------------------------------------------------------------

var service: IItemService = null


func add_item(data: ItemEntry, scope: String) -> void:
	if service == null:
		return
	service.add_item(data, scope)


func update_item(data: ItemEntry) -> void:
	if service == null:
		return
	service.update_item(data)


func remove_item(id: String) -> void:
	if service == null:
		return
	service.remove_item(id)


func get_item(id: String) -> ItemEntry:
	if service == null:
		return null
	return service.get_item(id)


func search_all(query: String, category: String, filters: Dictionary) -> Array:
	if service == null:
		return []
	return service.search_all(query, category, filters)


func get_all_by_scope(scope: String) -> Array:
	if service == null:
		return []
	return service.get_all_by_scope(scope)


func duplicate_from_srd(srd_index: String, ruleset: String) -> ItemEntry:
	if service == null:
		return null
	return service.duplicate_from_srd(srd_index, ruleset)


func create_blank() -> ItemEntry:
	if service == null:
		return null
	return service.create_blank()


func get_categories() -> PackedStringArray:
	if service == null:
		return PackedStringArray()
	return service.get_categories()
