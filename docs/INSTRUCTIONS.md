---
description: Describe when these instructions should be loaded by the agent based on task context
# applyTo: 'Describe when these instructions should be loaded by the agent based on task context' # when provided, instructions will automatically be added to the request context when the pattern matches an attached file
---

<!-- Tip: Use /create-instructions in chat to generate content with agent assistance -->

Provide project context and coding guidelines that AI should follow when generating code, answering questions, or reviewing changes.

Project context
- Engine: Godot 4.x, GDScript. Runtime split: authoritative DM host process and render-only Player process.
- Key folders: `scripts/autoloads/`, `scripts/core/`, `scripts/services/` (new), `scripts/protocols/` (new), `scripts/registry/` (new), `scripts/data/`, `scripts/render/`, `scripts/ui/`, `scenes/`, `docs/`.
- Current hotspots: fog, map model, network message flow, and legacy autoload singletons.

AI coding guidelines
- Always prefer small, incremental changes and include adapters or feature flags for backwards compatibility.
- When proposing new modules/files, place them under the recommended folders above and provide a one-paragraph rationale.
- Prefer explicit protocols: for any new service, create a `scripts/protocols/I<Name>Service.gd` that documents public methods and signals.
- Use typed GDScript signatures where practical; include `class_name` for services and protocols.
- Avoid modifying unrelated files; keep changes scoped to the minimal set required.

Communication & coupling
- Recommend using signals/events and DTOs for inter-service communication instead of direct property access.
- When refactoring, prefer adapters that preserve legacy API names and delegate to the new service.

Testing & verification
- Provide unit tests for pure logic (services) and small integration tests for message flows. Include example test code where helpful.
- Recommend adding runtime `assert()` checks during `ServiceRegistry.register()` to validate protocol conformance in debug builds.

PR guidance for generated changes
- Each generated change should include a short migration note describing why the change was made, how it can be rolled back, and what tests were added.
- Prefer multiple small PRs scoped to a single service/consumer rather than one large refactor PR.

Documentation
- Add or update `docs/ARCHITECTURE.md` when introducing architecture-level changes.
- Add brief protocol headers in `scripts/protocols/*.gd` describing expected behavior and examples.

Agent constraints
- Do not change project-wide configurations (CI, project.godot) without explicit user approval.
- When creating code, ensure it follows existing project conventions (file layout, naming, `class_name` usage).

Example prompt for the agent
"Create a `FogService` under `scripts/services/` with an accompanying `IFogService.gd` protocol and a `ServiceRegistry` autoload. Provide unit tests for reveal/hide behavior and a small adapter for legacy callers. Keep changes minimal and explain rollback steps."

