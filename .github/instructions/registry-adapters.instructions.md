
---
description: Loaded when modifying or adding registry/adapters
applyTo: 'scripts/registry/**'
---

Guidance for `ServiceRegistry` and adapter patterns.

- Provide `register(name: String, instance: Object)` and `get(name: String) -> Object` on the registry autoload.
- In `register()`, perform debug-time `assert()` checks to validate the instance implements required methods/signals.
- Use adapters to present legacy APIs while delegating to new service implementations.
- Adapters should be small and temporary; include a TODO/comment linking when it can be removed.

Example registry behavior:

```
# ServiceRegistry.register("Fog", fog_service_instance)
# assert(fog_service_instance.has_method("reveal_area"))
```
