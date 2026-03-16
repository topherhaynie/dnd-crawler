
---
description: Loaded when authoring protocol/interface scripts
applyTo: 'scripts/protocols/**/*.gd'
---

Guidance for writing protocol (interface) scripts.

- Use `class_name I<Name>Service` for protocols (e.g., `IFogService`).
- Document public methods and emitted signals at the top of the file.
- Keep protocols minimal: method signatures, expected signal names and payload types, and short examples.
- Prefer typed signatures where possible; show expected return values and exceptions/edge cases.

Example header:

```
# IFogService.gd
class_name IFogService
# Methods:
# func reveal_area(pos: Vector2, radius: float) -> void
# Signals:
# signal fog_updated(state: Dictionary)
```

When updating a protocol, add a migration note pointing to services that must be updated.
