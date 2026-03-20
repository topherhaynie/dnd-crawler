---
applyTo: "scripts/**/*.gd"
---

# GDScript Style and Typing

## Indentation and Formatting
- Use **tabs** for indentation (never spaces).
- One blank line between top-level functions; no trailing whitespace.
- Keep lines under 120 characters where practical.

## Explicit Typing — Always Required
Every variable, parameter, and return value must be explicitly typed. No bare `var x` or inferred types from assignment where the type is not obvious.

```gdscript
# Correct
var _map_size: Vector2 = Vector2(1920, 1080)
var _is_dm: bool = false
func get_state() -> PackedByteArray:

# Wrong — bare var, no return type
var x = something
func get_state():
```

**Exception:** loop variables over heterogeneous arrays may use `Variant` explicitly.

```gdscript
for raw in tokens:        # allowed when array is untyped
    if not raw is Node2D:
        continue
    var token := raw as Node2D
```

## Return Types
- Every `func` must declare `-> ReturnType`.
- Use `-> void` for no return value.
- Use `-> Variant` only when the return type genuinely varies (e.g. `get_profile_by_id`).

## Naming Conventions
| Element | Convention | Example |
|---|---|---|
| Class name | PascalCase | `FogSystem`, `IFogService` |
| Method | snake_case | `get_fog_state()` |
| Variable | snake_case, private prefixed `_` | `_history_image`, `fog_cell_px` |
| Constant | SCREAMING_SNAKE | `LOS_BAKE_GAIN`, `MAX_DIRTY_REGIONS` |
| Signal | snake_case past-tense or event | `fog_updated`, `map_loaded` |
| Enum | PascalCase type, SCREAMING members | `GridType.SQUARE` |

## Avoid Shadowing Built-in Properties
- Do **not** use `visible` as a local or parameter name inside `Node2D`/`CanvasItem` scripts — it shadows the base class property and triggers `SHADOWED_VARIABLE_BASE_CLASS`.
- Use descriptive alternatives: `is_visible`, `show_overlay`, etc.

## Dictionary `.get()` Temporaries
When calling `.get()` on a `Dictionary` and the type is not obvious, annotate the result as `Variant` to suppress analyzer warnings:

```gdscript
var val: Variant = my_dict.get("key", null)
```

## Signals
- Declare signals at the top of the file, after `extends`/`class_name`.
- Concrete service classes must **not** redeclare signals already declared in their protocol base class.

## Const Preloads
- Do not name a `const` preload alias the same as a global `class_name` script.

```gdscript
# Wrong — collides with class_name FogService
const FogService := preload("res://scripts/services/FogService.gd")

# Correct
const FogServiceScene := preload("res://scripts/services/FogService.gd")
```

## Autoload / Singleton Access
When the static analyzer cannot resolve a singleton identifier, use explicit `/root/` lookup and cast:

```gdscript
var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
```

Never use `Engine.get_singleton()` or bare identifier access for project autoloads in service scripts.
