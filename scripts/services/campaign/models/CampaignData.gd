extends RefCounted
class_name CampaignData

# ---------------------------------------------------------------------------
# CampaignData — organisational reference container for a campaign.
#
# Characters are stored globally in the CharacterService; this model holds
# only their IDs.  Maps and saves are .bundle paths on disk.
# ---------------------------------------------------------------------------

var id: String = ""
var name: String = ""
var description: String = ""
var created_at: String = ""
var updated_at: String = ""

## "2014" / "2024" — campaign default ruleset.
var default_ruleset: String = "2014"

## statblock_id → StatblockData.to_dict()  (NPC/monster bestiary, embedded)
var bestiary: Dictionary = {}
## IDs of StatblockData characters stored in the global character roster.
var character_ids: Array = []
## Campaign-scoped presentation overrides for global characters.
## character_id → CharacterOverride.to_dict()
var character_overrides: Dictionary = {}
## Legacy field: kept during load for one-time migration into CharacterService.
## NEVER written back to disk; omitted from to_dict().
var _legacy_characters: Dictionary = {}

## spell_index → SpellData.to_dict()
var spell_library: Dictionary = {}
## item_index → ItemEntry.to_dict()
var item_library: Dictionary = {}

## Paths to .map bundles associated with this campaign
var map_paths: Array = []
## Paths to .sav bundles associated with this campaign
var save_paths: Array = []
## Notes: each entry is {id, title, body, folder, created_at, updated_at}
var notes: Array = []
## Persisted note folder names (allows empty folders to survive refresh).
var note_folders: Array = []
## Images: each entry is {id, name, path, folder, copied}
## path is absolute if external, or absolute path inside .campaign/assets/ if copied.
var images: Array = []
## Persisted image folder names (allows empty folders to survive refresh).
var image_folders: Array = []
## Active player profile IDs
var active_profile_ids: Array = []

## House rules and campaign settings
var settings: Dictionary = {
	"tie_goes_to": "player",
	"critical_hit_rule": "double_dice",
	"dice_visibility": "shared",
	"advancement_mode": "milestone", ## "milestone" or "xp"
}


func generate_id() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	id = "campaign_%d_%d" % [Time.get_unix_time_from_system(), rng.randi()]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"created_at": created_at,
		"updated_at": updated_at,
		"default_ruleset": default_ruleset,
		"bestiary": bestiary,
		"character_ids": character_ids,
		"character_overrides": character_overrides,
		"spell_library": spell_library,
		"item_library": item_library,
		"map_paths": map_paths,
		"save_paths": save_paths,
		"notes": notes,
		"note_folders": note_folders,
		"images": images,
		"image_folders": image_folders,
		"active_profile_ids": active_profile_ids,
		"settings": settings,
	}


static func from_dict(d: Dictionary) -> CampaignData:
	var c := CampaignData.new()
	c.id = str(d.get("id", ""))
	c.name = str(d.get("name", ""))
	c.description = str(d.get("description", ""))
	c.created_at = str(d.get("created_at", ""))
	c.updated_at = str(d.get("updated_at", ""))
	c.default_ruleset = str(d.get("default_ruleset", "2014"))

	var raw_bestiary: Variant = d.get("bestiary", {})
	if raw_bestiary is Dictionary:
		c.bestiary = raw_bestiary as Dictionary

	## New format: character_ids array
	var raw_ids: Variant = d.get("character_ids", [])
	if raw_ids is Array:
		c.character_ids = raw_ids as Array

	## Campaign-scoped character overrides
	var raw_co: Variant = d.get("character_overrides", {})
	if raw_co is Dictionary:
		c.character_overrides = raw_co as Dictionary

	## Legacy format: full embedded character dicts — stash for migration
	var raw_chars: Variant = d.get("characters", {})
	if raw_chars is Dictionary and not (raw_chars as Dictionary).is_empty():
		c._legacy_characters = raw_chars as Dictionary

	var raw_spells: Variant = d.get("spell_library", {})
	if raw_spells is Dictionary:
		c.spell_library = raw_spells as Dictionary

	var raw_items: Variant = d.get("item_library", {})
	if raw_items is Dictionary:
		c.item_library = raw_items as Dictionary

	var raw_maps: Variant = d.get("map_paths", [])
	if raw_maps is Array:
		c.map_paths = raw_maps as Array

	var raw_saves: Variant = d.get("save_paths", [])
	if raw_saves is Array:
		c.save_paths = raw_saves as Array

	var raw_notes: Variant = d.get("notes", [])
	if raw_notes is Array:
		c.notes = raw_notes as Array

	var raw_nf: Variant = d.get("note_folders", [])
	if raw_nf is Array:
		c.note_folders = raw_nf as Array

	var raw_images: Variant = d.get("images", [])
	if raw_images is Array:
		c.images = raw_images as Array

	var raw_if: Variant = d.get("image_folders", [])
	if raw_if is Array:
		c.image_folders = raw_if as Array

	var raw_profiles: Variant = d.get("active_profile_ids", [])
	if raw_profiles is Array:
		c.active_profile_ids = raw_profiles as Array

	var raw_settings: Variant = d.get("settings", {})
	if raw_settings is Dictionary:
		var merged: Dictionary = {
			"tie_goes_to": "player",
			"critical_hit_rule": "double_dice",
			"dice_visibility": "shared",
			"advancement_mode": "milestone",
		}
		merged.merge(raw_settings as Dictionary, true)
		c.settings = merged

	return c
