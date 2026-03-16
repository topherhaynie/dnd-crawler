
---
description: Loaded when authoring or updating project documentation
applyTo: 'docs/*.md'
---

Documentation standards for architecture and protocol docs.

- Update `docs/ARCHITECTURE.md` and `docs/MIGRATION_PLAN.md` when making architecture-level changes.
- Protocol files in `scripts/protocols/` should include a short header describing methods and signals; mirror that in docs.
- Add migration notes to docs for any breaking changes or protocol updates.

Documentation style:
- Keep concise, example-driven content. Show code snippets for common usage patterns.
- Link to the service and protocol files when documenting behaviors.
