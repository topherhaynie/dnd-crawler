extends RefCounted
class_name HistoryCommand

## HistoryCommand — a single undoable/redoable DM action.
##
## Both `undo` and `redo` are Callables (lambdas or bound methods) that
## capture before/after state in their closures so they can be invoked at
## any later point.  The description is shown in the Edit menu and status bar.

var description: String = ""
var undo: Callable
var redo: Callable


static func create(desc: String, undo_fn: Callable, redo_fn: Callable) -> HistoryCommand:
	var cmd := HistoryCommand.new()
	cmd.description = desc
	cmd.undo = undo_fn
	cmd.redo = redo_fn
	return cmd
