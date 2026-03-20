---
applyTo: "scripts/**/*.gd"
---

# Fog System

## Architecture

The fog system is **GPU-only** with a clear Model / Manager / Renderer separation. There is no CPU per-pixel fallback permitted in `FogSystem.gd`.

| Component | Role |
|---|---|
| `FogModel` (`scripts/services/fog/models/FogModel.gd`) | Data class — owns `history_image`, `size`, `enabled`, `is_dm` |
| `FogManager` (`scripts/services/fog/FogManager.gd`) | Domain coordinator — owns `FogModel`, exposes fog operations, emits signals |
| `FogService` (`scripts/services/fog/FogService.gd`) | Computation helper — image math, GPU seed helpers, LOS scheduling |
| `IFogService` (`scripts/services/fog/IFogService.gd`) | Protocol — full method contract |
| `FogSystem` (`scripts/render/FogSystem.gd`) | Pure GPU renderer — SubViewports, shaders, lights, occluders |
| `fog_history_merge.gdshader` | GPU shader — merges live LOS into history ping-pong |
| `dm_mask_fog.gdshader` | GPU shader — composites fog overlay for DM/player views |

## Signal Flow

```
MapView → registry.fog.reveal_brush()
        → FogManager mutates FogModel.history_image (via FogService)
        → FogManager emits fog_changed
        → FogSystem._on_fog_model_changed()
        → GPU re-seeds from FogModel.history_image
MapView also emits its own fog_changed signal → DMWindow → network broadcast
```

**Never** route fog state mutations through `FogSystem` directly. Always go through `FogManager`.

## FogManager Operations

`FogManager` is owned by `FogManagerWrapper` (registry property `registry.fog`). All domain callers must use these methods:

| Method | Description |
|---|---|
| `configure(size, is_dm, enabled)` | (Re)size and initialise model; always emits `fog_changed` |
| `reset()` | Fill history_image black (fully hidden) |
| `set_enabled(value)` | Toggle fog; emits `fog_enabled_changed` |
| `apply_snapshot(buffer) -> bool` | Decode PNG → update model → emit `fog_changed` |
| `reveal_brush(world_pos, radius_px)` | Paint revealed circle at world position |
| `hide_brush(world_pos, radius_px)` | Paint hidden circle at world position |
| `reveal_rect(a, b)` | Fill revealed rectangle (world coords) |
| `hide_rect(a, b)` | Fill hidden rectangle (world coords) |
| `apply_seed_delta(revealed, hidden, cell_px)` | Apply cell-coordinate deltas |
| `seed_from_hidden(cell_px, hidden_cells)` | Initialise from hidden-cell dictionary |

Signals: `fog_changed`, `fog_enabled_changed(is_enabled: bool)`

## FogSystem Responsibilities

`FogSystem` is a `Node2D` placed in the scene tree. It is **not** a service. It:
- Manages two ping-pong history `SubViewport`s
- Manages the live LOS `SubViewport` with `PointLight2D` + `LightOccluder2D`
- Schedules LOS bakes via `_bake_live_los_into_history()` (GPU path only)
- **Reacts** to `FogManager.fog_changed` via `_on_fog_model_changed()` — re-seeds GPU from `FogModel.history_image`
- Does **not** own or mutate `history_image` directly; reads it from `FogModel` via `_fog_model()`

### Registry Helpers in FogSystem

```gdscript
func _fog_manager() -> FogManager:
    var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
    if registry == null or registry.fog == null:
        return null
    return registry.fog

func _fog_model() -> FogModel:
    var mgr := _fog_manager()
    if mgr == null:
        return null
    return mgr.model
```

Never access `_history_image` as a field of `FogSystem`. Always go through `_fog_model().history_image`.

## No CPU Fallbacks

**Do not add CPU per-pixel fallback paths to `FogSystem.gd`.** The entire `_bake_live_los_into_history` function uses the GPU viewport pipeline. If `_history_gpu_ready` is false, the function returns immediately.

`FogService.apply_history_brush` retains a pixel-loop only for circle geometry (unavoidable). All rectangle fills use `Image.fill_rect()`.

## History Texture Flow

1. `FogModel.history_image` (L8 `Image`) — authoritative CPU-side history; source of truth for snapshots and GPU seeds
2. Ping-pong `_history_viewports[0/1]` in `FogSystem` — GPU history, updated each LOS bake by the merge shader
3. `_history_active_index` — which viewport holds the current authoritative GPU texture
4. `_history_swap_pending` — flag set when a new GPU bake has been queued (UPDATE_ONCE) but not yet committed

## Fog State Snapshots

- `get_fog_state() -> PackedByteArray` — reads from GPU texture (falls back to `FogModel.history_image`), serializes as L8 PNG
- `apply_fog_snapshot(buffer)` / `set_fog_state(data)` — thin wrappers that delegate to `FogManager.apply_snapshot()`
- Snapshots flow: DM → Player via `fog_updated` network message; Player calls `_map_view.apply_fog_snapshot()` → `registry.fog.apply_snapshot()`

## FogService Delegation Contract

`FogService` implements the full `IFogService` protocol. Methods delegated from `FogSystem` (GPU renderer helpers):

| Method | Purpose |
|---|---|
| `rect_from_circle` | Compute dirty rect from light position + radius |
| `compact_los_dirty_regions` | Merge/trim overlapping dirty rects |
| `should_bake_los_now` | Check interval timer |
| `seed_gpu_history_from_image` | Seed both ping-pong viewports from a PNG image |
| `upload_history_texture` | Re-upload L8 image to GPU after CPU-side change |

Methods delegated from `FogManager` (domain operations):

| Method | Purpose |
|---|---|
| `apply_history_brush` | Paint a revealed/hidden circle onto history_image |
| `apply_history_rect` | Fill a revealed/hidden rectangle onto history_image |
| `apply_history_seed_delta` | Apply revealed/hidden cell deltas to history_image |
| `set_history_seed_from_hidden` | Initialise history_image from hidden-cell dictionary |

## Removed / Forbidden Patterns

- `fog_hidden_cells` on `MapData` — **removed**, do not re-introduce
- `merge_live_los_into_history` — **removed** from IFogService/FogService
- `export_hidden_cells_for_sync` — **removed**
- `commit_runtime_history_to_seed` — **removed**
- `fog_overlay.call("apply_history_brush", ...)` — **never use dynamic call**; route to `registry.fog.reveal_brush()`
- `FogSystem._history_image` — **does not exist**; use `_fog_model().history_image`

## MapData and Fog

`fog_cell_px` on `MapData` specifies the cell pixel size for fog seed / delta operations.
