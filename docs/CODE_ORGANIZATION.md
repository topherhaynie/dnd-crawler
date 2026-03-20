# Code Organization

This document defines where code belongs in the current SOA (Service-Oriented Architecture) codebase.

## Scripts Layout

- `scripts/autoloads/`
  - Global singleton systems declared in `project.godot`.
  - Current: `ServiceBootstrap.gd`, `HttpServer.cs`

- `scripts/core/`
  - App entry and process bootstrap logic.
  - Current: `Main.gd`, `BackendRuntime.gd`

- `scripts/data/`
  - Serializable game data/resources and persistence-oriented models.
  - Current: `MapData.gd`, `PlayerProfile.gd`

- `scripts/fog/`
  - Fog-of-war truth model and LOS compositing engine.
  - Current: `FogSystem.gd`

- `scripts/network/`
  - Client-side network connection logic (player display side).
  - Current: `PlayerClient.gd`

- `scripts/player/`
  - Player runtime root/process orchestration.
  - Current: `PlayerMain.gd`, `PlayerSprite.gd`

- `scripts/protocols/`
  - Service contract definitions (protocol scripts acting as interfaces).
  - Each file declares a `class_name IXxxService`, stubs public methods, and declares signals.
  - Current: `IFogService.gd`, `IGameState.gd`, `IInputService.gd`, `IMapService.gd`,
    `INetworkService.gd`, `IPersistenceService.gd`, `IProfileService.gd`

- `scripts/registry/`
  - Central service registry autoload and typed manager wrappers.
  - Current: `ServiceRegistry.gd`, `managers/`

- `scripts/registry/managers/`
  - One `XxxManager.gd` (`extends RefCounted`) per service; holds a single `service: IXxxService` property.
  - Current: `FogManager.gd`, `GameStateManager.gd`, `InputManager.gd`, `MapManager.gd`,
    `NetworkManager.gd`, `PersistenceManager.gd`, `ProfileManager.gd`

- `scripts/render/`
  - Shared map rendering and visual overlays.
  - Current: `MapView.gd`, `GridOverlay.gd`, `IndicatorOverlay.gd`

- `scripts/services/`
  - Concrete service implementations (`extends IXxxService`).
  - Current: `FogService.gd`, `GameStateService.gd`, `InputService.gd`, `MapService.gd`,
    `NetworkService.gd`, `PersistenceService.gd`, `ProfileService.gd`

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
3. Put serializable resources and schema classes in `scripts/data/`.
4. Keep network transport code separated from UI code.
5. Every new service must have a protocol under `scripts/protocols/` and a manager under `scripts/registry/managers/`.
6. Concrete service implementations live in `scripts/services/` and extend their protocol.
7. If a new feature spans domains, add the scene controller in `ui/` and supporting service in `scripts/services/`.

## Path References

Canonical resource paths for common preloads:
- Main scene script: `res://scripts/core/Main.gd`
- DM UI controller: `res://scripts/ui/DMWindow.gd`
- Player UI controller: `res://scripts/ui/PlayerWindow.gd`
- Shared map renderer: `res://scripts/render/MapView.gd`
- Profile data model: `res://scripts/data/PlayerProfile.gd`
- Service registry: `res://scripts/registry/ServiceRegistry.gd`
- Bootstrap autoload: `res://scripts/autoloads/ServiceBootstrap.gd`

## Notes for Future Agents

- Access services only through `ServiceRegistry` typed manager properties — never use string-based `get_service()` calls in new code.
- Keep `.map` bundle semantics separate from `.sav` session state.
- If VS Code/Godot analysis reports stale path errors after moving scripts, reload VS Code and restart the Godot editor language server.
- Keep this document updated whenever files are moved between top-level script domains.
