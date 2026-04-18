extends Node
class_name IStatblockService

# ---------------------------------------------------------------------------
# IStatblockService — protocol for unified statblock management.
#
# Merges SRD, campaign, map-local, and global custom statblocks into a
# single searchable namespace.
# ---------------------------------------------------------------------------

@warning_ignore("unused_signal")
signal statblock_added(data: StatblockData)
@warning_ignore("unused_signal")
signal statblock_updated(data: StatblockData)
@warning_ignore("unused_signal")
signal statblock_removed(id: String)


## scope: "map" / "campaign" / "global"
func add_statblock(_data: StatblockData, _scope: String) -> void:
	push_error("IStatblockService.add_statblock: not implemented")


func update_statblock(_data: StatblockData) -> void:
	push_error("IStatblockService.update_statblock: not implemented")


func remove_statblock(_id: String) -> void:
	push_error("IStatblockService.remove_statblock: not implemented")


func get_statblock(_id: String) -> StatblockData:
	push_error("IStatblockService.get_statblock: not implemented")
	return null


## Unified search across SRD + campaign + map-local + global.
## category: "" (all) / "monsters" / "spells" / "equipment"
## filters: optional {"ruleset": "2014", "source": "srd", ...}
func search_all(_query: String, _category: String, _filters: Dictionary) -> Array:
	push_error("IStatblockService.search_all: not implemented")
	return []


## scope: "map" / "campaign" / "global"
func get_all_by_scope(_scope: String) -> Array:
	push_error("IStatblockService.get_all_by_scope: not implemented")
	return []


## Copy SRD entry into an editable custom statblock.
func duplicate_from_srd(_srd_index: String, _ruleset: String) -> StatblockData:
	push_error("IStatblockService.duplicate_from_srd: not implemented")
	return null


func create_blank() -> StatblockData:
	push_error("IStatblockService.create_blank: not implemented")
	return null


func roll_statblock_hp(_statblock: StatblockData) -> int:
	push_error("IStatblockService.roll_statblock_hp: not implemented")
	return 0
