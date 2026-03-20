# AGENTS — Omni-Crawl Codebase Guide

This file is a quick navigation and workflow guide for future coding agents.

## Scope
- Engine: Godot 4.5
- Language: GDScript
- Architecture: SOA (Service-Oriented Architecture) with dual-process runtime
  - DM host process (authoritative game state, fog, input)
  - Player display process (render-only client)

## Where To Look First
- Entry and mode split: [scripts/core/Main.gd](scripts/core/Main.gd)
- DM runtime UI/controller: [scripts/ui/DMWindow.gd](scripts/ui/DMWindow.gd)
- Player runtime root: [scripts/player/PlayerMain.gd](scripts/player/PlayerMain.gd)
- Player renderer: [scripts/ui/PlayerWindow.gd](scripts/ui/PlayerWindow.gd)
- Shared map renderer: [scripts/render/MapView.gd](scripts/render/MapView.gd)
- Map model + persistence format: [scripts/services/map/models/MapData.gd](scripts/services/map/models/MapData.gd)
- Service registry: [scripts/core/ServiceRegistry.gd](scripts/core/ServiceRegistry.gd)
- Bootstrap: [scripts/autoloads/ServiceBootstrap.gd](scripts/autoloads/ServiceBootstrap.gd)

## Service-Oriented Architecture

All subsystems are accessed through typed manager properties on `ServiceRegistry`:

```gdscript
var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
registry.fog.service.set_fog_enabled(true)
```

| Registry property | Protocol | Service |
| :--- | :--- | :--- |
| `registry.fog` | `IFogService` | `FogService` |
| `registry.map` | `IMapService` | `MapService` |
| `registry.network` | `INetworkService` | `NetworkService` |
| `registry.game_state` | `IGameState` | `GameStateService` |
| `registry.profile` | `IProfileService` | `ProfileService` |
| `registry.persistence` | `IPersistenceService` | `PersistenceService` |
| `registry.input` | `IInputService` | `InputService` |

Never use `get_service(String)` in new code — always use the typed manager properties.

## Key Folders
- Service domains (protocol + service + manager + models): `scripts/services/<domain>/`
  - e.g. `scripts/services/fog/`, `scripts/services/map/`, `scripts/services/network/`, etc.
- Service registry: `scripts/core/ServiceRegistry.gd`
- Autoloads: `scripts/autoloads/` — only `ServiceBootstrap.gd` and `HttpServer.cs`
- Renderer nodes (not services): `scripts/render/` — `FogSystem.gd`, `MapView.gd`, `GridOverlay.gd`, `IndicatorOverlay.gd`

## Data and Persistence
- Map bundles: directory package `*.map`
  - `map.json`
  - `image.<ext>`
- Runtime map storage root (dev): `user://data/maps/`
- Profile storage file: `user://data/profiles.json`
  - macOS dev path:
    - `~/Library/Application Support/Godot/app_userdata/DnD Crawler/data/profiles.json`

## Profile System
- Profile resource class: [scripts/services/profile/models/PlayerProfile.gd](scripts/services/profile/models/PlayerProfile.gd)
- Profile service: `registry.profile.service` (backed by `ProfileService.gd`)
- DM profile editor is built dynamically in [scripts/ui/DMWindow.gd](scripts/ui/DMWindow.gd)
  - menu path: Edit -> Player Profiles...
  - supports add/edit/delete/import/export and gamepad/WS binding

## Network Message Flow
- Display client handshake: `{"type":"display", ...}`
- Display viewport resize: `{"type":"viewport_resize", ...}`
- DM -> display map, fog, camera, and state messages:
  - `map_loaded`
  - `map_updated`
  - `fog_state_snapshot_begin` / `fog_state_snapshot_chunk` / `fog_state_snapshot_end`
  - `fog_updated` / `fog_delta`
  - `camera_update`
  - `state` / `delta`

## Visibility Authority
- DM process is authoritative for LOS/fog reveal and gameplay visibility logic.
- Player process is render-only for visibility and should consume DM packets.
- DM/player fog-opacity differences are visual-only (same underlying revealed/hidden state).
- Prefer `fog_updated` over `map_updated` for frequent fog changes to avoid player map reload churn.

## Recent Stability Notes
- Map open flow accepts native dialog path variants and resolves nearest `.map` bundle.
- Player window connect/resize preserves world-space viewport footprint by compensating zoom.
- UI scales for HiDPI/fullscreen via [scripts/ui/DMWindow.gd](scripts/ui/DMWindow.gd) and `window/dpi/allow_hidpi=true`.

## Documentation Index
- Architecture overview: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Code organization: [docs/CODE_ORGANIZATION.md](docs/CODE_ORGANIZATION.md)
- Requirements: [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- Technical specifications: [docs/TECHNICAL_SPECIFICATIONS.md](docs/TECHNICAL_SPECIFICATIONS.md)
- Network protocol schemas: [docs/protocols.md](docs/protocols.md)
- Historical phase reports and migration logs: [docs/history/](docs/history/)

## Conventions For Future Agents
- Avoid naming `const` preload aliases the same as global `class_name` scripts.
- Prefer explicit autoload lookups (`/root/<SingletonName>`) in scripts where analyzer cannot resolve singleton identifiers.
- Keep `.map` and `.sav` semantics separate (`.map` is definition, `.sav` is runtime/session state).
- When changing DM/player viewport behavior, update both DM indicator behavior and `camera_update` broadcasts together.
- Every new service needs: a protocol, manager, and service implementation all co-located in `scripts/services/<domain>/`, a `models/` subdir for domain data classes, and a registration step in `ServiceBootstrap.gd`.
