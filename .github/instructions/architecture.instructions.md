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

All protocols live co-located with their domain under `scripts/services/<domain>/`. Each protocol:
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

All services live co-located with their domain under `scripts/services/<domain>/`. Each service:
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

All managers live co-located with their domain under `scripts/services/<domain>/`. Each manager:
- `extends RefCounted`
- Has a single `var service: IXxxService = null` property

```gdscript
extends RefCounted
class_name FogManager

var service: IFogService = null
```

## View / ViewModel Access Rule

**Views** (scenes, windows, UI scripts such as `DMWindow.gd`, `PlayerWindow.gd`) and **view-models** must only call **manager** methods. They must never reach through to the underlying service directly.

```gdscript
# Correct — view calls the manager
registry.fog.set_fog_enabled(true)

# Wrong — view bypasses the manager and calls the service directly
registry.fog.service.set_fog_enabled(true)
```

**Why:** The manager is the public API boundary for a subsystem. It is the appropriate place to add cross-cutting logic (validation, logging, state coordination). Bypassing it from the view layer breaks that boundary and creates hidden coupling.

**Corollary:** Every capability that a view needs must be exposed as a method on the manager, not accessed via `manager.service`. If the manager is missing a method, add it there — do not work around the gap by reaching into `manager.service` from a view.

**Corollary:** All core service functionality must be bound by its protocol (`IXxxService`). No method should exist on a concrete service without a corresponding stub in the protocol. This ensures managers can always depend on typed, protocol-guaranteed APIs rather than concrete implementations.

## ServiceRegistry

`scripts/core/ServiceRegistry.gd` — a `Node` added to the scene root. Has typed manager properties for every subsystem:

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
6. Place all three files (`IXxxService.gd`, `XxxService.gd`, `XxxManager.gd`) under `scripts/services/<domain>/` with a `models/` subdir for data classes

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

## Never Use `has_method` on Typed Objects

`has_method()` creates **silent-failure** code: when a method is absent the branch is silently skipped with no error, making bugs invisible. Protocol base classes eliminate the need for `has_method` entirely — every declared method has a `push_error` stub, so calling on a null-stubbed service produces a visible error instead of a silent no-op.

**Rules:**
- Never call `obj.has_method("foo")` when `obj` is typed to a protocol, service, manager, or any class with a `class_name`. The method is guaranteed present.
- Guard on `null` when the object might be absent — not on `has_method`.
- If a method is missing from a protocol, **add a stub** to the protocol rather than adding a `has_method` guard at the call site.
- When adding a new method to a concrete service, also add the corresponding stub to the protocol (`IXxxService.gd`) in the same commit.

```gdscript
# Wrong — has_method on a typed service variable
if nm != null and nm.has_method("bind_peer"):
    nm.bind_peer(peer_id, player_id)

# Wrong — has_method on a typed concrete class variable
if _backend and _backend.has_method("step"):
    _backend.step(delta)

# Correct — null guard only; the method is guaranteed by the protocol stub
if nm != null:
    nm.bind_peer(peer_id, player_id)

if _backend != null:
    _backend.step(delta)
```

**Legitimate exceptions** (the only cases where `has_method` is acceptable):
- Godot engine **version compatibility** checks on engine-provided objects (e.g. `ws_peer.has_method("get_current_outbound_buffered_amount")`)
- Genuinely **polymorphic scene nodes** stored as `Node` where no common typed base class can be used (e.g. mixed `TokenSprite` / `PlayerSprite` nodes in the same layer in `MapView`)
