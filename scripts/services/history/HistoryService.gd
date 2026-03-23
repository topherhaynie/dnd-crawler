extends IHistoryService
class_name HistoryService

## HistoryService — session undo/redo stack for DM actions.
##
## Commands are stored as HistoryCommand values (undo + redo Callables).
## The stack is capped at MAX_DEPTH entries; oldest commands are evicted when
## the cap is exceeded.  The stack is session-only and should be cleared on
## map load.
##
## Stack semantics:
##   _commands[0 .. _index-1]  — commands available for undo (most recent at _index-1)
##   _commands[_index .. end]  — commands available for redo (next at _index)

const MAX_DEPTH: int = 50

## Array[HistoryCommand]
var _commands: Array = []
var _index: int = 0


func push_command(cmd: HistoryCommand) -> void:
	if cmd == null:
		return
	# Discard any redo future when a new action is taken.
	if _index < _commands.size():
		_commands.resize(_index)
	_commands.append(cmd)
	_index = _commands.size()
	# Evict oldest entry when over cap.
	if _commands.size() > MAX_DEPTH:
		_commands.remove_at(0)
		_index = _commands.size()
	history_changed.emit()


func undo() -> bool:
	if _index <= 0:
		return false
	_index -= 1
	var cmd: HistoryCommand = _commands[_index] as HistoryCommand
	if cmd != null and cmd.undo.is_valid():
		cmd.undo.call()
	history_changed.emit()
	return true


func redo() -> bool:
	if _index >= _commands.size():
		return false
	var cmd: HistoryCommand = _commands[_index] as HistoryCommand
	_index += 1
	if cmd != null and cmd.redo.is_valid():
		cmd.redo.call()
	history_changed.emit()
	return true


func can_undo() -> bool:
	return _index > 0


func can_redo() -> bool:
	return _index < _commands.size()


func get_undo_description() -> String:
	if _index <= 0:
		return ""
	var cmd: HistoryCommand = _commands[_index - 1] as HistoryCommand
	return cmd.description if cmd != null else ""


func get_redo_description() -> String:
	if _index >= _commands.size():
		return ""
	var cmd: HistoryCommand = _commands[_index] as HistoryCommand
	return cmd.description if cmd != null else ""


func clear() -> void:
	_commands.clear()
	_index = 0
	history_changed.emit()
