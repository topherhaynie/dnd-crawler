# Code Organization

This document defines where code belongs in the current SOA (Service-Oriented Architecture) codebase.

## Scripts Layout

- `scripts/autoloads/`
  - Global singleton systems declared in `project.godot`.
  - Current: `ServiceBootstrap.gd`, `HttpServer.cs`

- `scripts/core/`
  - App entry, process bootstrap logic, and the service registry.
  - Current: `Main.gd`, `BackendRuntime.gd`, `ServiceRegistry.gd`

- `scripts/player/`
  - Player runtime root/process orchestration.
  - Current: `PlayerMain.gd`, `PlayerSprite.gd`

- `scripts/render/`
  - Shared map rendering, visual overlays, and the fog-of-war GPU renderer.
  - Current: `MapView.gd`, `GridOverlay.gd`, `IndicatorOverlay.gd`, `FogSystem.gd`

- `scripts/services/`
  - Domain directories — each contains the protocol (`IXxxService.gd`), service implementation (`XxxService.gd`), manager (`XxxManager.gd`), and a `models/` subdir for data classes.

  - `scripts/services/fog/`
    - Fog state management service domain.
    - Current: `IFogService.gd`, `FogService.gd`, `FogManager.gd`, `models/`

  - `scripts/services/map/`
    - Map bundle lifecycle service domain.
    - Current: `IMapService.gd`, `MapService.gd`, `MapManager.gd`, `models/MapData.gd`

  - `scripts/services/network/`
    - WebSocket server and player-side network client domain.
    - Current: `INetworkService.gd`, `NetworkService.gd`, `NetworkManager.gd`, `PlayerClient.gd`, `models/`

  - `scripts/services/game_state/`
    - Runtime player state and lock flags domain.
    - Current: `IGameState.gd`, `GameStateService.gd`, `GameStateManager.gd`, `models/`

  - `scripts/services/profile/`
    - Persistent player profile domain.
    - Current: `IProfileService.gd`, `ProfileService.gd`, `ProfileManager.gd`, `models/PlayerProfile.gd`

  - `scripts/services/persistence/`
    - File I/O and bundle read/write domain.
    - Current: `IPersistenceService.gd`, `PersistenceService.gd`, `PersistenceManager.gd`, `models/`

  - `scripts/services/input/`
    - Input vector aggregation and arbitration domain.
    - Current: `IInputService.gd`, `InputService.gd`, `InputManager.gd`, `models/`

- `scripts/tests/`
  - Integration and message-flow test scripts (run headless or in-editor).
  - Current: `fog_delta_broadcast_test.gd`, `handshake_role_test.gd`,
    `network_input_parsing_test.gd`, `protocol_versioning_test.gd`

- `scripts/tools/`
  - Editor/runtime helper tools used by DM workflows.
  - Current: `CalibrationTool.gd`

- `scripts/ui/`
  - DM and player-facing window controllers and runtime UI composition.
  - Current: `DMWindow.gd`, `PlayerWindow.gd`

- `scripts/utils/`
  - Shared utility helpers with no service dependency.
  - Current: `JsonUtils.gd`

- `tests/`
  - Top-level test suites organized by type.
  - Current: `tests/unit/` (`test_fog_service.gd`, `test_persistence.gd`),
    `tests/smoke/` (`smoke_fog_gd.gd`)

## Placement Rules

1. Keep autoloads limited to bootstrap and cross-cutting infrastructure (`ServiceBootstrap`, `HttpServer`).
2. Put scene-owned behavior in domain folders (`ui`, `render`, `player`, etc.), not in root.
3. Put domain data classes in the `models/` subdir of their owning service domain.
4. Keep network transport code in `scripts/services/network/`.
5. Every new service must have its protocol (`IXxxService.gd`), manager (`XxxManager.gd`), and implementation (`XxxService.gd`) co-located under `scripts/services/<domain>/`, plus a `models/` subdir for data classes, plus a registration step in `ServiceBootstrap.gd`.
6. `ServiceRegistry.gd` lives in `scripts/core/` — access it via `/root/ServiceRegistry`.
7. If a new feature spans domains, add the scene controller in `ui/` and its service domain under `scripts/services/`.

## Path References

Canonical resource paths for common preloads:
- Main scene script: `res://scripts/core/Main.gd`
- DM UI controller: `res://scripts/ui/DMWindow.gd`
- Player UI controller: `res://scripts/ui/PlayerWindow.gd`
- Shared map renderer: `res://scripts/render/MapView.gd`
- Fog GPU renderer: `res://scripts/render/FogSystem.gd`
- Service registry: `res://scripts/core/ServiceRegistry.gd`
- Bootstrap autoload: `res://scripts/autoloads/ServiceBootstrap.gd`
- Map data model: `res://scripts/services/map/models/MapData.gd`
- Profile data model: `res://scripts/services/profile/models/PlayerProfile.gd`
- Player WebSocket client: `res://scripts/services/network/PlayerClient.gd`

## Notes for Future Agents

- Access services only through `ServiceRegistry` typed manager properties — never use string-based `get_service()` calls in new code.
- Keep `.map` bundle semantics separate from `.sav` session state.
- If VS Code/Godot analysis reports stale path errors after moving scripts, reload VS Code and restart the Godot editor language server.
- Keep this document updated whenever files are moved between top-level script domains.
