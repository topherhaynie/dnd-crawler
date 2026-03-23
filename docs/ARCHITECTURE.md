# Architecture: The Vault VTT

**Engine:** Godot 4.5  
**Language:** GDScript  

---

## 1. Runtime Split

The application runs as two Godot processes communicating over local WebSocket:

| Role | Process | Key Script |
| :--- | :--- | :--- |
| **DM Host** | Authoritative — owns game state, fog, map, profiles, and input arbitration. | `scripts/core/BackendRuntime.gd`, `scripts/ui/DMWindow.gd` |
| **Player Display** | Render-only — applies DM-broadcast packets; runs no simulation logic. | `scripts/player/PlayerMain.gd`, `scripts/ui/PlayerWindow.gd` |

`scripts/core/Main.gd` is the entry point and selects which role to start based on command-line arguments.

---

## 2. Service-Oriented Architecture (SOA)

All major subsystems are accessed through a typed `ServiceRegistry` autoload. This replaces the legacy singleton pattern (GameState, FogManager, NetworkManager, InputManager autoloads).

### 2.1 Layers

```
scripts/services/<domain>/   ← IXxxService.gd (protocol), XxxService.gd (impl), XxxManager.gd (holder)
scripts/services/<domain>/models/  ← domain data classes
scripts/core/             ← ServiceRegistry.gd  (registry autoload)
scripts/autoloads/        ← ServiceBootstrap.gd (wires services into registry at startup)
```

### 2.2 Registry Access Pattern

Always use typed manager properties on `ServiceRegistry`. Never call `get_service(String)` in new code.

```gdscript
var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
if registry == null or registry.fog == null:
    return
registry.fog.service.set_fog_enabled(true)
```

### 2.3 Protocol Convention

Every protocol (`scripts/services/<domain>/IXxxService.gd`):
- `extends Node`
- Declares `class_name IXxxService`
- Declares all signals for the subsystem
- Stubs all public methods with `push_error("IXxx.method: not implemented")`

Every service (`scripts/services/<domain>/XxxService.gd`):
- `extends IXxxService` — not `extends Node`
- Does **not** redeclare signals inherited from the protocol
- Implements every method in the protocol

Every manager (`scripts/services/<domain>/XxxManager.gd`):
- `extends RefCounted`
- Single property: `var service: IXxxService = null`

### 2.4 Bootstrap

`scripts/autoloads/ServiceBootstrap.gd` runs at startup and:
1. Instantiates each `XxxService` via direct `XxxService.new()`
2. Creates the corresponding `XxxManager`, sets `manager.service = svc`
3. Assigns the manager to the `ServiceRegistry` typed property
4. Defers `add_child(svc)` on the scene root

`scripts/autoloads/HttpServer.cs` provides the embedded HTTP server for mobile/web clients. Both autoloads are declared in `project.godot`.

### 2.5 Services

| Registry property | Protocol | Service | Responsibility |
| :--- | :--- | :--- | :--- |
| `registry.fog` | `IFogService` | `FogService` | Fog truth, reveal/hide, snapshot distribution |
| `registry.map` | `IMapService` | `MapService` | Map bundle load/save, metadata |
| `registry.network` | `INetworkService` | `NetworkService` | WebSocket server and peer routing |
| `registry.game_state` | `IGameState` | `GameStateService` | Runtime player state, lock flags |
| `registry.profile` | `IProfileService` | `ProfileService` | Persistent player profiles |
| `registry.persistence` | `IPersistenceService` | `PersistenceService` | File I/O, bundle read/write |
| `registry.input` | `IInputService` | `InputService` | Input vector aggregation and arbitration |

---

## 3. Rendering Pipeline

Both DM and Player windows render through the same `MapView` scene composition:

| Layer | Content |
| :--- | :--- |
| 1 | Background |
| 2 | Map image |
| 3 | Grid overlay |
| 4 | Walls |
| 5 | Objects |
| 6 | Player sprites |
| 7 | Fog of war |
| 8 | Player viewport indicator (DM-only) |

DM-only UI (menus, toolbar, editor controls) lives outside the shared `MapView` graph.

---

## 4. Fog of War

### 4.1 Authority
- DM process is authoritative for all fog truth and LOS-driven reveals.
- Player process is render-only; it applies snapshots from the DM without running any reveal logic.

### 4.2 Storage
- Persistent history: L8 image/texture (`history_tex`) stored in map bundle.
- Live LOS: rendered in a dedicated `SubViewport` using `PointLight2D` and `LightOccluder2D` (`live_lights_tex`).
- Composite shader (`assets/effects/dm_mask_fog.gdshader`) merges history + live masks.
- History merges are monotonic (`max(existing, live)`) — revealed areas are never re-hidden except by explicit DM tool action.

### 4.3 Transport
- Full sync: chunked snapshot packets (`fog_state_snapshot_begin` / `fog_state_snapshot_chunk` / `fog_state_snapshot_end`) reassembled atomically on the player side.
- Incremental: `fog_updated` / `fog_delta` packets for lightweight updates.
- Large fog payloads must **never** be inlined into `map_loaded` or `map_updated`.

---

## 5. Network Message Flow

All messages are JSON objects encoded as UTF-8. See `docs/protocols.md` for full schemas.

### DM → Player (key messages)
| Message type | Purpose |
| :--- | :--- |
| `map_loaded` | Full map payload for initial load or reconnect recovery |
| `map_updated` | Structural map changes (grid, walls, metadata) |
| `fog_state_snapshot_*` | Chunked fog image sync |
| `fog_updated` / `fog_delta` | Incremental fog update |
| `camera_update` | Player viewport center/zoom from DM controls |
| `state` / `delta` | Token position and simulation state |

### Player → DM (key messages)
| Message type | Purpose |
| :--- | :--- |
| `display` | Handshake / role registration |
| `viewport_resize` | Player window geometry change |
| `input_event` | Mobile/web joystick input |

---

## 6. Data and Persistence

- **Map bundle** (`*.map/`): directory package containing `map.json` + `image.<ext>`. Defines map structure, grid type, calibration, and wall geometry.
- **Session state** (`*.sav/`): runtime state that references a map bundle. Not the same as a map bundle.
- **Profiles** (`user://data/profiles.json`): persistent player profiles managed by `ProfileService`.
- **Dev path** (macOS): `~/Library/Application Support/Godot/app_userdata/The Vault/data/`

---

## 7. Input Arbitration

Input vectors are merged by source priority in `InputService`:

1. DM override (highest priority)
2. Physical gamepad (`device_id`)
3. WebSocket / mobile

---

## 8. Documentation Index

- Code organization: [docs/CODE_ORGANIZATION.md](CODE_ORGANIZATION.md)
- Product requirements: [docs/REQUIREMENTS.md](REQUIREMENTS.md)
- Technical specifications: [docs/TECHNICAL_SPECIFICATIONS.md](TECHNICAL_SPECIFICATIONS.md)
- Network protocol schemas: [docs/protocols.md](protocols.md)
- Historical phase reports: [docs/history/](history/)
