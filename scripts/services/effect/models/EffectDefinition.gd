extends RefCounted
class_name EffectDefinition

# ---------------------------------------------------------------------------
# EffectDefinition — a single entry in the effects manifest.
#
# Describes a DM-placeable visual effect: its identity, size limits,
# lifetime mode, and which scene file to instantiate.
#
# JSON round-trip: from_dict() (write path not needed — manifest is static).
# ---------------------------------------------------------------------------

enum Mode {
	ONE_SHOT = 0, ## Plays one full cycle then auto-removes.
	PERSISTENT = 1, ## Stays on the map until the DM removes it.
}

var effect_id: String = ""
var display_name: String = ""
var scene_path: String = ""
var default_size: float = 100.0
var min_size: float = 20.0
var max_size: float = 500.0
var mode: int = Mode.ONE_SHOT
var category: String = ""
var icon: String = "✦"


static func from_dict(d: Dictionary) -> EffectDefinition:
	var def := EffectDefinition.new()
	def.effect_id = str(d.get("effect_id", ""))
	def.display_name = str(d.get("display_name", ""))
	def.scene_path = str(d.get("scene_path", ""))
	def.default_size = float(d.get("default_size", 100.0))
	def.min_size = float(d.get("min_size", 20.0))
	def.max_size = float(d.get("max_size", 500.0))
	def.mode = int(d.get("mode", Mode.ONE_SHOT))
	def.category = str(d.get("category", ""))
	def.icon = str(d.get("icon", "✦"))
	return def
