---
applyTo: "scripts/**/*.gd"
---

# Architecture: SOA Registry Pattern

## Overview
The codebase uses a **Service-Oriented Architecture** (SOA) with a typed registry. All major subsystems are accessed through the `ServiceRegistry` autoload via typed manager properties.

## Registry Access Pattern

**Always** use the typed manager properties on `ServiceRegistry`. Never call `get_service(String)` for new code.

```gdscript
# Correct — typed registry access
var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
if registry == null or registry.fog == null:
    return
registry.fog.service.set_fog_enabled(true)

# Wrong — string-based lookup
registry.get_service("Fog").set_fog_enabled(true)
```

## Protocol Classes (interfaces)

All protocols live in `scripts/protocols/`. Each protocol:
- `extends Node` (not `RefCounted` — services are Nodes added to the scene tree)
- Declares `class_name IXxxService`
- Declares all signals for the subsystem
- Declares all public methods with `push_error("IXxx.method: not implemented")` stubs
- Returns typed defaults (empty `PackedByteArray()`, `Vector2i.ZERO`, etc.)

```gdscript
extends Node
class_name IFogService

signal fog_updated(state: Dictionary)

func set_fog_enabled(_enabled: bool) -> void:
    push_error("IFogService.set_fog_enabled: not implemented")
```

## Concrete Services

All services live in `scripts/services/`. Each service:
- `extends IXxxService` — **not** `extends Node`
- Does **not** redeclare signals already in the protocol base class
- Implements every method declared in the protocol

```gdscript
extends IFogService
class_name FogService

# No `signal fog_updated` — inherited from IFogService

func set_fog_enabled(enabled: bool) -> void:
    _fog_enabled = enabled
```

## Manager Classes

All managers live in `scripts/registry/managers/`. Each manager:
- `extends RefCounted`
- Has a single `var service: IXxxService = null` property

```gdscript
extends RefCounted
class_name FogManager

var service: IFogService = null
```

## ServiceRegistry

`scripts/registry/ServiceRegistry.gd` — a `Node` added to the scene root. Has typed manager properties for every subsystem:

```gdscript
var fog: FogManager = null
var map: MapManager = null
var network: NetworkManager = null
var game_state: GameStateManager = null
var profile: ProfileManager = null
var persistence: PersistenceManager = null
var input: InputManager = null
```

The `get_service(String)` method exists only as a backwards-compat shim — do not use it in new code.

## ServiceBootstrap

`scripts/autoloads/ServiceBootstrap.gd` instantiates all services by class name (no `load()` paths), wires them into managers, and defers `add_child` calls. When adding a new service:
1. Instantiate via `XxxService.new()`
2. Create manager `XxxManager.new()`
3. Set `manager.service = svc`
4. Assign to `registry.xxx = manager`
5. Defer `root.call_deferred("add_child", svc)`

## Responsibility Separation

| Concern | Owner |
|---|---|
| Runtime player state (locks, positions) | `GameStateService` / `IGameState` |
| Player profile persistence | `ProfileService` / `IProfileService` |
| Map lifecycle | `MapService` / `IMapService` |
| Fog rendering (GPU) | `FogSystem` (renderer, not a service) |
| Fog state management | `FogService` / `IFogService` |
| WebSocket server | `NetworkService` / `INetworkService` |
| Multi-source input | `InputService` / `IInputService` |
| JSON file persistence | `PersistenceService` / `IPersistenceService` |

## Dual-Process Runtime

- **DM process** — authoritative game state, runs `ServiceBootstrap`, owns `FogSystem`
- **Player process** — render-only, connects via WebSocket, does not run service bootstrap

The player display receives `map_loaded`, `fog_updated`, `camera_update`, `state`/`delta` messages from the DM and applies them without running game logic.
