extends Node
class_name IHistoryService

## Protocol: IHistoryService
##
## Base class for the session undo/redo history service.  Extend this class
## and override all methods; stubs push_error so missing overrides surface
## at runtime.
##
## The service is session-only — history is not persisted to disk and should
## be cleared whenever the map changes.

@warning_ignore("unused_signal")
signal history_changed


func push_command(_cmd: HistoryCommand) -> void:
	push_error("IHistoryService.push_command: not implemented")


func undo() -> bool:
	push_error("IHistoryService.undo: not implemented")
	return false


func redo() -> bool:
	push_error("IHistoryService.redo: not implemented")
	return false


func can_undo() -> bool:
	push_error("IHistoryService.can_undo: not implemented")
	return false


func can_redo() -> bool:
	push_error("IHistoryService.can_redo: not implemented")
	return false


func get_undo_description() -> String:
	push_error("IHistoryService.get_undo_description: not implemented")
	return ""


func get_redo_description() -> String:
	push_error("IHistoryService.get_redo_description: not implemented")
	return ""


func clear() -> void:
	push_error("IHistoryService.clear: not implemented")
