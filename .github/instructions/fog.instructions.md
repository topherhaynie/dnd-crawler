---
applyTo: "scripts/fog/**/*.gd"
---

# Fog System

## Architecture

The fog system is **GPU-only**. There is no CPU per-pixel fallback.

| Component | Role |
|---|---|
| `FogSystem` (`scripts/fog/FogSystem.gd`) | Renderer — manages SubViewports, shaders, lights, and occluders |
| `FogService` (`scripts/services/FogService.gd`) | Service — manages fog state, delegates computation |
| `IFogService` (`scripts/protocols/IFogService.gd`) | Protocol — full method contract |
| `fog_history_merge.gdshader` | GPU shader — merges live LOS into history ping-pong |
| `dm_mask_fog.gdshader` | GPU shader — composites fog overlay for DM/player views |

## FogSystem Responsibilities

`FogSystem` is a `Node2D` placed in the scene tree. It is **not** a service. It:
- Manages two ping-pong history `SubViewport`s
- Manages the live LOS `SubViewport` with `PointLight2D` + `LightOccluder2D`
- Schedules LOS bakes via `_bake_live_los_into_history()` (GPU path only)
- Delegates **all stateful computation** to `FogService` via `_fog_service()`
- Does **not** mutate `Image` pixel data directly

## Service Access in FogSystem

`FogSystem` accesses the service through a typed helper method:

```gdscript
func _fog_service() -> IFogService:
    var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
    if registry == null or registry.fog == null:
        return null
    return registry.fog.service
```

All service dispatch calls must:
1. Call `_fog_service()` and guard on `null`
2. Call the method directly (no `has_method()` check — type is declared)
3. Never fall through to a CPU implementation if the service returns an error result

```gdscript
# Correct
var svc := _fog_service()
if svc == null:
    return
var res := svc.seed_gpu_history_from_image(...)
if not res.get("ok", false):
    return
```

## No CPU Fallbacks

**Do not add CPU per-pixel fallback paths.** The entire `_bake_live_los_into_history` function uses the GPU viewport pipeline. If `_history_gpu_ready` is false, the function returns immediately. No image pixel loops are permitted in `FogSystem.gd`.

## History Texture Flow

1. `_history_image` (L8 `Image`) — authoritative CPU-side history, source of truth for snapshots
2. Ping-pong `_history_viewports[0/1]` — GPU history, updated each bake by the merge shader
3. `_history_active_index` — which viewport is the current authoritative GPU texture
4. `_history_swap_pending` — flag set when a new GPU bake has been queued (UPDATE_ONCE) but not yet committed

## Fog State Snapshots

- `get_fog_state() -> PackedByteArray` — reads from GPU texture (or `_history_image` fallback), serializes as L8 PNG
- `set_fog_state(data) -> bool` (via `apply_fog_snapshot`) — decodes PNG, updates `_history_image`, seeds GPU history
- Snapshots are sent DM → Player via `fog_updated` network message

## FogService Delegation Contract

`FogService` implements the full `IFogService` protocol. Methods delegated from `FogSystem`:

| Method | Purpose |
|---|---|
| `rect_from_circle` | Compute dirty rect from light position + radius |
| `compact_los_dirty_regions` | Merge/trim overlapping dirty rects |
| `should_bake_los_now` | Check interval timer |
| `seed_gpu_history_from_image` | Seed both ping-pong viewports from a PNG image |
| `upload_history_texture` | Re-upload after CPU-side image change |
| `set_history_seed_from_hidden` | Initialize history from a hidden-cell dictionary |
| `apply_history_seed_delta` | Apply revealed/hidden cell deltas to history image |

## MapData and Fog

`fog_cell_px` on `MapData` specifies the cell pixel size for fog seed / delta operations.  
`fog_hidden_cells` has been **removed** — do not re-introduce it. Fog state is managed exclusively as a GPU texture snapshot.
