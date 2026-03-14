# Phase 4 Architecture Notes

## Summary
Phase 4 introduces a strict runtime split:

1. Backend authority (`scripts/core/BackendRuntime.gd`)
2. DM operator window (`scripts/ui/DMWindow.gd`)
3. Player render window (`scripts/ui/PlayerWindow.gd`)

The backend is authoritative for movement and collision. Fog is currently in a clean-slate baseline mode focused on stable rendering and manual DM control.

## Fog Reset Plan Reference
For the Phase 4 fog-of-war reset and clean-slate execution sequence, see:

- `docs/phase-4-fog-reset-plan.md`

## Authority Boundaries

### Backend Runtime
- Owns token simulation and collision against wall geometry.
- Reads merged input vectors from `InputManager`.
- Applies source priority: DM override > gamepad > network.
- Automatic LOS fog reveal is disabled in the clean-slate baseline.
- Builds player state payloads for outbound network messages.

### DM Window
- Owns menus, tools, calibration, and viewport controls.
- Provides DM interaction input (including DM override movement channel).
- Broadcasts map/camera/state/fog packets to player displays.
- Handles DM-authoring fog edits (brush/rectangle) as UI input events.

### Player Window
- Render-only consumer of packets.
- Applies `map_loaded`, `map_updated`, `camera_update`, `state`, `fog_updated`, and `fog_delta`.
- Does not run movement, LOS, or fog authority logic.

## Shared Render Pipeline
Both windows instantiate `MapView` and use the same layer order:

1. Background
2. Map
3. Grid
4. Wall
5. Object
6. Player
7. Fog
8. Player viewport indicator (DM-only visibility)

DM-only overlays (toolbar/menu and editor controls) live outside the shared `MapView` graph.

## Fog of War Flow

### Baseline Flow (current)
1. Backend advances simulation for movement/collision only.
2. DM fog tools author fog cell changes in `MapView`.
3. DM runtime broadcasts plain fog updates (`fog_updated` and `fog_delta`).
4. Player runtime applies fog updates with no additional authority logic.

### DM Tool Edits
1. DM uses fog brush/rect tool in `MapView`.
2. MapView applies local edit and syncs map fog state.
3. DM runtime serializes and broadcasts fog changes.

## Current Fog Baseline

1. Single shared fog renderer implementation in `scripts/render/FogOverlay.gd`.
2. Fog transport uses plain cell payloads (no sequence/version codec path).
3. Goal is stable, predictable behavior before reintroducing advanced fog authority.

## Deterministic Ordering Decision
This project will not implement deterministic command ordering.

Rationale:
- The runtime is local-authoritative and latency-sensitive.
- Priority arbitration (DM > gamepad > network) is sufficient for current requirements.
- Deterministic queues add complexity (buffering/clocking/replay plumbing) without practical benefit for this scope.

Future trigger to revisit:
- Only reconsider if requirements add replay/rollback, remote authoritative hosting, or strict reproducibility across distributed peers.
