# Plan: Omni-Crawl VTT — Multi-Phase Implementation (v2)

## Project Context
- Godot 4.5, GDScript only (project.godot currently has .NET config — needs cleanup)
- 6 players target; expandable via mobile WebSocket (no hard cap on WS slots)
- Dual-window: DM Window + shared Player TV Window (future: per-player windows)
- Dev: macOS, Deployment: Windows
- DM has separate Editor Mode and Play Mode within the DM Window

---

## Phase 1: Foundation — Project Scaffold & Dual-Window Architecture
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

## Phase 2: Map System — Import, Grid/Hex & Calibration
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

## Phase 3: Extensible Player Profiles & Input Binding
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

## Phase 4: Movement & Fog of War
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

## Phase 5: Input Sources — Gamepad & WebSocket Mobile
**Goal:** Gamepads and phones drive players simultaneously; unlimited WS slots.
*Depends on: Phases 3 & 4*

1. `InputManager.gd`: per-frame `get_vector(player_id) -> Vector2`; checks `GameState.player_locked[id]` → returns `Vector2.ZERO` if locked
2. Gamepad: `Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X/Y)` → normalized, dead-zone applied
3. `NetworkManager.gd`: `WebSocketMultiplayerPeer` on port `9090`; parse `{ "player_id": int, "x": float, "y": float }`; sanitize (clamp x/y to `[-1,1]`, validate player_id exists in profiles)
4. Mobile client: `assets/mobile_client/index.html` — virtual joystick (nipplejs or canvas); connects to `ws://<host-ip>:9090`
5. WS slots: no hard cap in `NetworkManager`; `GameState` holds all active player profiles

**Verification:** 4 gamepads + 2 phones all move independently; malformed WS packets are discarded silently

---

## Phase 6: DM Editor Mode — Map Object Placement
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

## Phase 7: Auto-Trigger Logic & DM Notification Queue
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

## Phase 8: DM Play Tools — FoW Brush, AoE Templates & Map Navigation
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

## Phase 9: Game State Save / Load (Named Slots)
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

## Phase 10: Cross-Platform Polish & Integration QA
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

## Phase 11: Visual Effects System — Expandable Library
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

## Phase 12: Roaming Encounters Framework
**Goal:** DM places moving patrol entities that carry their own trigger zones.
*Depends on: Phases 6 & 7 — lower priority than Phase 11*

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
