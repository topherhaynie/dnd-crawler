---
description: Describe when these instructions should be loaded by the agent based on task context
applyTo: 'scripts/**/*.gd'
---

<!-- Tip: Use /create-instructions in chat to generate content with agent assistance -->

Provide project context and coding guidelines that AI should follow when generating code, answering questions, or reviewing changes.

This file is the primary instructions entry point. It should be loaded when working on GDScript files and points to more specific instruction files for focused guidance.

Referenced instruction files (placed under `.github/instructions/`):

- `architecture.instructions.md` — core architecture and runtime entry points (`applyTo: 'scripts/core/**'`).
- `protocols.instructions.md` — writing protocol/interface scripts (`applyTo: 'scripts/protocols/**/*.gd'`).
- `services.instructions.md` — service implementation guidance (`applyTo: 'scripts/services/**/*.gd'`).
- `registry-adapters.instructions.md` — `ServiceRegistry` and adapter patterns (`applyTo: 'scripts/registry/**'`).
- `autoloads.instructions.md` — autoload/bootstrap rules (`applyTo: 'scripts/autoloads/**'`).
- `gdscript-style.instructions.md` — GDScript style and linting (`applyTo: 'scripts/**/*.gd'`).
- `testing-ci.instructions.md` — tests and CI guidance (`applyTo: 'tests/**'`).
- `docs.instructions.md` — documentation standards (`applyTo: 'docs/*.md'`).

Recommended action: remove or archive `docs/INSTRUCTIONS.md` after you validate these modular instruction files. If you want, I can remove it in a follow-up patch.

Usage note for agents and humans:
- When editing scripts, load this file first to get high-level constraints and then consult the file matching the exact `applyTo` pattern for detailed rules.
