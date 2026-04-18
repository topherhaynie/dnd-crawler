extends Node
class_name IItemService

# ---------------------------------------------------------------------------
# IItemService — protocol for unified item/equipment management.
#
# Merges SRD, campaign, and global custom items into a single searchable
# namespace.
# ---------------------------------------------------------------------------

@warning_ignore("unused_signal")
signal item_added(data: ItemEntry)
@warning_ignore("unused_signal")
signal item_updated(data: ItemEntry)
@warning_ignore("unused_signal")
signal item_removed(id: String)


## scope: "campaign" / "global"
func add_item(_data: ItemEntry, _scope: String) -> void:
	push_error("IItemService.add_item: not implemented")


func update_item(_data: ItemEntry) -> void:
	push_error("IItemService.update_item: not implemented")


func remove_item(_id: String) -> void:
	push_error("IItemService.remove_item: not implemented")


func get_item(_id: String) -> ItemEntry:
	push_error("IItemService.get_item: not implemented")
	return null


## Unified search across SRD + campaign + global.
## category: "" (all) / "Weapon" / "Armor" / "Adventuring Gear" / "Tool" / etc.
## filters: optional {"ruleset": "2014", "source": "srd", ...}
func search_all(_query: String, _category: String, _filters: Dictionary) -> Array:
	push_error("IItemService.search_all: not implemented")
	return []


## scope: "campaign" / "global"
func get_all_by_scope(_scope: String) -> Array:
	push_error("IItemService.get_all_by_scope: not implemented")
	return []


## Copy an SRD item into an editable custom item.
func duplicate_from_srd(_srd_index: String, _ruleset: String) -> ItemEntry:
	push_error("IItemService.duplicate_from_srd: not implemented")
	return null


func create_blank() -> ItemEntry:
	push_error("IItemService.create_blank: not implemented")
	return null


## Return the set of distinct equipment categories from SRD data.
func get_categories() -> PackedStringArray:
	push_error("IItemService.get_categories: not implemented")
	return PackedStringArray()
