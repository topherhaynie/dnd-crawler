extends RefCounted
class_name SelectionManager

## Selection domain coordinator.
##
## Exposes selection policy (tool allow-list and SelectionLayer priority enum)
## through ISelectionService.
##
## Access via: get_node("/root/ServiceRegistry").selection

var service: ISelectionService = null


## Returns true when the given tool participates in unified selection logic.
## Returns false if the service is unavailable (fails closed — no selection).
func tool_supports_selection(tool_key: String) -> bool:
	if service == null:
		return false
	return service.tool_supports_selection(tool_key)
