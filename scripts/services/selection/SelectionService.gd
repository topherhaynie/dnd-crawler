extends ISelectionService
class_name SelectionService

## SelectionService — implements the tool allow-list.
##
## Returns true only for tools that participate in unified selection logic:
## the picker runs, drag-to-select is enabled, and SelectionLayer priority
## ordering applies.  Any tool not in this list handles its own click logic
## internally and never reaches the selection path.


func tool_supports_selection(tool_key: String) -> bool:
	match tool_key:
		"select", "place_token", "place_effect", "spawn_point":
			return true
	return false
