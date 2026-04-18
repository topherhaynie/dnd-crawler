extends Node
class_name ISelectionService

## Protocol: ISelectionService
##
## Owns the canonical SelectionLayer priority ordering and the tool allow-list
## that determines whether the unified selection picker runs for a given tool.
##
## Also owns the persistent multi-selection state: which entity IDs are
## currently selected, and emits selection_changed when that set changes.
##
## Priority is expressed as integer value: higher number = higher priority.
## The unified picker in MapView tests layers from highest to lowest and
## returns the first hit found.

@warning_ignore("unused_signal")
signal selection_changed(selected_ids: Array)

enum SelectionLayer {
	WALL = 0,
	INDICATOR = 1,
	SPAWN = 2,
	TOKEN = 3,
	EFFECT = 4,
	MEASUREMENT = 5,
	PLAYER_TOKEN = 6,
}


## Returns true when the given tool_key participates in unified selection logic.
func tool_supports_selection(_tool_key: String) -> bool:
	push_error("ISelectionService.tool_supports_selection: not implemented")
	return false


## Replace selection with a single entity.
func select(_id: String, _layer: int) -> void:
	push_error("ISelectionService.select: not implemented")


## Toggle an entity in/out of the current selection (Ctrl+click).
func toggle_select(_id: String, _layer: int) -> void:
	push_error("ISelectionService.toggle_select: not implemented")


## Select all entities whose world position falls inside `rect`.
## `hits` is an Array of {id: String, layer: int} pre-gathered by the caller.
func box_select(_hits: Array) -> void:
	push_error("ISelectionService.box_select: not implemented")


## Replace selection with multiple entities at the given layer.
func select_many(_ids: Array[String], _layer: int) -> void:
	push_error("ISelectionService.select_many: not implemented")


## Clear all selected entities.
func clear_selection() -> void:
	push_error("ISelectionService.clear_selection: not implemented")


## Return the ordered list of currently-selected entity IDs.
func get_selected_ids() -> Array[String]:
	push_error("ISelectionService.get_selected_ids: not implemented")
	return []


## Return true if the given id is currently selected.
func is_selected(_id: String) -> bool:
	push_error("ISelectionService.is_selected: not implemented")
	return false
