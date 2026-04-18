extends RefCounted
class_name CharacterOverride

# ---------------------------------------------------------------------------
# CharacterOverride — campaign-scoped presentation overlay for a global
# character (StatblockData stored in CharacterService).
#
# Follows the same layered-override pattern as StatblockOverride but scoped
# to campaign-level presentation rather than per-token combat state.
#
# Resolution order:  campaign override → global character → defaults.
# ---------------------------------------------------------------------------

## ID of the global character this overrides.
var character_id: String = ""

## Campaign-specific portrait path (absolute, or relative to .campaign/assets/).
## Empty = use the global character's portrait_path instead.
var portrait_path: String = ""

## Optional back-reference to a campaign image ID this portrait was sourced
## from.  Metadata only — rendering always uses portrait_path, never resolves
## through the campaign image library at draw time.
var campaign_image_id: String = ""

## Campaign-specific display name override.  Empty = use global name.
var display_name: String = ""

## Free-form campaign-specific notes (e.g. "Currently cursed", "Has the key").
var notes: String = ""


func to_dict() -> Dictionary:
	return {
		"character_id": character_id,
		"portrait_path": portrait_path,
		"campaign_image_id": campaign_image_id,
		"display_name": display_name,
		"notes": notes,
	}


static func from_dict(d: Dictionary) -> CharacterOverride:
	var co := CharacterOverride.new()
	co.character_id = str(d.get("character_id", ""))
	co.portrait_path = str(d.get("portrait_path", ""))
	co.campaign_image_id = str(d.get("campaign_image_id", ""))
	co.display_name = str(d.get("display_name", ""))
	co.notes = str(d.get("notes", ""))
	return co
