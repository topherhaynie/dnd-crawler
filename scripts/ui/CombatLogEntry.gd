extends HBoxContainer
class_name CombatLogEntry

## A single row in the Combat Log panel.
##
## Layout: [round badge]  [type tag]  [rich text description]

var _round_badge: Label = null
var _type_tag: Label = null
var _desc_label: RichTextLabel = null


## Populate this row from a log entry Dictionary and a UI scale factor.
func setup(entry: Dictionary, s: float) -> void:
	add_theme_constant_override("separation", roundi(4.0 * s))

	var rnd: int = int(entry.get("round", 0))
	_round_badge = Label.new()
	_round_badge.text = "R%d" % rnd if rnd > 0 else "--"
	_round_badge.custom_minimum_size = Vector2(roundi(26.0 * s), 0)
	_round_badge.add_theme_font_size_override("font_size", roundi(10.0 * s))
	_round_badge.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_round_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_round_badge.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_round_badge)

	var type_str: String = str(entry.get("type", ""))
	_type_tag = Label.new()
	_type_tag.text = _tag_for(type_str)
	_type_tag.custom_minimum_size = Vector2(roundi(44.0 * s), 0)
	_type_tag.add_theme_font_size_override("font_size", roundi(10.0 * s))
	_type_tag.add_theme_color_override("font_color", _color_for(type_str))
	_type_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_tag.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(_type_tag)

	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc_label.scroll_active = false
	_desc_label.fit_content = true
	_desc_label.add_theme_font_size_override("normal_font_size", roundi(12.0 * s))
	_desc_label.add_theme_font_size_override("bold_font_size", roundi(12.0 * s))
	_desc_label.add_theme_font_size_override("italics_font_size", roundi(12.0 * s))
	_desc_label.text = _format(entry)
	add_child(_desc_label)


## Return the short type tag shown in the second column.
func _tag_for(type_str: String) -> String:
	match type_str:
		"combat_start": return "[START]"
		"combat_end": return "[END]"
		"initiative_rolled": return "[INIT]"
		"turn_start": return "[TURN]"
		"attack_roll": return "[ATK]"
		"damage_dealt": return "[DMG]"
		"healing_applied": return "[HEAL]"
		"saving_throw": return "[SAVE]"
		"death_save": return "[DEATH]"
		"condition_applied": return "[COND+]"
		"condition_removed": return "[COND-]"
		"token_killed": return "[KILL]"
		"token_stabilized": return "[STBL]"
		"custom": return "[NOTE]"
		_: return "[?]"


## Return the highlight colour for the type tag.
func _color_for(type_str: String) -> Color:
	match type_str:
		"damage_dealt": return Color(1.0, 0.4, 0.3)
		"healing_applied": return Color(0.3, 0.9, 0.4)
		"saving_throw": return Color(0.4, 0.6, 1.0)
		"death_save": return Color(0.9, 0.5, 0.2)
		"attack_roll": return Color(0.9, 0.75, 0.3)
		"condition_applied": return Color(0.9, 0.6, 0.2)
		"condition_removed": return Color(0.6, 0.6, 0.6)
		"token_killed": return Color(1.0, 0.3, 0.3)
		"token_stabilized": return Color(1.0, 0.85, 0.2)
		"combat_start", "combat_end": return Color(0.5, 0.8, 1.0)
		"custom": return Color(0.8, 0.8, 0.8)
		_: return Color(0.6, 0.6, 0.6)


## Format the entry as BBCode-rich text for the description column.
func _format(entry: Dictionary) -> String:
	var type_str: String = str(entry.get("type", ""))
	match type_str:
		"combat_start":
			return "[b]Combat started[/b]"
		"combat_end":
			return "[b]Combat ended[/b]"
		"initiative_rolled":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			var total: int = int(entry.get("total", 0))
			var roll: int = int(entry.get("roll", 0))
			var mod: int = int(entry.get("modifier", 0))
			if mod > 0:
				return "[b]%s[/b] rolled initiative: %d + %d = [b]%d[/b]" % [nm, roll, mod, total]
			if mod < 0:
				return "[b]%s[/b] rolled initiative: %d - %d = [b]%d[/b]" % [nm, roll, -mod, total]
			return "[b]%s[/b] rolled initiative: [b]%d[/b]" % [nm, total]
		"turn_start":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			var rnd: int = int(entry.get("round", 0))
			return "[b]%s[/b]'s turn  (Round %d)" % [nm, rnd]
		"attack_roll":
			var atk: String = str(entry.get("attacker_name", entry.get("attacker_id", "?")))
			var tgt: String = str(entry.get("target_name", entry.get("target_id", "?")))
			var roll: int = int(entry.get("roll", 0))
			var bonus: int = int(entry.get("bonus", 0))
			var total: int = int(entry.get("total", 0))
			var hit: bool = bool(entry.get("hit", false))
			var crit: bool = bool(entry.get("critical", false))
			var result: String
			if crit:
				result = "[color=#ffd700][b]CRITICAL HIT[/b][/color]"
			elif hit:
				result = "[color=#44ee66][b]HIT[/b][/color]"
			else:
				result = "[color=#ff4444][b]MISS[/b][/color]"
			var bonus_str: String = ("+%d" % bonus) if bonus >= 0 else str(bonus)
			return "[b]%s[/b] attacks [b]%s[/b]: %d %s = [b]%d[/b] — %s" % [atk, tgt, roll, bonus_str, total, result]
		"damage_dealt":
			var src: String = str(entry.get("source_name", entry.get("source_id", "")))
			var tgt: String = str(entry.get("target_name", entry.get("target_id", "?")))
			var actual: int = int(entry.get("actual", entry.get("amount", 0)))
			var dmg_type: String = str(entry.get("type_detail", ""))
			var detail: String = str(entry.get("detail", ""))
			var text: String
			if not src.is_empty():
				text = "[b]%s[/b] → [b]%s[/b]: [color=#ff5555][b]%d[/b][/color] damage" % [src, tgt, actual]
			else:
				text = "[b]%s[/b] takes [color=#ff5555][b]%d[/b][/color] damage" % [tgt, actual]
			if not dmg_type.is_empty():
				text += " (%s)" % dmg_type
			if not detail.is_empty():
				text += "  [color=#777777][i]%s[/i][/color]" % detail
			return text
		"healing_applied":
			var src: String = str(entry.get("source_name", entry.get("source_id", "")))
			var tgt: String = str(entry.get("target_name", entry.get("target_id", "?")))
			var amount: int = int(entry.get("amount", 0))
			if not src.is_empty():
				return "[b]%s[/b] heals [b]%s[/b] for [color=#44ee88][b]%d[/b][/color] HP" % [src, tgt, amount]
			return "[b]%s[/b] heals [color=#44ee88][b]%d[/b][/color] HP" % [tgt, amount]
		"saving_throw":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			var ability: String = str(entry.get("ability", "?")).to_upper()
			var dc: int = int(entry.get("dc", 0))
			var total: int = int(entry.get("total", 0))
			var roll: int = int(entry.get("roll", 0))
			var mod: int = int(entry.get("modifier", 0))
			var passed: bool = bool(entry.get("passed", false))
			var auto_fail: bool = bool(entry.get("auto_fail", false))
			var result: String = "[color=#44aaff][b]PASS[/b][/color]" if passed else "[color=#ff4444][b]FAIL[/b][/color]"
			if auto_fail:
				return "[b]%s[/b] %s save DC %d: [i]auto-fail[/i] — %s" % [nm, ability, dc, result]
			if mod != 0:
				var mod_str: String = ("+%d" % mod) if mod >= 0 else str(mod)
				return "[b]%s[/b] %s save DC %d: %d %s = [b]%d[/b] — %s" % [nm, ability, dc, roll, mod_str, total, result]
			return "[b]%s[/b] %s save DC %d: [b]%d[/b] — %s" % [nm, ability, dc, total, result]
		"death_save":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			var roll: int = int(entry.get("roll", 0))
			var stabilized: bool = bool(entry.get("stabilized", false))
			var dead: bool = bool(entry.get("dead", false))
			var success: bool = bool(entry.get("success", false))
			if stabilized:
				return "[b]%s[/b] death save: [b]%d[/b] — [color=#ffd700][b]STABILIZED[/b][/color]" % [nm, roll]
			if dead:
				return "[b]%s[/b] death save: [b]%d[/b] — [color=#ff3333][b]DEAD[/b][/color]" % [nm, roll]
			var res: String = "[color=#44aaff]success[/color]" if success else "[color=#ff4444]failure[/color]"
			return "[b]%s[/b] death save: [b]%d[/b] — %s" % [nm, roll, res]
		"condition_applied":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			var cond: String = str(entry.get("condition_name", "?")).capitalize()
			var source: String = str(entry.get("source", ""))
			var text: String = "[b]%s[/b] gains [color=#ffaa33][b]%s[/b][/color]" % [nm, cond]
			if not source.is_empty():
				text += " (from %s)" % source
			return text
		"condition_removed":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			var cond: String = str(entry.get("condition_name", "?")).capitalize()
			return "[b]%s[/b] — [color=#888888][b]%s[/b][/color] removed" % [nm, cond]
		"token_killed":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			return "[color=#ff3333][b]%s is slain![/b][/color]" % nm
		"token_stabilized":
			var nm: String = str(entry.get("token_name", entry.get("token_id", "?")))
			return "[color=#ffd700][b]%s is stabilized.[/b][/color]" % nm
		"custom":
			var note: String = str(entry.get("text", ""))
			return "[color=#cccccc][i]%s[/i][/color]" % note
		_:
			return str(entry)
