
---
description: Loaded for general GDScript style and linting guidelines
applyTo: 'scripts/**/*.gd'
---

GDScript-specific rules and common pitfalls.

- Use typed function signatures and variable declarations where possible.
- Prefer `class_name` for exported service/protocol classes.
- Avoid using `visible` as a parameter or local variable name in Node2D/CanvasItem scripts (triggers analyzer warnings).
- Use `assert()` for debug-time contract checks; keep them out of release builds when possible.
- Keep functions small and prefer composition over inheritance.

Naming conventions:
- `FooService` for services, `IFooService` for protocols, and `FooAdapter` for adapters.
