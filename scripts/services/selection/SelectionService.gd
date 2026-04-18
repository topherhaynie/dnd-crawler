extends ISelectionService
class_name SelectionService

## SelectionService — tool allow-list + multi-selection state.
##
## Tracks which entity IDs are currently selected and emits
## selection_changed when the set changes.

var _selected_ids: Array[String] = []
var _selected_layers: Dictionary = {} ## id → layer int


func tool_supports_selection(tool_key: String) -> bool:
	match tool_key:
		"select", "place_token", "place_effect", "spawn_point":
			return true
	return false


func select(id: String, layer: int) -> void:
	if _selected_ids.size() == 1 and _selected_ids[0] == id:
		return
	_selected_ids.clear()
	_selected_layers.clear()
	_selected_ids.append(id)
	_selected_layers[id] = layer
	selection_changed.emit(_selected_ids.duplicate())


func toggle_select(id: String, layer: int) -> void:
	var idx: int = _selected_ids.find(id)
	if idx >= 0:
		_selected_ids.remove_at(idx)
		_selected_layers.erase(id)
	else:
		_selected_ids.append(id)
		_selected_layers[id] = layer
	selection_changed.emit(_selected_ids.duplicate())


func box_select(hits: Array) -> void:
	_selected_ids.clear()
	_selected_layers.clear()
	for hit: Dictionary in hits:
		var id: String = str(hit.get("id", ""))
		var layer: int = int(hit.get("layer", 0))
		if not id.is_empty() and not _selected_ids.has(id):
			_selected_ids.append(id)
			_selected_layers[id] = layer
	selection_changed.emit(_selected_ids.duplicate())


func select_many(ids: Array[String], layer: int) -> void:
	_selected_ids.clear()
	_selected_layers.clear()
	for id: String in ids:
		if not id.is_empty() and not _selected_ids.has(id):
			_selected_ids.append(id)
			_selected_layers[id] = layer
	selection_changed.emit(_selected_ids.duplicate())


func clear_selection() -> void:
	if _selected_ids.is_empty():
		return
	_selected_ids.clear()
	_selected_layers.clear()
	selection_changed.emit(_selected_ids.duplicate())


func get_selected_ids() -> Array[String]:
	return _selected_ids.duplicate()


func is_selected(id: String) -> bool:
	return _selected_ids.has(id)
