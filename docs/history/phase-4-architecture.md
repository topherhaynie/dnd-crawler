# Phase 4 Architecture Notes

Status: Complete

## Summary
Phase 4 introduces a strict runtime split:

1. Authoritative simulation (`scripts/core/BackendRuntime.gd`)
2. DM operator window (`scripts/ui/DMWindow.gd`)
3. Player render window (`scripts/ui/PlayerWindow.gd`)

The backend is authoritative for movement/collision/input arbitration. Fog delivery is now fully migrated to the image-history + snapshot transport model.

## Fog Reset Plan Reference
For the Phase 4 fog-of-war reset and clean-slate execution sequence, see:

- `docs/phase-4-fog-reset-plan.md`

## Authority Boundaries

### Backend Runtime
- Owns token simulation and collision against wall geometry.
- Reads merged input vectors from `InputManager`.
- Applies source priority: DM override > gamepad > network.
- Builds player state payloads for outbound network messages.

### DM Window
- Owns menus, tools, calibration, and viewport controls.
- Provides DM interaction input (including DM override movement channel).
- Broadcasts map/camera/state/fog packets to player displays.
- Handles DM-authoring fog edits (brush/rectangle) as UI input events.

### Player Window
- Render-only consumer of packets.
- Applies `map_loaded`, `map_updated`, `camera_update`, `state`, and fog snapshot packets.
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

### Current Flow
1. Backend advances simulation; DM runtime updates live LOS lights in `FogSystem`.
2. `FogSystem` composes persistent history (`history_tex`) with live LOS (`live_lights_tex`).
3. DM fog tools edit history directly in image space (brush/rect).
4. DM runtime sends fog full-sync as chunked snapshot packets.
5. Player runtime reassembles and applies snapshot atomically.

### DM Tool Edits
1. DM uses fog brush/rect tool in `MapView`.
2. `MapView` routes tool edits to `FogSystem` history-image methods.
3. DM runtime queues debounced snapshot broadcast for player sync.

## Current Fog Architecture

1. Shared fog runtime is `scripts/fog/FogSystem.gd`.
2. Persistent reveal history is image-backed and merged monotonically.
3. Composite shader path is `assets/effects/dm_mask_fog.gdshader`.
4. Snapshot transport uses chunked packets to avoid websocket outbound OOM.

## Deterministic Ordering Decision
This project will not implement deterministic command ordering.

Rationale:
- The runtime is local-authoritative and latency-sensitive.
- Priority arbitration (DM > gamepad > network) is sufficient for current requirements.
- Deterministic queues add complexity (buffering/clocking/replay plumbing) without practical benefit for this scope.

Future trigger to revisit:
- Only reconsider if requirements add replay/rollback, remote authoritative hosting, or strict reproducibility across distributed peers.
