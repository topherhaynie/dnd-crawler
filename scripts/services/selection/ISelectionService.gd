extends Node
class_name ISelectionService

## Protocol: ISelectionService
##
## Owns the canonical SelectionLayer priority ordering and the tool allow-list
## that determines whether the unified selection picker runs for a given tool.
##
## Priority is expressed as integer value: higher number = higher priority.
## The unified picker in MapView tests layers from highest to lowest and
## returns the first hit found.

enum SelectionLayer {
	WALL = 0,
	INDICATOR = 1,
	SPAWN = 2,
	TOKEN = 3,
	EFFECT = 4,
	MEASUREMENT = 5,
	PLAYER_TOKEN = 6,
}


## Returns true when the given tool_key participates in unified selection logic
## (the picker runs, drag-to-select is enabled, priority ordering applies).
## Non-selection tools handle their own click logic entirely and never trigger
## the selection path.
func tool_supports_selection(_tool_key: String) -> bool:
	push_error("ISelectionService.tool_supports_selection: not implemented")
	return false
