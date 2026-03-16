# Phase 4 Fog Reset Plan

## Purpose
Reset fog of war implementation to restore:

1. Shared DM/Player rendering behavior
2. Stable performance under movement and camera updates
3. Smooth visual presentation independent of coarse gameplay truth
4. Safe network payload behavior (no outbound queue OOM)
5. A true clean-slate baseline with minimal moving parts

## Constraints

1. DM remains authoritative for fog truth and LOS-driven reveals.
2. Player remains render-only for fog/visibility.
3. DM and Player both use the same MapView and FogOverlay rendering path.
4. Rendering may smooth/feather visual output but must not mutate truth.

Current clean-slate decision:
1. Automatic LOS fog reveal is disabled until baseline stability is proven.
2. DM fog tools are the only active fog-authoring path in this stage.

## Work Breakdown

### Sub-point 4.1: Freeze and Reset Scope

1. Stop iterative fog tweaks outside this plan.
2. Keep public integration points unchanged:
   1. `MapView.apply_fog_state`
   2. `MapView.apply_fog_delta`
   3. `fog_updated` / `fog_delta` packets
3. Remove renderer-side truth migration logic from shared renderer paths.
4. Establish a single fog quality baseline profile for both DM and Player.

### Sub-point 4.2: Baseline Truth Stage (Manual Authority)

1. Keep fog truth as direct hidden-cell state on map data.
2. Support two operations only:
   1. Reveal cells
   2. Hide cells
3. Disable automatic LOS reveal while stabilizing renderer + transport.

Deliverables:

1. DM-side baseline authority updates (`scripts/ui/DMWindow.gd`, `scripts/autoloads/FogManager.gd`)
2. `scripts/ui/DMWindow.gd` direct fog delta/full-sync broadcast updates

### Sub-point 4.3: Unified Render Layer Refactor

1. Keep one FogOverlay implementation for DM and Player.
2. Render from authoritative hidden-cell truth only.
3. Use a simple cell-mask renderer first; visual polish can come later.
4. Do not rebuild fog on every camera micro-movement.
5. Rebuild policy:
   1. Full rebuild on map/fog state reset
   2. Dirty-region updates for fog deltas
6. Keep DM/player differences limited to optional visibility toggle controls, not different fog logic.

Deliverables:

1. `scripts/render/FogOverlay.gd` rewritten to baseline architecture
2. `scripts/render/MapView.gd` cleanup of fog camera-coupled churn

### Sub-point 4.4: Transport and Packet Safety

1. Define safe fog full-sync format using plain hidden-cell payloads.
2. Keep delta packets bounded by size/cell count.
3. Coalesce/delay fog bursts under pressure.
4. Add fallback full-sync cadence to heal packet drops.
5. Never include giant fog arrays in map bootstrap payloads.

Deliverables:

1. `scripts/autoloads/NetworkManager.gd` payload safety updates
2. `scripts/ui/DMWindow.gd` fog broadcast policy updates
3. `scripts/ui/PlayerWindow.gd` decoding support

### Sub-point 4.5: Observability and Verification

1. Add fog metrics logging hooks (debug-only):
   1. rebuild time ms
   2. changed cells per tick
   3. packet bytes per fog message type
   4. outbound queue pressure events
2. Add stress-test script/scenario for repeated reveal/hide and camera movement.

Deliverables:

1. Debug telemetry in fog/network code paths
2. Test checklist document updates

## Acceptance Criteria

1. DM and Player show matching fog state for the same camera framing.
2. No websocket outbound OOM errors during sustained movement and reveal events.
3. Fog updates remain responsive under normal play load.
4. Visual edges are acceptable and stable at normal zoom levels.
5. Camera movement does not cause major frame-time spikes.

## Implementation Sequence

1. Complete Sub-point 4.1 (freeze/reset boundaries).
2. Complete Sub-point 4.2 (baseline truth stage).
3. Complete Sub-point 4.3 (renderer).
4. Complete Sub-point 4.4 (transport safety).
5. Complete Sub-point 4.5 (observability and verification).

## Out of Scope

1. Deterministic rollback/replay networking.
2. Remote authoritative server architecture.
3. Non-fog gameplay system rewrites.

## Clean-context Handoff Notes

1. Start from this plan file as source of truth.
2. Implement one sub-point at a time and validate before proceeding.
3. Do not modify public fog API signatures unless explicitly documented and approved.
