
---
description: Loaded when implementing service logic
applyTo: 'scripts/services/**/*.gd'
---

Service implementation guidelines.

- Create the protocol first (`scripts/protocols/I<Name>Service.gd`).
- Use `class_name <Name>Service` and typed method signatures where practical.
- Services should own domain state and expose behavior via methods and signals only.
- Avoid direct scene-tree manipulation from services; expose callbacks or signals for UI code.
- Keep private helpers internal and test public API behavior via unit tests.

Lifecycle notes:
- Services may have `init()`/`start()`/`stop()` lifecycle methods; register them with `ServiceRegistry` during startup.
