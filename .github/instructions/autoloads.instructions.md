
---
description: Loaded when editing autoload singletons and bootstrapping code
applyTo: 'scripts/autoloads/**'
---

Rules for autoloads and bootstrap code.

- Autoloads should be lightweight: wire `ServiceRegistry`, register adapters, and perform environment setup.
- Avoid placing heavy domain logic in autoloads; move logic to services.
- Document any autoload that remains as legacy: explain its role and migration steps.

When adding new autoloads, include a short startup sequence comment and list services registered.
