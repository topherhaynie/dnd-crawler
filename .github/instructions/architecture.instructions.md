
---
description: Loaded when working on core architecture and runtime entry points
applyTo: 'scripts/core/**'
---

Project architecture guidance for DM/Player runtime and top-level layout.

- Engine: Godot 4.x. Runtime split: authoritative DM host and render-only Player.
- Entry points: `scripts/core/Main.gd`, `scripts/core/BackendRuntime.gd`, and scenes in `scenes/`.
- Keep orchestration and lifecycle code in `scripts/core/`.
- Prefer services for domain logic; use `scripts/services/` for implementations and `scripts/protocols/` for contracts.
- Avoid putting domain logic in scenes or UI controllers; UI should subscribe to service signals.

When editing core files, include a short note describing the impact on both DM and Player processes and required migration steps.
