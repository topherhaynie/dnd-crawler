# Service-Oriented Migration Plan — DnD Crawler

## Goal
Evolve the codebase to a Service-Oriented Architecture (SOA) with clear protocols, a central service registry, and incremental refactors to improve separation of concerns, modularity, testability, and maintainability.

## Principles
- Single responsibility per service (Map, Fog, Network, Profile, Persistence, Input, Rendering).
- Explicit, documented protocols (interfaces) for services; runtime assertion on registration.
- Services communicate via signals/events and DTOs; avoid direct field access across modules.
- Backwards-compatible adapters during migration to avoid large, risky rewrites.

## High-level phases

Phase 0 — Inventory (current)
- Produce a mapping: files → responsibilities → public APIs → consumers.
- Mark high-risk, high-coupling hotspots (fog, map model, network messages).

Phase 1 — Contracts & Registry
- Define protocol scripts for each service (e.g., `IFogService.gd`, `IMapService.gd`).
- Implement `ServiceRegistry.gd` autoload: `register(name, instance)` and `get(name)` with runtime conformance checks.
- Add a lightweight `ServiceAdapter` pattern to present legacy APIs while delegating to new services.

Phase 2 — Pilot: FogService
- Create `scripts/protocols/IFogService.gd` documenting expected methods and signals.
- Implement `scripts/services/FogService.gd` that owns fog state, LOS calculations, and emits `fog_updated` signals.
- Provide `scripts/registry/FogAdapter.gd` that exposes legacy functions expected by existing callers.
- Replace one consumer (e.g., `MapView.gd` or a DM UI path) to use `ServiceRegistry.get("Fog")` directly.
- Add unit tests for `FogService` and integration tests for DM→player fog message flow.

Phase 3 — Service-by-service migration
- Migrate MapService, NetworkService, ProfileService, PersistenceService, InputService.
- For each service: define protocol, implement service, provide adapter, migrate consumers, have the user test, remove adapter.

Phase 4 — Cleanup and enforcement
- Remove legacy singletons when no consumers remain.
- Add CI checks: protocol conformance tests, linter rules enforcing registry use.
- Update docs and onboarding materials.

## Detailed pilot steps (Fog)
1. Create `scripts/protocols/IFogService.gd` (class_name IFogService) listing:
   - `func reveal_area(pos: Vector2, radius: float) -> void`
   - `func set_fog_enabled(enabled: bool) -> void`
   - `func get_fog_state() -> Dictionary`
   - signals: `fog_updated(state: Dictionary)`
2. Implement `scripts/services/FogService.gd` with clear public API and private helpers.
3. Implement `scripts/registry/FogAdapter.gd` that preserves legacy API names and forwards to FogService.
4. Autoload `ServiceRegistry.gd` at startup; wire `ServiceRegistry.register("Fog", FogService.instance)`.
5. Replace one consumer call site to use the registry and assert the service implements `IFogService`.
6. Add unit tests for the FogService corner cases (reveal, hide, serialization, merge).

## Testing & CI
- Unit tests for each service (pure logic) using Godot's unit test harness or custom test runner.
- Integration test for networked DM→player message flows (fog, map load).
- CI pipeline steps: static analysis, unit tests, headless startup smoke test.

Note: during initial migration we patched the autoload bootstrap and a unit test harness to explicitly load service scripts to avoid analyzer scope errors on headless runs. As a follow-up, standardize on `class_name` exports for services and update `ServiceBootstrap.gd` to use direct `ClassName.new()` once the codebase is stable.

## Rollout checklist before removing legacy APIs
- All consumers migrated or wrapped by adapters.
- Tests cover service behavior and message serialization.
- Performance profiling shows no regressions in critical flows.
- Rollback plan: keep adapters and feature flag to route calls to legacy behavior if issues arise.

## Risks and mitigations
- Risk: subtle runtime contract drift (duck typing). Mitigation: runtime `assert` during `register()` and optional debug-mode strict checks.
- Risk: large merge conflicts. Mitigation: small incremental PRs per service and consumer, prefer branch-per-service.

## Estimated timeline (suggested)
- Inventory: 2–3 days
- Registry + Fog pilot: 3–5 days
- Service migrations (per service): 2–4 days each depending on complexity
- Cleanup & CI additions: 3–5 days

## Deliverables for pilot
- `scripts/protocols/IFogService.gd`
- `scripts/services/FogService.gd`
- `scripts/registry/ServiceRegistry.gd`
- `scripts/registry/FogAdapter.gd` (temporary)
- Tests and updated docs: `docs/ARCHITECTURE.md`, `docs/MIGRATION_PLAN.md`

## Contacts & ownership
- Suggested owners: maintainers familiar with fog, network, and DM flow. Start with the author of current `FogManager.gd` and `FogSystem.gd`.

---
Note: implement the registry and protocol files first so other team members can begin adapting code gradually.
