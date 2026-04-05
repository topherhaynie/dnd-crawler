# 5e-bits/5e-database Reference

**Repo:** <https://github.com/5e-bits/5e-database> (MIT license, OGL for content)  
**Stars:** 878 | **Contributors:** 89 | **Releases:** 109 (latest: v4.6.3)  
**API:** <https://dnd5eapi.co/>  
**Docs:** <https://5e-bits.github.io/docs/>

## What it is

A community-maintained, well-structured JSON database of all D&D 5th Edition SRD content.
Data is already machine-readable — no parsing or transformation needed.

## Data location

Raw JSON files live under `src/2014/` (2014 SRD rules) and `src/2024/` (2024 SRD rules).

**Base raw URL pattern:**

```
https://raw.githubusercontent.com/5e-bits/5e-database/main/src/2014/{filename}
```

## Available files (2014 SRD)

| File | Content |
| ---- | ------- |
| `5e-SRD-Monsters.json` | All SRD monsters with full stat blocks |
| `5e-SRD-Spells.json` | All SRD spells with full details |
| `5e-SRD-Equipment.json` | Weapons, armor, gear, tools |
| `5e-SRD-Magic-Items.json` | Magic items |
| `5e-SRD-Classes.json` | Class definitions |
| `5e-SRD-Subclasses.json` | Subclass definitions |
| `5e-SRD-Races.json` | Race definitions |
| `5e-SRD-Subraces.json` | Subrace definitions |
| `5e-SRD-Features.json` | Class features by level |
| `5e-SRD-Levels.json` | Level progression tables |
| `5e-SRD-Feats.json` | Feats |
| `5e-SRD-Traits.json` | Racial traits |
| `5e-SRD-Skills.json` | Skills |
| `5e-SRD-Ability-Scores.json` | Ability score definitions |
| `5e-SRD-Proficiencies.json` | Proficiencies |
| `5e-SRD-Conditions.json` | Conditions |
| `5e-SRD-Damage-Types.json` | Damage types |
| `5e-SRD-Magic-Schools.json` | Schools of magic |
| `5e-SRD-Equipment-Categories.json` | Equipment categories |
| `5e-SRD-Languages.json` | Languages |
| `5e-SRD-Alignments.json` | Alignments |
| `5e-SRD-Backgrounds.json` | Backgrounds |
| `5e-SRD-Weapon-Properties.json` | Weapon properties |
| `5e-SRD-Rules.json` | Rule sections |
| `5e-SRD-Rule-Sections.json` | Rule section content |

## Data structure

Each file is a top-level JSON array of objects. Every entity has:

- `index` — slug ID (e.g. `"acid-splash"`, `"goblin"`) used for cross-referencing
- `name` — display name
- `url` — API path (e.g. `"/api/2014/spells/acid-splash"`)

**Cross-references** use `{ "index": "...", "name": "...", "url": "..." }` objects throughout,
so relationships are fully traversable.

### Spell fields

`index`, `name`, `desc[]`, `higher_level[]`, `range`, `components[]`, `material`,
`ritual`, `duration`, `concentration`, `casting_time`, `level`, `school`, `classes[]`,
`subclasses[]`, `damage` (with `damage_type` and `damage_at_slot_level` or
`damage_at_character_level`), `dc`, `area_of_effect`, `heal_at_slot_level`, `attack_type`

### Monster fields

`index`, `name`, `size`, `type`, `subtype`, `alignment`, `armor_class[]`, `hit_points`,
`hit_dice`, `hit_points_roll`, `speed`, `strength`, `dexterity`, `constitution`,
`intelligence`, `wisdom`, `charisma`, `proficiencies[]`, `damage_vulnerabilities[]`,
`damage_resistances[]`, `damage_immunities[]`, `condition_immunities[]`, `senses`,
`languages`, `challenge_rating`, `xp`, `special_abilities[]`, `actions[]`,
`legendary_actions[]`, `reactions[]`, `image`, `url`

## Schemas

ZOD validation schemas are available under `src/2014/schemas/` and `src/2014/tests/`.

## How to consume

1. **Direct raw file download** — fetch JSON files via the raw GitHub URLs above
2. **REST API** — query `https://www.dnd5eapi.co/api/2014/monsters`, `/api/2014/spells`, etc.
3. **Clone the repo** — `git clone https://github.com/5e-bits/5e-database.git` and read from `src/2014/`

## License

MIT for the code. D&D content is under the Open Gaming License (OGL 1.0a) — SRD content only.
