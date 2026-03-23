extends RefCounted
class_name HistoryManager

## HistoryManager — typed coordinator for the session history domain.
##
## Owned by ServiceRegistry.history.  All callers push/pop undo commands
## through manager methods — never via registry.history.service directly.
##
## Access via: get_node("/root/ServiceRegistry").history

var service: IHistoryService = null


func push_command(cmd: HistoryCommand) -> void:
	if service == null:
		return
	service.push_command(cmd)


func undo() -> bool:
	if service == null:
		return false
	return service.undo()


func redo() -> bool:
	if service == null:
		return false
	return service.redo()


func can_undo() -> bool:
	if service == null:
		return false
	return service.can_undo()


func can_redo() -> bool:
	if service == null:
		return false
	return service.can_redo()


func get_undo_description() -> String:
	if service == null:
		return ""
	return service.get_undo_description()


func get_redo_description() -> String:
	if service == null:
		return ""
	return service.get_redo_description()


func clear() -> void:
	if service == null:
		return
	service.clear()
