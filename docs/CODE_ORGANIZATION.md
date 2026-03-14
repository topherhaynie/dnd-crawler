# Code Organization

This document defines where code belongs after Phase 3.5 cleanup.

## Scripts Layout

- `scripts/core/`
  - App entry and process bootstrap logic.
  - Current: `Main.gd`, `BackendRuntime.gd`

- `scripts/ui/`
  - DM and player-facing window controllers and runtime UI composition.
  - Current: `DMWindow.gd`, `PlayerWindow.gd`

- `scripts/render/`
  - Shared map rendering and visual overlays.
  - Current: `MapView.gd`, `GridOverlay.gd`, `FogOverlay.gd`, `IndicatorOverlay.gd`

- `scripts/data/`
  - Serializable game data/resources and persistence-oriented models.
  - Current: `MapData.gd`, `PlayerProfile.gd`

- `scripts/player/`
  - Player runtime root/process orchestration.
  - Current: `PlayerMain.gd`, `PlayerSprite.gd`

- `scripts/network/`
  - Client-side network connection logic (player display side).
  - Current: `PlayerClient.gd`

- `scripts/tools/`
  - Editor/runtime helper tools used by DM workflows.
  - Current: `CalibrationTool.gd`

- `scripts/autoloads/`
  - Global singleton systems declared in `project.godot`.
  - Current: `GameState.gd`, `InputManager.gd`, `NetworkManager.gd`

- `scripts/map_objects/`
  - Reserved for map object systems introduced in later phases.

## Placement Rules

1. Keep autoloads limited to cross-system state/services only.
2. Put scene-owned behavior in domain folders (`ui`, `render`, `player`, etc.), not in root.
3. Put serializable resources and schema classes in `scripts/data/`.
4. Keep network transport code separated from UI code.
5. If a new feature spans domains, add the scene controller in `ui/` and supporting model/service in the matching folder.

## Path References

When adding preloads or dynamic `load(...)`, prefer these canonical paths:
- Main scene script: `res://scripts/core/Main.gd`
- DM UI controller: `res://scripts/ui/DMWindow.gd`
- Player UI controller: `res://scripts/ui/PlayerWindow.gd`
- Shared map renderer: `res://scripts/render/MapView.gd`
- Profile data model: `res://scripts/data/PlayerProfile.gd`

## Notes for Future Agents

- If VS Code/Godot analysis reports stale path errors after moving scripts, reload VS Code and restart the Godot editor language server.
- Keep this document updated whenever files are moved between top-level script domains.
