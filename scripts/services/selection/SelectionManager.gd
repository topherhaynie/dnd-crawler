extends RefCounted
class_name SelectionManager

## Selection domain coordinator.
##
## Exposes selection policy and multi-selection state through ISelectionService.
##
## Access via: get_node("/root/ServiceRegistry").selection

var service: ISelectionService = null


func tool_supports_selection(tool_key: String) -> bool:
	if service == null:
		return false
	return service.tool_supports_selection(tool_key)


func select(id: String, layer: int) -> void:
	if service != null:
		service.select(id, layer)


func toggle_select(id: String, layer: int) -> void:
	if service != null:
		service.toggle_select(id, layer)


func box_select(hits: Array) -> void:
	if service != null:
		service.box_select(hits)


func select_many(ids: Array[String], layer: int) -> void:
	if service != null:
		service.select_many(ids, layer)


func clear_selection() -> void:
	if service != null:
		service.clear_selection()


func get_selected_ids() -> Array[String]:
	if service == null:
		return []
	return service.get_selected_ids()


func is_selected(id: String) -> bool:
	if service == null:
		return false
	return service.is_selected(id)
