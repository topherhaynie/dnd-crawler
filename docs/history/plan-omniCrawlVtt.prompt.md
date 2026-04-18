# Plan: Omni-Crawl VTT — Combined Master Plan (v3)

> **Audit date: April 2026**
> This document is the single authoritative plan covering both the VTT
> foundation (Phases 1–12) and the Statblock, Combat & Dice system
> (Phases 13–26).  Each phase carries an explicit status marker:
> **[COMPLETE]**, **[PARTIAL]**, or **[NOT STARTED]**.
>
> Phases 1–24 are complete (Phase 12 partial).
> Phases 25–26 are the remaining work.

---

## Milestone Tracking (Updated)

| Milestone | Phases | Status |
| :--- | :--- | :--- |
| VTT Foundation | 1–11 | ✅ All complete |
| Roaming Encounters | 12 | ⚠️ Partial (data model + path-paint tool; runtime movement missing) |
| SRD + Campaign + Statblocks | 13–15 | ✅ All complete |
| Token Integration + Dice | 16–17 | ✅ All complete |
| Combat System | 18–22 | ✅ All complete |
| **PAUSE 3** | — | Ready — full combat tested |
| Player Characters | 23 | ✅ Complete |
| Mobile Dice Tray | 24 | ✅ Complete |
| Character Advancement | 25 | ❌ Not started |
| SRD Updates + Polish | 26 | ❌ Not started |

---

# Part I — VTT Foundation

# Plan: Omni-Crawl VTT — Multi-Phase Implementation (v2)

## Project Context
- Godot 4.5, GDScript only (project.godot currently has .NET config — needs cleanup)
- 6 players target; expandable via mobile WebSocket (no hard cap on WS slots)
- Dual-window: DM Window + shared Player TV Window (future: per-player windows)
- Dev: macOS, Deployment: Windows
- DM has separate Editor Mode and Play Mode within the DM Window

---

## Phase 1: Foundation — Project Scaffold & Dual-Window Architecture `[COMPLETE]`
**Goal:** Running skeleton with two windows and core autoload singletons.

1. Remove `[dotnet]` section from `project.godot`
2. Establish folder structure: `scenes/`, `scripts/`, `assets/`, `data/`
3. Create three Autoload singletons:
   - `GameState.gd` — player states, lock flags, active map metadata, notification queue
   - `InputManager.gd` — routes device_id / WebSocket player_id → movement vectors
   - `NetworkManager.gd` — owns WebSocketMultiplayerPeer server
4. Dual-window setup in `Main.gd`:
   - Main window = DM Window (`DisplayServer.window_set_mode`)
   - TV window = `DisplayServer.window_create(...)` on secondary display
5. Create placeholder scenes: `DMWindow.tscn`, `PlayerWindow.tscn`
6. **Future expansion note (not in scope):** Architecture should use a `windows: Array` in `GameState` so additional per-player windows can be spawned later without restructuring

**Verification:** Two windows open on launch; singletons accessible; `GameState.windows` array populated

---

## Phase 2: Map System — Import, Grid/Hex & Calibration `[COMPLETE]`
**Goal:** DM can load a map image, pick an overlay type, and calibrate scale.

1. Map import: FileDialog → support PNG, JPG/JPEG, WEBP, BMP, TGA (Godot 4 native formats)
2. Grid type selector: enum `GridType { SQUARE, HEX_FLAT, HEX_POINTY }` stored in map metadata
3. `GridOverlay.gd`: `_draw()` renders either square grid (using `cell_px`) or hex grid (using `hex_size` + `GridType` orientation)
4. Calibration tool: DM drags ruler → pixel distance / "5 ft" prompt = `cell_px` (square) or `hex_size` (hex)
5. Map definition bundle: `data/maps/<name>.map/`
   - `map.json` stores `{ "image_path", "grid_type", "cell_px", "hex_size", "grid_offset", ... }`
   - `image.<ext>` is copied into the bundle so the map is self-contained
   - DM uses native system dialogs to create/open `.map` bundles
6. DM can paint `LightOccluder2D` wall polygons in editor; stored in map JSON

**Verification:** Load PNG, WEBP, and BMP maps; switch between square and hex overlay; calibrate each; set grid offset; grid aligns to tiles; `.map` bundle persists on reload

---

## Phase 3: Extensible Player Profiles & Input Binding `[COMPLETE]`
**Goal:** 6+ persistent player profiles, designed so new attributes never require a schema refactor.

1. `PlayerProfile.gd` as a Godot `Resource` subclass with two layers:
   - **Core typed fields:** `id` (UUID), `player_name`, `base_speed`, `vision_type` (enum: Normal/Darkvision), `darkvision_range`, `perception_mod`, `input_id`, `input_type` (enum: Gamepad/WebSocket)
   - **Extensible extras:** `var extras: Dictionary = {}` — any future attributes (status effects, inventory, etc.) live here; loaded/saved transparently
2. JSON serialization: `to_dict()` / `from_dict()` on `PlayerProfile`; `extras` round-trips automatically — unknown future keys are preserved without code changes
3. `GameState`: `save_profiles()` / `load_profiles()` → `data/profiles.json`; no cap on profile count
4. DM profile editor UI: list, Add/Edit/Delete, input binding dialog (lists gamepads + WS slots)
5. `passive_perception` computed property: `10 + perception_mod`

**Verification:** Create 8 profiles, add a custom key to `extras`, reload — all data persists; adding new extra field requires zero refactoring

---

## Phase 4: Movement & Fog of War `[COMPLETE]`
**Goal:** Player sprites move with vision arcs; fog reveals around them; walls cast shadows.
*Depends on: Phases 2 & 3*

1. `PlayerSprite.tscn`: `CharacterBody2D` + `Sprite2D` (color-coded token) + `PointLight2D` (vision arc via mask texture) + `CollisionShape2D`
2. `PlayerSprite.gd`: consume vector from `InputManager` → `move_and_slide()` at `base_speed` px/sec; Darkvision profiles get larger base `PointLight2D` range
3. Dash toggle: `is_dashing` → speed ×1.5, `PointLight2D.texture_scale` ×0.5 (vision penalty)
4. FoW: black `CanvasLayer` on `PlayerWindow` with `CanvasModulate`; `PointLight2D` punches through
5. `LightOccluder2D` polygons (from map JSON) create real-time wall shadows
6. DM Window: no FoW layer, full map always visible

**Verification:** Sprite moves, fog clears around it, walls block light; Dash shrinks vision; Darkvision token has wider arc

---

## Phase 5: Input Sources — Gamepad & WebSocket Mobile `[COMPLETE]`
**Goal:** Gamepads and phones drive players simultaneously; unlimited WS slots.
*Depends on: Phases 3 & 4*

1. `InputManager.gd`: per-frame `get_vector(player_id) -> Vector2`; checks `GameState.player_locked[id]` → returns `Vector2.ZERO` if locked
2. Gamepad: `Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X/Y)` → normalized, dead-zone applied
3. `NetworkManager.gd`: `WebSocketMultiplayerPeer` on port `9090`; parse `{ "player_id": int, "x": float, "y": float }`; sanitize (clamp x/y to `[-1,1]`, validate player_id exists in profiles)
4. Mobile client: `assets/mobile_client/index.html` — virtual joystick (nipplejs or canvas); connects to `ws://<host-ip>:9090`
5. WS slots: no hard cap in `NetworkManager`; `GameState` holds all active player profiles

**Verification:** 4 gamepads + 2 phones all move independently; malformed WS packets are discarded silently

---

## Phase 6: DM Editor Mode — Map Object Placement `[COMPLETE]`
**Goal:** DM can pre-configure the map with interactive objects before/during a session; editor/play mode toggle.
*Depends on: Phase 2 (map + cell_px)*

1. DM Window mode toggle button: **Editor Mode** ↔ **Play Mode** (stored in `GameState.dm_mode`)
2. `MapObject` base resource with shared fields: `id` (UUID), `object_type` (enum), `position`, `trigger_shape` (Polygon2D area), `label`, `notes`
3. Five DM-placeable object types (each extends `MapObject`):
   - **Trap**: `perception_dc` (int) — auto-reveal if `passive_perception >= perception_dc`; otherwise freezes player on contact
   - **Event Trigger**: No perception check; proximity auto-fires, freezes player, alerts DM (e.g., encounter start, boss entrance)
   - **Observable / Point of Interest**: Requires player-initiated "Investigate" action; has `investigation_dc`; freezes player until DM unfreezes
   - **Secret**: Hidden door/object; combination of perception (to notice it exists) + investigation (to interact); `perception_dc` + `investigation_dc`
   - **Hazard**: Visible area effect (fire, acid, difficult terrain); doesn't freeze but applies ongoing state or movement penalty; has `damage_type`, `effect_label`
4. Editor Mode tools: click to place object, drag to resize trigger shape, right-click to edit properties, delete key to remove
5. Objects stored in the `.map` bundle metadata under `"map_objects": [...]`; DM Window renders object icons/outlines; Player Window renders nothing (objects are hidden from players)

**Verification:** Place all 5 object types; configure trap with perception_dc=15; save map; reload — all objects restored

---

## Phase 7: Auto-Trigger Logic & DM Notification Queue `[COMPLETE]`
**Goal:** Map objects fire automatically; DM is notified without needing to watch the screen constantly.
*Depends on: Phases 4, 5, 6*

1. Per-frame proximity checks in `TriggerSystem.gd` (Autoload): iterates `GameState.map_objects`, tests each `PlayerSprite` position against object `trigger_shape`
2. **Trap logic:**
   - Each frame: if `player.passive_perception >= trap.perception_dc` → reveal trap icon to that player (show on Player Window)
   - On contact: if trap NOT perceived → fire trap (`GameState.lock_player(id)`, push DM notification)
   - Once revealed: player can choose to avoid (no freeze)
3. **Event Trigger logic:**
   - On `body_entered` equivalent in TriggerSystem: `lock_player(id)`, push notification; fires once (mark `triggered = true`)
4. **Observable logic:**
   - Player presses "Investigate" button → TriggerSystem checks if within range of any Observable → `lock_player(id)`, push notification with object details for DM
5. **Secret logic:**
   - Passive perception check runs each frame while nearby; if `passive_perception >= perception_dc` → subtle "something feels off" indicator shown to that player only
   - Player must then press "Investigate" to fully interact; triggers freeze + DM notification
6. **DM Notification Queue** (panel in `DMWindow.tscn`):
   - Ordered list of pending events: icon, type, player name, object label
   - DM clicks item to see details (notes, dc, etc.) and dismiss/resolve
   - Dismissing unfreezes the associated player (unless DM chooses to keep locked)
7. DM manual controls: "Global Freeze" button, per-player lock/unlock toggle

**Verification:** Player walks into trap (perception below DC) → frozen, DM notified; player with high perception → trap revealed, no freeze; player presses Investigate near POI → frozen, DM sees notification; DM dismisses → player unfreezes

---

## Phase 8: DM Play Tools — FoW Brush, AoE Templates & Map Navigation `[COMPLETE]`
**Goal:** Full DM play-mode toolset for running the session.
*Depends on: Phases 2 & 4*

1. **Map scroll/zoom** (Play Mode + Editor Mode):
   - `Camera2D` on DM Window with pan (middle-mouse drag or right-mouse drag) and zoom (`scroll_wheel`)
   - Player Window has its own `Camera2D` that mirrors a "reveal center" (average of all player positions, or DM-set focus)
2. **FoW brush** (Play Mode):
   - "Reveal" and "Hide" brush modes with adjustable radius slider
   - Paints to a persistent `FoWMask` (Image + ImageTexture) via `Image.set_pixel()`
   - `FoWMask` renders as a modulate layer on Player Window
3. **AoE templates** (Play Mode, visible on both windows):
   - `TemplateLayer.gd` Node2D on both DM and Player windows
   - DM places semi-transparent overlays: **Cone** (origin, direction, angle, length), **Circle** (origin + radius in ft → `cell_px`), **Line** (endpoints + width)
   - DM click-drag to place; click existing to select/delete/reposition

**Verification:** DM pans and zooms map; reveals a corridor with brush → Player Window updates; places fireball circle → visible on both windows

---

## Phase 9: Game State Save / Load (Named Slots) `[COMPLETE]`
**Goal:** DM can save and restore the full game state across sessions.
*Depends on: All prior phases*

Saved state includes:
- Reference to active `.map` bundle + session-specific transforms
- All player positions and lock states
- FoW mask (serialized as base64-encoded image data or RLE-compressed pixel array)
- All map object states (which have fired, which have been revealed per player)
- Active AoE templates
- DM and Player camera positions/zoom levels
- Loaded player profiles snapshot

Implementation:
1. `SaveManager.gd` (Autoload): `save_slot(name: String)` / `load_slot(name: String)` / `list_slots() -> Array`
2. Save format: `.sav` bundle per slot → `data/saves/<name>.sav/`
   - Contains session JSON and transient assets/state only
   - References a `.map` bundle rather than duplicating the base map definition
3. DM Save/Load UI panel in `DMWindow.tscn`: list of named slots with timestamps, Save, Load, Delete
4. On save: serialize all above state via `GameState` + `TriggerSystem` + FoW mask
5. On load: restore scene tree state — reinitialize map, reposition sprites, restore FoW mask, restore trigger states

**Verification:** Mid-session save; close app; reopen; load save → all player positions, FoW, triggered objects, and templates restored exactly

---

## Phase 10: Cross-Platform Polish & Integration QA `[COMPLETE]`
**Goal:** Mac dev ↔ Windows parity; full integration test.

1. `OSHelper.gd`: `get_data_dir() -> String` using `OS.get_name()` for platform-correct user data paths
2. Audit all hardcoded paths → replace with `OSHelper.get_data_dir()`
3. Finalise native map/save document behavior per OS:
   - macOS: exported app `Info.plist` declares `.map` as package/document type (and `.sav` when implemented)
   - Windows: exported app registers file associations/icons for `.map`/`.sav`; verify Explorer/open-with behavior
   - Verify native file dialogs treat `.map` and `.sav` consistently as user-facing documents as much as platform APIs allow
4. Integration test: 4-gamepad + 2-phone session on a real map; all auto-triggers, FoW, saves tested
5. Window resolution/DPI: ensure Player TV Window fills secondary screen on both platforms
6. Stretch/post-MVP: status condition overlays on sprites

---

## Phase 11: Visual Effects System — Expandable Library `[COMPLETE]`
**Goal:** DM can select, place, size, and fire visual effects on both windows.
*Depends on: Phase 8*

Design: each effect is a self-contained `.tscn`. Adding a new effect = drop scene into `assets/effects/` + one entry in `data/effects_manifest.json`. Zero engine code changes.

1. `EffectDefinition.gd` resource: `effect_id`, `display_name`, `scene_path`, `default_size`, `min_size`, `max_size`, `mode` (enum: ONE_SHOT / PERSISTENT), `category`
2. `EffectsManager.gd` (Autoload): loads manifest → `spawn_effect(id, pos, size)` instantiates scene on both DM + Player `EffectLayer` CanvasLayers; tracks persistent effects for save/load
3. Effect scene contract (every `.tscn` must expose):
   - `var size: float` (exported) — uniform scale
   - `signal effect_finished` — ONE_SHOT cleanup signal
   - Can contain any mix of `GPUParticles2D`, `CPUParticles2D`, `AnimatedSprite2D`
4. Starter library (5 effects to validate architecture): `fire_burst`, `lightning_strike`, `frost_nova`, `wind_gust`, `poison_cloud`
5. DM Effect Palette (Play Mode): category-grouped buttons; size slider / scroll-wheel before placement
   - ONE_SHOT: plays while held + one cycle, auto-removes
   - PERSISTENT: stays until DM right-click → Remove

**Verification:** Fireball plays on both windows; poison cloud persists until removed; drop a new .tscn + manifest entry → appears in palette instantly

---

## Phase 12: Roaming Encounters Framework `[PARTIAL]`
**Goal:** DM places moving patrol entities that carry their own trigger zones.
*Depends on: Phases 6 & 7*

**What exists:** `TokenData` has `roam_path: PackedVector2Array`, `roam_speed: float`, `roam_loop: bool` fields (serialized). `MapView.gd` has a full roam-path paint tool (`RoamTool.FREEHAND` / `POLYLINE` / `ERASE`) with `roam_path_committed` signal.

**What is missing:** Runtime roaming movement/animation engine — no `RoamingEntitySprite.tscn`, no per-frame path-following logic, no perception-gated Player Window visibility.

1. `RoamingEntity.gd` (extends `MapObject`): adds `sprite_texture`, `move_speed`, `patrol_mode` (WAYPOINTS / RANDOM_WANDER / STATIONARY), `waypoints: Array[Vector2]`, `trigger_radius`, `trigger_type`, `detection_perception_dc`
2. `RoamingEntitySprite.tscn`: `CharacterBody2D` + `Sprite2D` + `Area2D` trigger that moves with it
3. Movement logic: WAYPOINTS cycles array with dwell time; RANDOM_WANDER picks random nearby point; STATIONARY = static sprite
4. TriggerSystem: roaming entities register their `Area2D` at spawn — uses identical notification queue + lock behavior as static objects
5. Player Window visibility per-entity: Hidden / Always Revealed / Perception-Gated (shows if `passive_perception >= detection_perception_dc`)
6. Editor Mode: place entity, click waypoints on map in sequence, configure in properties panel

**Verification:** Monster patrols waypoints; player enters radius → frozen, DM notified; perception-gated monster only visible to high-perception player

---

## Relevant Files (to be created)
- `project.godot` — remove `[dotnet]` section
- `scenes/DMWindow.tscn` + `scripts/DMWindow.gd`
- `scenes/PlayerWindow.tscn` + `scripts/PlayerWindow.gd`
- `scripts/autoloads/GameState.gd`
- `scripts/autoloads/InputManager.gd`
- `scripts/autoloads/NetworkManager.gd`
- `scripts/autoloads/TriggerSystem.gd`
- `scripts/autoloads/SaveManager.gd`
- `scripts/autoloads/EffectsManager.gd`
- `scenes/MapLayer.tscn` + `scripts/MapLayer.gd`
- `scripts/GridOverlay.gd`
- `scripts/PlayerProfile.gd` (Resource, with extras: Dictionary)
- `scripts/MapObject.gd` + subtypes (Trap, EventTrigger, Observable, Secret, Hazard)
- `scripts/EffectDefinition.gd` (Resource)
- `scripts/RoamingEntity.gd` (extends MapObject)
- `scenes/PlayerSprite.tscn` + `scripts/PlayerSprite.gd`
- `scenes/RoamingEntitySprite.tscn` + `scripts/RoamingEntitySprite.gd`
- `scripts/OSHelper.gd`
- `assets/mobile_client/index.html`
- `assets/effects/` — starter effect .tscn files
- `data/effects_manifest.json` — effect library registry
- `data/` (runtime JSON + saves, gitignored)

---

## Key Decisions
- Language: GDScript (remove .NET config)
- Player cap: 6 default, WS slots uncapped; GameState holds all active profiles
- Dual-window now; future multi-window via `GameState.windows: Array` (not implemented)
- FoW: PointLight2D + CanvasModulate for performance
- PlayerProfile extensibility: typed core fields + `extras: Dictionary` for zero-refactor future attributes
- DM has Editor Mode / Play Mode toggle in DM Window
- 5 map object types: Trap, Event, Observable, Secret, Hazard
- Perception vs Investigation distinct: Traps = passive perception (auto); Observables = active player button; Secrets = both
- Save format: named JSON slots in `data/saves/`
- Runtime caveat: editor/dev runtime can show `.map` bundles as plain directories until exported app document metadata is applied (finalised in Phase 10)
- WebSocket port: 9090
- Effects: manifest-driven expandable library; each effect is a .tscn with `size: float` + `effect_finished` signal; supports GPUParticles2D, CPUParticles2D, AnimatedSprite2D or any mix
- Effects render on both DM + Player windows via EffectLayer CanvasLayer
- Roaming entities reuse TriggerSystem infrastructure; perception-gated visibility

---

# Part II — Statblock, Combat & Dice System

> Phases 13–26 add the full D&D 5e gameplay layer: SRD library, campaign bestiary,
> statblock tokens, 3D physics dice, full combat automation, AoE templates, conditions,
> player character management, and mobile dice tray.

---

## Phase 13: Core Data Models + SRD Bundling `[COMPLETE]`
**Goal:** Shared model classes and bundled SRD data for both 2014 and 2024 rulesets.

**What was built:**
- `StatblockData` — unified creature/character model with all SRD fields. `roll_hit_points() -> int` parses `hit_points_roll` (e.g. "2d8+2").
- `DiceExpression` / `DiceResult` — parse and evaluate any dice expression ("2d6+3", "4d6kh3"). Shared utility used everywhere.
- `ActionEntry`, `SpellData`, `ItemEntry`, `StatblockOverride` — supporting model classes.
- `StatblockOverride` includes runtime combat state: `current_hp`, `temp_hp`, `conditions`, `death_saves`, `concentration_spell`, `spell_slots_used`.
- SRD assets bundled:
  - `assets/srd/2014/`: `5e-SRD-Classes.json`, `5e-SRD-Conditions.json`, `5e-SRD-Equipment.json`, `5e-SRD-Monsters.json`, `5e-SRD-Races.json`, `5e-SRD-Spells.json`
  - `assets/srd/2024/`: `5e-SRD-Conditions.json`, `5e-SRD-Equipment.json`, `5e-SRD-Species.json`
  - `assets/srd/srd_version.json` for update checking
- `SRDLibraryService` (`registry.srd`): lazy-loads and caches monsters, spells, equipment, conditions, classes, races. Both rulesets queryable simultaneously.

**Known gap:** 2024 SRD bundle is incomplete — missing `5e-SRD-Monsters.json`, `5e-SRD-Classes.json`, `5e-SRD-Spells.json` for the 2024 ruleset. Only Conditions, Equipment, and Species are present for 2024.

---

## Phase 14: Campaign System Foundation `[COMPLETE]`
**Goal:** Campaign container owns bestiary, character roster, libraries, map paths, and house rule settings.

**What was built:**
- `CampaignData` — `bestiary: Dictionary`, `characters: Dictionary`, `spell_library: Dictionary`, `item_library: Dictionary`, `map_paths`, `save_paths`, `active_profile_ids`, `settings: Dictionary` (`tie_goes_to`, `critical_hit_rule`), `default_ruleset`.
- `CampaignService` / `CampaignManager` (`registry.campaign`): CRUD, bestiary management, active campaign tracking.
- Campaign data persisted at `user://data/campaigns/<id>/campaign.json`.
- Campaign menu in DMWindow: New / Open / Save / Settings.

---

## Phase 15: Statblock Service + Library Browser UI `[COMPLETE]`
**Goal:** Unified statblock search across SRD, campaign, and map-local scopes. DM-facing browser window.

**What was built:**
- `StatblockService` (`registry.statblock`): merges SRD (read-only) + campaign bestiary (editable) + map-local. `search_all()`, `add_statblock(scope)`, `duplicate_from_srd()`, `create_blank()`, `roll_statblock_hp()`.
- `StatblockLibrary` — non-modal browser window: search box, category/source filter, results list with badges, SRD stat card preview, "Add to Bestiary" / "Attach to Token" / "Roll HP" / "Edit Copy" actions.
- `StatblockCardView` — reusable D&D-style statblock card widget.
- `StatblockOverrideEditor` — modal window for per-instance field overrides with highlighted changes and "Reset to Base".

---

## Phase 16: Token Integration + Per-Token Overrides `[COMPLETE]`
**Goal:** Any token can carry one or more statblocks with per-instance stat overrides and runtime combat state.

**What was built:**
- `TokenData.statblock_refs: Array` — IDs of attached statblocks.
- `TokenData.statblock_overrides: Dictionary` — `{statblock_id: StatblockOverride.to_dict()}` for per-instance overrides and runtime combat state.
- Token editor "Statblocks" section: attach/detach, Roll HP per instance, Auto-Generate, inline HP/temp HP, active conditions.
- Context menu: "View Statblock", "Quick HP", "Manage Statblocks".
- `TokenSprite.set_hp_bar(current_hp, max_hp, temp_hp)` — color-coded bars rendered on map; `_draw_hp_bar()` with green/yellow/red/bloodied theming.
- Network messages: `token_statblock_attached`, `token_statblock_detached`, `token_statblock_override_updated`.

---

## Phase 17: Dice System (3D Physics + Fast Mode) `[COMPLETE]`
**Goal:** Fully animated 3D physics dice with a DM dice tray panel.

**What was built:**
- `DiceService` (`registry.dice`): `roll()`, `roll_animated()`, `roll_fast()`, `roll_with_advantage()`, `roll_with_disadvantage()`, `roll_saving_throw()`, `roll_attack()`, `roll_damage()`, roll history.
- `DiceRenderer3D` (`SubViewportContainer`): `Node3D` scene with `Camera3D`, `DirectionalLight3D`, `StaticBody3D` table (floor + walls). `RigidBody3D` per die with random impulse + torque. Polls for settle via velocity threshold. Reads top face via dot-product of face normals with `Vector3.UP`.
- `DiceMeshFactory` — procedural mesh generation for d4, d6, d8, d10, d12, d20, d100 with UV-mapped face numbers.
- `DiceTray` — DM panel: expression input, quick d4–d20 buttons, modifier spinner, roll history, animated/fast toggle.

---

## Phase 18: Multi-Selection System `[COMPLETE]`
**Goal:** DM can select multiple tokens simultaneously for batch combat operations.

**What was built:**
- `SelectionService` (`registry.selection`): `selected_ids: Array[String]`, `toggle_select()`, `box_select()`, `select_all_in_layer()`.
- `SelectableHit` model for hit-test results.
- Ctrl+click toggles individual tokens; shift+drag box selects all inside rectangle.
- Selected tokens show distinct highlight; selection count displayed in toolbar.
- Quick-filter: "Select All Monsters", "Select All NPCs".

---

## Phase 19: Combat Foundation — Initiative & HP Tracking `[COMPLETE]`
**Goal:** Full combat lifecycle — initiative tracker, HP/damage pipeline, death saves.

**What was built:**
- `CombatService` (`registry.combat`): `start_combat()`, `end_combat()`, `roll_initiative_all()` (uses DEX mod), `set_initiative()`, `next_turn()`, `previous_turn()`, `delay_turn()`, `ready_action()`.
- Damage pipeline: checks immunity → resistance (halve) → vulnerability (double) → subtracts temp HP, then HP. Result logged as "Goblin takes 7 fire damage (halved — fire resistance)".
- Death saves for PCs: 3 successes = stabilize, 3 failures = dead, nat 20 = regain 1 HP, nat 1 = 2 failures.
- Tie-breaking reads `campaign.settings.tie_goes_to`.
- `InitiativePanel` — dockable panel: sorted combatant list with initiative spinner, token icon + name, HP bar (color-coded), condition icons. Current turn highlighted gold. Drag-to-reorder. Right-click context menu.
- `InitiativeEntry` — individual row widget.
- `QuickDamageDialog` — amount + damage type → auto-applies resistances → logs entry.

---

## Phase 20: Saving Throws + AoE Templates `[COMPLETE]`
**Goal:** Batch saving throws with AoE auto-token selection.

**What was built:**
- `AoEData` model: `shape` (CONE/SPHERE/CUBE/LINE/CYLINDER), `origin`, `size_ft`, `spell_name`, `save_ability`, `save_dc`, `damage_expression`, `damage_type`, `effect_type`, `duration_rounds`.
- `SaveResultsPanel` — modal: batch save results table (Token | Roll | Mod | Total | Pass/Fail), per-row DM override, "Apply half/full damage" shortcut.
- `CombatService.get_save_modifier(token_id, ability)` — reads statblock override for the token.
- AoE auto-selects tokens inside shape → highlights → prompts "Call for Save?".

---

## Phase 21: Condition System `[COMPLETE]`
**Goal:** Full D&D 5e conditions with mechanical effects and duration tracking.

**What was built:**
- `ConditionRules` — all 14 5e conditions (Blinded, Charmed, Deafened, Frightened, Grappled, Incapacitated, Invisible, Paralyzed, Petrified, Poisoned, Prone, Restrained, Stunned, Unconscious) plus Exhaustion. Each entry defines: attack adv/disadv, save auto-fails, save adv/disadv, speed multiplier, incapacitated flag.
- `ConditionDialog` — apply/remove dialog with dropdown, source field, duration spinner.
- `CombatService.apply_condition()`, `remove_condition()`, `get_conditions()`, `check_condition_modifiers()` — auto-applied to rolls ("Gnoll is Restrained → DEX save at disadvantage").
- Duration tracking: decremented at start of turn, auto-removed at expiry.
- Concentration tracking: auto-prompt CON save when concentrating caster takes damage.
- Visual condition icons on `TokenSprite` above HP bar.

---

## Phase 22: Combat Log `[COMPLETE]`
**Goal:** Persistent scrollable record of all combat events.

**What was built:**
- `CombatLogPanel` — scrollable log panel: all combat events (initiative rolls, turn changes, attacks, damage with resistance notes, healing, saves, conditions applied/removed, death saves, spell casts, custom DM notes). Rich text with damage in red, healing in green, saves in blue, crits in gold. Filterable (All/Attacks/Damage/Saves/Conditions), searchable. "Add Note" for free-text. "Export" saves full log as text file.
- `CombatLogEntry` — individual row widget.
- `ICombatService.log_entry_added` signal, `get_combat_log()`, `add_log_entry()`, `clear_combat_log()`.

**PAUSE 3 — test point**: Full combat encounter with saving throws via AoE, conditions with mechanical effects, combat log recording everything, 3D dice, initiative, HP tracking, death saves.

---

## Phase 23: Player Character Support `[COMPLETE]`
**Goal:** Full PC creation, management, and profile linking.
*Depends on: Phases 13–15*

**What was built:**
1. **Character creation wizard** (`CharacterWizard.gd`, 3,400 lines): 8-step modal — Name & Race → Class & Level → Class Features → Ability Scores (manual/standard array/point buy) → Background → Proficiencies → Review → Finalize & Override. All 12 SRD classes, 6 races with subraces, 13 backgrounds, 40 feats, fighting styles, invocations, expertise, spell selection. Emits `character_created(statblock, profile_id)`. DM can skip wizard via override step.
2. **Character service** (`CharacterService.gd` / `CharacterManager.gd`): global character roster persisted to `user://data/characters.json`. CRUD, campaign integration.
3. **PlayerProfile ↔ statblock link**: `PlayerProfile.statblock_id` field. `get_passive_perception()`, `get_speed()`, `get_vision_type()`, `get_darkvision_range()` all resolve from the linked character's `StatblockData` when set, with fallback to manual profile fields. Backward compatible.
4. **Character sheet** (`CharacterSheet.gd`): non-modal Window with header (name/race/class/level/background), ability scores + modifiers, saving throws, combat stats (AC/HP/speed/initiative/prof bonus/passive perception), all 18 skills with auto-calculated modifiers, tabbed Features/Spells/Inventory/Notes. Editable with dirty tracking and save.

**Note:** PC creation data (class tables, race traits, spell lists, backgrounds, feats) is hardcoded in the wizard rather than parsed from SRD JSON files. This is pragmatic for a DM-driven VTT — the DM always has override capability in the finalize step.

**Verification:** ✅ Create a fighter via wizard; attach to player profile; statblock auto-fills passive perception and speed; character sheet editable.

---

## Phase 24: Player Dice Tray (Mobile Client) `[COMPLETE]`
**Goal:** Players roll dice from their mobile device; results visible to DM.
*Depends on: Phase 17 (DiceService), Phase 23 (PlayerProfile linked statblock for modifiers)*

**Delivered:**
1. Mobile client (`index.html`) has tabbed UI: **Controls** (joystick, action buttons) and **Dice** (d4–d20 grid, expression input, modifier ±, Roll / Adv / Dis buttons, result display, roll history).
2. Network protocol: mobile sends `{"type": "dice_roll_request", "player_id", "expression", "advantage", "disadvantage"}` → `NetworkService._handle_dice_roll_request` evaluates via `DiceService.roll_fast / roll_with_advantage / roll_with_disadvantage` → sends `{"type": "dice_roll_result", ...}` back to requesting peer.
3. Per-campaign `dice_visibility` setting (`"shared"` / `"roller_only"` / `"dm_only"`) in `CampaignData.settings`. When `"shared"`, result is also broadcast to player displays as `"dice_roll_toast"`.
4. `INetworkService.dice_roll_received` signal → `DMWindow._on_dice_roll_received` → `DiceTray.append_remote_roll(player_name, result)` — mobile rolls appear in DM dice tray history with player name prefix.
5. `PlayerWindow` handles `"dice_roll_toast"` message → animated overlay toast (4s auto-hide) showing player name, expression, total (color-coded for crits/fumbles), and individual rolls.

**Verification:** Player opens mobile client → dice tab → rolls 1d20+5 (adv) → result appears in DM dice tray and optionally on player display.

---

## Phase 25: Character Advancement `[NOT STARTED]`
**Goal:** Optional level-up and XP tracking.
*Depends on: Phase 23*

**What needs to be built:**
1. "Level Up" button on character sheet → wizard: auto-apply class features for next level, HP increase (roll or take average), spell slot increases, new spell selection, ASI at appropriate levels.
2. Optional XP tracking from defeated monsters (CR → XP table lookup from SRD). Milestone leveling alternative (DM grants a level manually).
3. Multiclass support: choose which class to level in (if character has multiple classes).

**Verification:** Fighter levels 1→2; gets Action Surge; HP rolls; ASI at level 4.

---

## Phase 26: SRD Updates + Import/Export + Polish `[NOT STARTED]`
**Goal:** SRD update checker, full statblock editor, import/export, and player-facing visibility controls.

**Partial foundation:** `SRDLibraryService` already has `IMAGE_CACHE_DIR`, `API_IMAGE_BASE`, and `prefetch_all_monster_images()` stub wired into the protocol.

**What needs to be built:**
1. **SRD Update Checker:** compare bundled `srd_version.json` against a hosted version file; download updated JSON files to `user://data/srd_cache/` without requiring an app update.
2. **Full statblock editor/builder:** rich form for from-scratch creature creation, action builder, spell picker, inline dice expression preview.
3. **Import/Export:** statblocks as `.json`, campaigns as `.campaign.json`, cross-campaign copy-paste in library browser.
4. **Player-facing statblock sharing:** DM controls visibility level per token (full / partial / name-only) — shown on player display.
5. **Combat QoL:** opportunity attack prompts when enemy moves away, action macros (Attack / Cast / Dash / Dodge / Disengage / Help / Hide), optional turn timer.

**Verification:** Export a custom monster; import into a different campaign; statblock visible on player display at "name-only" level; OA prompt fires correctly.

---

## Architecture Summary (Current)

**Services registered in `ServiceRegistry`:**
`fog`, `map`, `network`, `game_state`, `profile`, `persistence`, `input`, `token`, `history`, `measurement`, `effect`, `selection`, `ui_scale`, `ui_theme`, `movement`, `srd`, `campaign`, `statblock`, `dice`, `combat`

**Renderer nodes (not services):**
`FogSystem`, `MapView`, `GridOverlay`, `IndicatorOverlay`, `MeasurementOverlay`, `DiceRenderer3D`, `TokenSprite`, `EffectNode`, `ShaderEffectScene`

**Key architectural decisions:**
- GDScript only; no .NET/C#
- SOA registry — typed manager properties only; no `get_service(String)` in new code
- Player cap: 6 default, WS slots uncapped
- Dual-window now; future multi-window via `GameState.windows: Array`
- FoW: `FogSystem.gd` with shader-based reveal and history merge
- `PlayerProfile` extensibility: typed core fields + `extras: Dictionary`
- DM has Editor Mode / Play Mode toggle in DM Window
- 8 token categories: DOOR, TRAP, HIDDEN_OBJECT, SECRET_PASSAGE, MONSTER, EVENT, NPC, GENERIC
- Save format: named `.sav` bundles in `user://data/saves/`; `.map` bundles in `user://data/maps/`
- WebSocket port: 9090
- Effects: manifest-driven expandable library (`data/effects_manifest.json`); each effect is a `.tscn` with `size: float` + `effect_finished` signal
- Statblocks: SRD (read-only) + campaign + map-local scopes merged by `StatblockService`
- Campaign house rules: `tie_goes_to`, `critical_hit_rule` in `CampaignData.settings`
- DM has final say: every auto-calculated value, every roll, every condition can be overridden
