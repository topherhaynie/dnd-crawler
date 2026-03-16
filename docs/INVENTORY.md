# Initial Codebase Inventory — DnD Crawler

This is an initial mapping of key files to responsibilities to support the SOA migration. Keep this file as the source of truth for future agents; update as you refine ownership.

## Autoloads
- `scripts/autoloads/GameState.gd` — Global runtime state, profiles, and map metadata.
- `scripts/autoloads/FogManager.gd` — Coordinates fog-of-war updates and exposes fog APIs to UI.
- `scripts/autoloads/NetworkManager.gd` — High-level networking orchestration and peers management.
- `scripts/autoloads/InputManager.gd` — Central input aggregation and event dispatch.
- `scripts/autoloads/HttpServer.cs` — Embedded HTTP server for mobile/web client connectivity.

## Core Runtime
- `scripts/core/Main.gd` — Application entry point and initialization.
- `scripts/core/BackendRuntime.gd` — Headless/DM runtime orchestration and authoritative logic.
- `scenes/Main.tscn` — Root scene for the application.

## Data Models
- `scripts/data/MapData.gd` — Map model, serialization, and persistence formats.
- `scripts/data/PlayerProfile.gd` — Player profile resource and persistence logic.
- `scripts/tools/FogTruthCodec.gd` — Fog serialization/encoding helpers.

## Fog System
- `scripts/fog/FogSystem.gd` — Core fog-of-war visibility calculations and truth model.
- `assets/effects/dm_mask_fog.gdshader` — DM fog shader.
- `assets/effects/fog_history_merge.gdshader` — Fog history blending shader.

## Network
- `scripts/network/PlayerClient.gd` — Display-client transport and message handling.
- `assets/mobile_client/index.html` — Mobile/web client entry UI.

## Rendering
- `scripts/render/MapView.gd` — Map rendering controller and layer orchestration.
- `scripts/render/FogOverlay.gd` — Fog rendering layer.
- `scripts/render/GridOverlay.gd` — Tactical grid overlay.
- `scripts/render/IndicatorOverlay.gd` — Visual indicators and pings.

## UI
- `scripts/ui/DMWindow.gd` — DM control panel logic.
- `scripts/ui/PlayerWindow.gd` — Player view controller.
- `scenes/DMWindow.tscn` — DM UI scene.
- `scenes/PlayerWindow.tscn` — Player UI scene.

## Tools & Tests
- `scripts/tools/CalibrationTool.gd` — Dev calibration utilities.
- `scripts/tools/FogTruthCodecTest.gd` — Tests/validation for fog codec.

## Docs & Plans
- `docs/MIGRATION_PLAN.md` — SOA migration plan (pilot & phases).
- `docs/INSTRUCTIONS.md` — Archived coding instructions (migrated into `.github/instructions/`).
- `docs/ARCHITECTURE.md` — (update as migration progresses) high-level architecture documentation.

## Notes & Next Steps
- This is an initial pass — next, scaffold `scripts/registry/ServiceRegistry.gd` and the `IFogService.gd` protocol, then implement a `FogService.gd` under `scripts/services/` as a pilot.
- Keep adapters in `scripts/registry/` to maintain backwards compatibility while migrating consumers incrementally.

## Newly added (scaffolded)
- `scripts/registry/ServiceRegistry.gd` — Central registry autoload to register and lookup services with optional runtime conformance checks.
- `scripts/protocols/IFogService.gd` — Protocol describing the Fog service contract (methods and signals).
- `scripts/services/FogService.gd` — Minimal FogService implementation (pilot) exposing reveal/set/get methods and `fog_updated` signal.
- `scripts/registry/FogAdapter.gd` — Adapter shim to preserve legacy API while delegating to `FogService`.

- `scripts/autoloads/ServiceBootstrap.gd` — Runtime bootstrap: attaches `ServiceRegistry` to the scene root, creates and registers `FogService` and `FogAdapter` for development/testing. Add this script to project autoloads for consistent startup.
