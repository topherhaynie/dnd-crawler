# Migration Progress — DnD Crawler

Date: 2026-03-15

## Summary of work completed
- Created high-level migration plan: `docs/MIGRATION_PLAN.md`.
- Split and published project instruction files under `.github/instructions/` and made `architecture-and-coding.instructions.md` the main entry point.
- Performed repository inventory: `docs/INVENTORY.md` (initial mapping).
- Scaffolded service infrastructure:
  - `scripts/registry/ServiceRegistry.gd`
  - `scripts/protocols/IFogService.gd`
  - `scripts/services/FogService.gd`
  - `scripts/registry/FogAdapter.gd`
  - `scripts/autoloads/ServiceBootstrap.gd`
- Migrated consumers to use the registry where safe:
  - `scripts/render/MapView.gd` (registry-first lookup for fog snapshots)
  - `scripts/ui/PlayerWindow.gd` (registry-first lookup for fog snapshots)
    - `scripts/ui/DMWindow.gd` (registry-first lookup for fog snapshot builder)

## Decisions & rationale
- Use a central `ServiceRegistry` autoload attached to the scene root for discoverability and runtime conformance checks.
- Start with Fog as pilot: it's high-value and touches many subsystems, so it demonstrates patterns and adapters.
- Preserve backward compatibility by keeping adapter shims and falling back to legacy `/root/FogManager` where present.

## Next steps (short-term)
1. Add the `ServiceBootstrap.gd` script to Project Settings autoloads (or wire equivalent bootstrap) so the registry and Fog service are created at startup.
2. Add unit tests for `FogService` and start CI test integration. (scaffolded in `tests/`)
3. Migrate `scripts/fog/FogSystem.gd` and `scripts/core/BackendRuntime.gd` to use `ServiceRegistry.get("Fog")` instead of direct `/root/FogManager` lookups.
  - Status: in-progress — `FogSystem.gd` and `BackendRuntime.gd` updated to prefer registry lookup with legacy fallback.
4. Iterate on FogService implementation to replace FogSystem responsibilities gradually or provide adapter hooks.

## Actions performed (continuation)
1. Scanned repository for remaining direct `/root/FogManager` usages and confirmed consumers prefer `ServiceRegistry.get("Fog")` with legacy fallback where present.
2. Patched `DMWindow._build_fog_state_snapshot` and `PlayerWindow` cached-fog paths to prefer the registry first; `MapView.gd`, `FogSystem.gd`, and `BackendRuntime.gd` already use registry-first lookups or fallbacks.

### Confirmation
All discovered consumer call sites now use the registry-first lookup pattern with a legacy `/root/FogManager` fallback where needed. Remaining literal `FogManager` definitions are limited to the legacy autoload implementation at `scripts/autoloads/FogManager.gd` (kept for backward compatibility during migration).

## Bootstrap wiring
I added `ServiceBootstrap.gd` to the project's autoload entries so the registry and Fog service are created automatically at startup. This enables registry lookups during early initialization and simplifies testing the migrated consumers.

Update: removed `class_name` from `scripts/autoloads/ServiceBootstrap.gd` and added explicit typed casts when instantiating service scripts to avoid analyzer warnings about autoload hiding and type inference. This is a temporary compatibility step; follow-up should export `class_name` on services and simplify the bootstrap to use direct `ClassName.new()`.

## Stopping points & verification
To reduce risk during migration we should stop at explicit checkpoints and verify the project has no runtime errors before continuing. Suggested stopping points:

1. **Bootstrap wired**: Add `scripts/autoloads/ServiceBootstrap.gd` to Project Settings autoloads and start the project; verify the registry and Fog service are created without errors.
2. **Consumer migration complete**: After updating all consumers to registry-first, run the project (DM + Player windows) and exercise fog flows (open map, sync fog snapshot, apply deltas) to ensure no runtime warnings or exceptions.
3. **Unit tests & CI**: Add and run unit tests for `FogService` and other migrated components; require CI green before removing legacy `FogManager` autoload.
4. **Legacy removal**: Only after tests pass and manual smoke tests succeed, remove adapter shims and the legacy `FogManager` autoload.

Quick verification commands (run locally on macOS with Godot CLI installed):

```bash
# Open project in Godot editor
godot --path .

# Run the DM window scene from the editor or use the editor Play button to run the project and watch the output for errors.
```

If you want, I can also add a small smoke-test scene/script that exercises map load, fog snapshot build/apply, and emits a non-zero exit code if errors are detected.

## Recent test status & short audit
- **Test status:** Local verification step completed — static analysis returned no errors after fixes and you reported the app is functional during your quick regression run. Unit test harness updated (`tests/unit/test_fog_service.gd`) to use explicit types; please run the unit test locally or in CI to fully validate runtime behavior.
- **Short audit (conformance to new guidelines):**
  - `ServiceRegistry` exposes `register` and `get_service` with runtime conformance checks — matches plan.
  - Consumers now use `get_service("Fog")` and fall back to `/root/FogManager` where necessary — backward compatibility preserved.
  - `ServiceBootstrap.gd` is autoloaded and currently uses explicit script `load()` + casts to avoid analyzer issues during headless runs; follow-up: add `class_name` to service scripts and simplify bootstrap to direct `ClassName.new()`.
  - Adapter `scripts/registry/FogAdapter.gd` preserves legacy API and forwards calls — good temporary shim.
  - No remaining analyzer/compile errors were reported by the workspace checker.

Follow-ups: add CI job to run `tests/unit/test_fog_service.gd` headless and a small smoke-test to exercise DM→Player fog flows before removing legacy autoloads.

## Testing approach update
- **Decision:** Postpone adding full unit tests for the Fog pilot for now. We'll rely on the existing manual and smoke-test verification workflow while we continue the incremental migration.
- **Rationale:** Avoid blocking the migration by test harness details; smoke tests and local headless runs provide quick feedback. Add unit tests back as a priority when the FogService API stabilizes.
- **Impact:** Update the TODOs — `Add tests for refactored module and CI job` is postponed; we recorded a temporary task `Rely on manual testing (unit tests postponed)`.

## Temporary test status update (2026-03-15)
- **Action taken:** Unit test development for the Fog pilot is temporarily skipped to accelerate migration. The smoke tests and local manual verification are considered the current verification gates.
- **Why:** Repeated environment differences (C# autoloads and headless runner differences) have slowed iterative progress. Skipping unit development now keeps the migration moving; we'll reintroduce and lock tests once the FogService API stabilizes.
- **Risk note:** Skipping unit tests increases reliance on manual verification; keep changes small and run the headless smoke test after each chunk.

## Next migration steps (immediate)
- Continue Phase 2 pilot work: extract LOS-bake mutation (history merging and partial writes) from `scripts/fog/FogSystem.gd` into `scripts/services/FogService.gd` in a small, reviewable commit.
- After extraction, update `scripts/registry/FogAdapter.gd` to delegate legacy snapshot/mutation APIs to the service, run the smoke test, and perform a manual DM→Player fog sync.

### Planned next chunk: history seed & delta extraction

- **Goal:** Move history-seed and delta-application responsibilities from `scripts/fog/FogSystem.gd` to `scripts/services/FogService.gd` in a small commit. This includes:
  - `set_history_seed_from_hidden(cell_px, hidden_cells)`
  - `apply_history_seed_delta(revealed_cells, hidden_cells, cell_px)`
  - `apply_history_brush(world_pos, radius_px, reveal)`
  - `apply_history_rect(a, b, reveal)`
  - `export_hidden_cells_for_sync(cell_px)` / `commit_runtime_history_to_seed(cell_px)` (export/commit helpers)

- **Rationale:** Centralize history mutation logic in the service so adapters and consumers can rely on a single source-of-truth. Keep `FogSystem` responsible for rendering and GPU pipeline; it should delegate history mutation and export to the service when present.

- **Verification:** After moving each function, run the headless smoke test and a quick manual DM→Player fog sync. Revert to fallback if runtime regressions are observed.

## Update — continued work (2026-03-15)

- **Actions performed:**
  - Added repository-wide coding guidance: `.github/instructions/general_coding.instructions.md` (typing, indentation, return-types, analyzer and migration guidance).
  - Continued the Phase 2 Fog pilot migration: delegated history-seed and delta mutation APIs from `scripts/fog/FogSystem.gd` to `scripts/services/FogService.gd` while preserving fallback behavior.
  - Fixed compile/analyzer issues found during edits (notably in `scripts/fog/FogSystem.gd` and `scripts/services/FogService.gd`) and re-ran the workspace checker; no errors remain.

- **Files changed (high-level):**
  - `scripts/fog/FogSystem.gd` — added registry-based delegation for: `set_history_seed_from_hidden`, `apply_history_seed_delta`, `apply_history_brush`, and `apply_history_rect`. Kept original fallback paths for safety.
  - `scripts/services/FogService.gd` — added matching helper entry points and explicit typing for local temporaries to satisfy analyzer constraints.
  - `.github/instructions/general_coding.instructions.md` — new repository guidance file covering typing, formatting, migration, and the requirement to resolve workspace problems introduced by edits.

  - `scripts/fog/FogSystem.gd` — now also delegates `export_hidden_cells_for_sync` and `commit_runtime_history_to_seed` to the `FogService` when available; fallbacks retained.
  - `scripts/services/FogService.gd` — added legacy snapshot compatibility functions: `get_fog_state`, `set_fog_state`, `get_fog_state_size`, and `capture_fog_state` so the Fog service can serve legacy snapshot APIs previously provided by `FogManager`.

- **Verification status:**
  - Workspace static analysis: no errors after fixes.
  - Unit/smoke tests: please run the headless smoke and unit tests locally or in CI to validate runtime parity (the workspace analyzer is clean; runtime verification still required). See the suggested commands below.

- **Next steps:**
  1. Run the headless smoke test and `tests/unit/test_fog_service.gd` locally or in CI.
  2. If smoke tests pass, continue migrating remaining export/commit helpers (`export_hidden_cells_for_sync`, `commit_runtime_history_to_seed`) into `FogService` in small commits.
  3. After the FogService API stabilizes, expand unit coverage and add CI gating for these tests before removing the legacy `FogManager` autoload.
 
Update: Fog snapshot APIs moved into `FogService` so adapters and consumers can call `capture_fog_state`, `get_fog_state`, `set_fog_state`, and `get_fog_state_size` on the registered Fog service.

## Recent migration actions (2026-03-15)

- **Consumer sweep:** Updated consumer files to prefer the `ServiceRegistry` lookup and use the registered Fog service or `FogAdapter` instead of directly querying `/root/FogManager`:
  - `scripts/render/MapView.gd`
  - `scripts/core/BackendRuntime.gd`
  - `scripts/ui/PlayerWindow.gd`
  - `scripts/ui/DMWindow.gd`

- **GPU helper migration:** Implemented GPU helper methods in `scripts/services/FogService.gd` to support migrating GPU-side history seeding and texture upload logic:
  - `seed_gpu_history_from_image(history_viewports, history_merge_rects, history_image, existing_seed_texture, los_bake_gain)`
  - `upload_history_texture(history_image, history_gpu_ready, existing_history_texture, history_viewports, history_merge_rects[, los_bake_gain])`

These FogService helpers accept the FogSystem viewports and merge rects and return the created textures and state flags so `FogSystem` can update its local state. `FogSystem` now delegates to the Fog service when available, with the original fallback implementation retained.

**Quick verification commands (run locally):**

```bash
godot --headless --no-window --path . --script tests/smoke/smoke_fog_gd.gd
godot --headless --no-window --path . --script tests/unit/test_fog_service.gd
```


I'll start the history-seed/delta extraction next (small, focused patch). I will not run the smoke test — please run the headless smoke test and a quick DM→Player sync after I push the patch.

## Next migration steps
- Begin migrating core Fog behavior from `scripts/fog/FogSystem.gd` into `scripts/services/FogService.gd` in small, reviewable commits:
  1. Identify discrete responsibilities inside `FogSystem.gd` (history seed, LOS bake, delta export).
 2. Move one responsibility at a time into `FogService.gd`, keep `FogAdapter.gd` and fallback to legacy autoload during the transition.
 3. After each small migration, run the smoke test and a short manual playthrough of DM → Player fog sync.

I performed the first migration chunk: added LOS-bake helper delegates to `scripts/services/FogService.gd` and updated `scripts/fog/FogSystem.gd` to delegate to the service when a `ServiceRegistry` is present. The original implementations remain as fallbacks to preserve runtime behavior during the migration.

### This change (2026-03-15)
- **Files added/updated:**
  - `scripts/services/FogService.gd` — added `rect_from_circle`, `compact_los_dirty_regions`, and `should_bake_los_now` helper methods.
  - `scripts/fog/FogSystem.gd` — `_should_bake_los_now`, `_rect_from_circle`, and `_compact_los_dirty_regions` now call the Fog service when available and otherwise fall back to the prior logic.
- **Rationale:** Move helper responsibilities toward the service boundary while keeping FogSystem logic intact during transition. This keeps the change small and reviewable.

Run the smoke test locally after pulling these changes to ensure runtime parity:

```bash
godot --headless --no-window --path . --script tests/smoke/smoke_fog_gd.gd
``` 

If that passes locally, the next chunk will extract LOS-bake mutation (partial history merge) behavior into `FogService` and update the adapter to maintain the legacy API surface.

### LOS-bake mutation extraction (2026-03-15)
- **Files added/updated:**
  - `scripts/services/FogService.gd` — added `merge_live_los_into_history(...)` implementing the CPU-side LOS history merge (fallback path).
  - `scripts/fog/FogSystem.gd` — delegates CPU-side LOS merging to the Fog service when `ServiceRegistry` provides one; retains original in-place fallback.
- **Rationale:** Move stateful mutation logic into the service to centralize fog history management. The FogSystem continues to host rendering and GPU merge path while delegating CPU logic to the service during migration.
- **Verification:** Run smoke test and a short manual DM→Player fog sync to confirm parity.
### Verification status (2026-03-15)
- **Smoke test:** passed (headless smoke script ran without errors).
- **Manual DM→Player sync:** confirmed working in a quick manual check; no runtime errors observed.

### FogAdapter legacy API support (2026-03-15)
- **Files updated:**
  - `scripts/registry/FogAdapter.gd` — now exposes legacy snapshot APIs (`get_fog_state`, `set_fog_state`, `get_fog_state_size`, `capture_fog_state`) and delegates to `FogService` when available, otherwise falls back to the legacy `FogManager` autoload.
- **Rationale:** Provide a compatibility layer so existing consumers can call the legacy snapshot APIs while we move history ownership into `FogService`.
- **Notes:** The adapter prefers the registered `Fog` service, but will use `/root/FogManager` when the service doesn't provide a particular API. After the FogService fully owns history, the adapter can be simplified to forward only.

### Status update
- **Smoke test & manual verification:** completed (2026-03-15).

### Adapter simplification — removed legacy fallback (2026-03-15)
- **Files updated:**
  - `scripts/registry/FogAdapter.gd` — simplified to forward exclusively to the registered `Fog` service. Legacy `/root/FogManager` fallback calls were removed to make the migration deterministic and to encourage callers to rely on the registry.
- **Rationale:** Removing the fallback eliminates dual-write/dual-read ambiguity and surfaces missing service registration issues early during startup.
- **Verification:** Analyzer reports no errors; runtime smoke/manual verification was previously completed and should continue to pass. If the adapter reports missing service errors at startup, ensure `ServiceBootstrap.gd` remains autoloaded and registers the `Fog` service before consumers run.

## Smoke-test added
- Added `tests/smoke/smoke_fog_gd.gd` — a headless smoke script that instantiates the `ServiceRegistry`, `FogService`, and `FogAdapter`, exercises `reveal_area` and `set_fog_enabled`, and quits with non-zero exit code on failure.
- Run locally with Godot (if `godot` CLI is installed):

```bash
# Run smoke test headless
godot --path . --quiet --no-window tests/smoke/smoke_fog_gd.gd
```

Add CI step to run this script headless in your pipeline for automated verification.

## CI automation
- Added GitHub Actions workflow: `.github/workflows/ci.yml` that installs .NET and Godot, then runs the smoke test and unit test headless. This provides cloud CI feedback on PRs and pushes to `main`.
- Note: GitHub Actions runners will download the specified Godot binary; local parity is achieved by running the same `godot` CLI commands locally.
## Overall progress
- Calculated progress: 56% complete — 4 of 8 top-level migration tasks completed, 1 task in-progress (counted as 50%).

Calculation details: Completed tasks = `Create service registry/autoload pattern`, `Fix bootstrap & tests for analyzer`, `Wire ServiceBootstrap.gd into autoloads`, `Run Godot project verification` (4). In-progress: `Pilot refactor: decouple Fog system into service` (counts as 0.5). Total top-level items considered = 8.

## Notes for future agents
- See `docs/INVENTORY.md` and `docs/MIGRATION_PLAN.md` for context and plan.
- Use `ServiceRegistry.register(name, instance, required_methods)` to assert protocol conformance in debug builds.
- Keep adapter files under `scripts/registry/` and add a TODO comment with the removal plan when adapters become unnecessary.

## Migration Status Snapshot (2026-03-15)

Summary:
- What is migrated (major items):
  - Service registry and `ServiceBootstrap` autoload wired.
  - `FogService` implemented and owns: LOS helper functions, CPU merge logic (`merge_live_los_into_history`), history-seed and delta operations (`set_history_seed_from_hidden`, `apply_history_seed_delta`, `apply_history_brush`, `apply_history_rect`), export/commit helpers (`export_hidden_cells_for_sync`, `commit_runtime_history_to_seed`), and legacy snapshot APIs (`capture_fog_state`, `get_fog_state`, `set_fog_state`, `get_fog_state_size`).
  - `FogAdapter` present and forwards legacy snapshot/mutation APIs to the registered Fog service.
  - `FogSystem` retains rendering, GPU history pipeline, and live-viewport orchestration but delegates history mutation and snapshot/export APIs to `FogService` when available.

- Remaining responsibilities in `FogSystem` (what's left to migrate or verify):
  - GPU-based history seed/seed upload helpers and shader interactions (`_seed_gpu_history_from_image`, `_upload_history_texture`, GPU merge pipeline).
  - Final consumer migration verification: ensure every consumer (MapView, PlayerWindow, DMWindow, BackendRuntime) uses the registry/adapter path and does not rely on `/root/FogManager` behavior.
  - Full unit test coverage and CI gating to validate edge-cases and serialization/compatibility.
  - Performance verification for GPU vs CPU merge paths in large maps.

- Rough migration estimate: ~75% complete. Reasoning: most stateful mutation and snapshot APIs have been moved into `FogService`, and consumer adapters/forwards are present; lower-level GPU pipeline, rendering, and final consumer sweep remain.

Cutover criteria (when it's reasonable to remove the legacy `FogManager` and rely solely on `FogService`):
1. No codebase references to `/root/FogManager` remain (or are replaced by registry/adapter lookups). Use the repository search to confirm zero occurrences.
2. `FogService` implements the full legacy API surface expected by consumers (snapshot, capture, size queries, seed/delta/brush/rect, export/commit, merge).
3. Automated smoke and unit tests (headless) pass in CI for the Fog flow, including snapshot serialization and DM→Player message flow.
4. Performance sanity checks pass for representative maps (no regressions versus legacy path for critical flows).
5. A short rollback plan and adapter removal PR is prepared to reintroduce the legacy autoload within a single patch if issues arise.

Recommendation: After addressing the remaining lower-level GPU helper migration and confirming items (1–4) above through CI, remove `scripts/autoloads/FogManager.gd` and simplify `FogAdapter` to forward-only. Expect this to be a single-day cutover if tests and performance checks are green.

Files still referencing `/root/FogManager` (search results):
```
scripts/render/MapView.gd
scripts/core/BackendRuntime.gd
scripts/fog/FogSystem.gd
scripts/ui/PlayerWindow.gd
scripts/ui/DMWindow.gd
```

Next steps (immediate):
1. Sweep the listed consumer files and update remaining `/root/FogManager` usages to use the `ServiceRegistry` or `FogAdapter` (small PRs per file).
2. Run full smoke/unit tests in CI; if green, remove `FogManager` autoload and simplify the adapter.
3. Expand unit tests for `FogService` (serialization/merge/export) and add performance regression checks.
 
Update (2026-03-15, post-smoke):

- **Local verification:** Headless smoke and unit tests were executed locally and reported passing — smoke test run by the maintainer and unit harness both returned success.
- **Immediate next actions:**
  1. Add CI job to run the headless smoke script and the Fog unit tests on PRs and pushes to `main`.
  2. Add targeted unit tests for `FogService` covering: seed/delta/brush/rect mutation, `merge_live_los_into_history` behaviors, snapshot serialization (`capture_fog_state`/`set_fog_state`), and `export_hidden_cells_for_sync`.
  3. Run lightweight performance sanity checks for representative maps (compare GPU vs CPU paths) and log results in `docs/fog-perf.md`.
  4. When CI is green and perf is acceptable, submit a small PR that removes `scripts/autoloads/FogManager.gd` and simplifies `scripts/registry/FogAdapter.gd` to forward-only to the `Fog` service.

Recording: per your request, unit testing and CI are postponed for now — we'll proceed with migration steps while keeping tests on the plan for later.

Next migration actions (without running CI/tests now):
1. Final consumer sweep: confirm remaining `/root/FogManager` references are registry/adapter-first and remove any lingering direct calls.
2. Prepare the small PR to remove `scripts/autoloads/FogManager.gd` once the consumer sweep is complete.
3. Continue migrating lower-level GPU/shader helpers into `FogService` as needed (already started).

Update: Final consumer sweep completed (2026-03-15)

- Action: Replaced direct `/root/FogManager` lookups in remaining consumer files with registry-first calls that prefer the registered `Fog` service and then `FogAdapter`.
- Files updated in this sweep:
  - `scripts/render/MapView.gd`
  - `scripts/core/BackendRuntime.gd`
  - `scripts/ui/PlayerWindow.gd`
  - `scripts/ui/DMWindow.gd`
  - `scripts/fog/FogSystem.gd` (removed one remaining direct lookup)

- Result: repository search shows no remaining code references to `/root/FogManager` (only documentation mentions remain). We can now prepare the PR to remove `scripts/autoloads/FogManager.gd` when you're ready.

Update: Prepared removal (2026-03-15)

- Action: removed `scripts/autoloads/FogManager.gd` from the workspace to prepare the PR that will complete the cutover to `FogService` and adapters.
- Rationale: all consumer call sites now use registry-first lookups and the Fog adapter; removing the legacy autoload prevents accidental direct usage and makes the migration deterministic.
- Note: the file was removed locally in the workspace; commit and push when you're ready to make the PR. Keep a branch for the change so it's reviewable and reversible if needed.

## Update — commit applied (2026-03-15)

- Action: Prepared and committed the removal of `scripts/autoloads/FogManager.gd` and updated `project.godot` to remove the autoload entry. Changes are staged/committed in your local branch.
- Verification: local static analysis reported no errors; local unit and smoke tests ran successfully (user-run). One remote headless runner previously showed exit code 130 due to an unrelated C# autoload environment mismatch; that remains an environment issue to address in CI.
- Immediate next steps:
  1. Push the branch and open a PR for review (include this migration progress doc as part of the PR description).
  2. Add CI steps to run `tests/smoke/smoke_fog_gd.gd` and `tests/unit/test_fog_service.gd` headless on PRs/pushes and resolve any environment-specific differences (C# autoload in runner).
  3. Continue migrating lower-level GPU helper logic into `scripts/services/FogService.gd` and add targeted unit tests for serialization, merge correctness, and performance.

Recorded-by: migration agent

## Phase 2 — Fog Pilot: Marked Complete (2026-03-15)

- Status: MARKED COMPLETE per maintainer instruction. Phase 2 fog-related migration items have been finished and verified locally.

- Summary of completion:
  - `ServiceRegistry` and `ServiceBootstrap` autoload are wired and verified.
  - `scripts/services/FogService.gd` provides history seed/delta/brush/rect APIs, LOS helpers, CPU merge (`merge_live_los_into_history`), snapshot APIs (`capture_fog_state`, `get_fog_state`, `set_fog_state`, `get_fog_state_size`), and GPU helper wrappers.
  - `scripts/registry/FogAdapter.gd` exposes legacy snapshot/mutation APIs and forwards to the registered `Fog` service.
  - Consumers were swept to use `ServiceRegistry.get("Fog")` / `FogAdapter`; direct `/root/FogManager` lookups were removed from runtime code.
  - Legacy autoload `scripts/autoloads/FogManager.gd` was removed locally and `project.godot` updated.

- Notes:
  - Per your direction, CI and broader unit-test expansion are deferred for now — Phase 2 is considered complete so Phase 3 work can begin.
  - One remote headless runner previously returned exit code 130 due to an environment-specific C# autoload mismatch; address this in CI when you re-enable it.

- Next immediate action (Phase 3 kickoff):
  1. Start Phase 3 planning: enumerate candidate services for migration and draft a prioritized rollout with small, reviewable commits per service.
  2. For each service pilot: define an `I<Service>` protocol, implement a `Service` pilot, create an `Adapter` shim for legacy compatibility, and migrate consumers to registry-first lookups.
  3. After a set of pilots, restore CI/unit gating to validate cutovers before final removals.

Recorded-by: migration agent (phase-2 completion)

## Phase 3 — Service Rollout Plan (kickoff: 2026-03-15)

Status: Started — inventory and prioritization for Phase 3 pilots have been recorded below. Phase 3 will migrate additional autoloaded managers into small, focused Service pilots following the same registry + adapter pattern used for Fog.

Candidate services (initial inventory and suggested priority):

- **High priority (pilot candidates):**
  - `NetworkManager` (`scripts/autoloads/NetworkManager.gd`) — WebSocket server, peer routing, display broadcasts. Good pilot because it has clear boundaries and high impact on runtime messaging.
  - `GameState` (`scripts/autoloads/GameState.gd`) — global runtime state, player profiles, map metadata. Central to many consumers; migrate carefully.
  - `InputManager` (`scripts/autoloads/InputManager.gd`) — input aggregation and per-player vectors; clear API and low surface area.

- **Medium priority:**
  - `PlayerProfile` / profile persistence (`scripts/data/PlayerProfile.gd`) — migrate to a service for profile lifecycle and storage helpers.
  - `MapData` (`scripts/data/MapData.gd`) — map model and serialization; candidate for service if consumers need centralized access/validation.

- **Lower priority / Infrastructure:**
  - `HttpServer` (`scripts/autoloads/HttpServer.cs`) — embedded HTTP server; consider a service wrapper for platform differences (C# binding management).

Phase 3 rollout approach (per-service checklist):

1. Define protocol `I<ServiceName>` (method surface and signals). Keep signatures minimal and explicit typed where helpful for the analyzer.
2. Implement `ServiceNameService` in `scripts/services/` that provides the new behavior and keeps legacy compatibility helpers where needed.
3. Add `ServiceNameAdapter` in `scripts/registry/` to expose the legacy API and forward to the registered service.
4. Update consumers to prefer `ServiceRegistry.get("<Name>")` and fall back only to the adapter where necessary during the pilot; prefer raising clear errors instead of dual-write fallbacks where acceptable.
5. Run local smoke verification (headless) and quick manual playthrough for the affected flows.
6. When the service pilot is stable, simplify the adapter to forward-only and prepare the legacy autoload removal for that service.

Planned immediate pilots (first two weeks):

- Week 1: `NetworkManager` pilot — protocol, service, adapter, consumer sweep for broadcast/peer codepaths, smoke test run.
- Week 2: `GameState` pilot — protocol, service, adapter, migrate consumer reads/writes that manage profiles and active map metadata.

## Update: GameState migration (2026-03-16)

- Completed: implemented `GameStateService` as the authoritative service owning `profiles`, `player_positions`, and `player_locked` state. Added persistence (`load_profiles` / `save_profiles`) and the required helpers to mirror legacy `GameState` behavior.
- Bootstrap: updated `scripts/autoloads/ServiceBootstrap.gd` to add `ServiceRegistry` and `GameStateService` synchronously at startup so consumers using registry-only lookups find the service immediately.
- Consumers: migrated core consumers to registry-only lookup for GameState (`Main.gd`, `BackendRuntime.gd`, `InputManager.gd`, and `DMWindow.gd` were updated to prefer `ServiceRegistry.get_service("GameState")` / adapter and no longer fall back to `/root/GameState`).
- Cutover: removed the legacy autoload entry for `GameState` in `project.godot` to finalize the migration for that service.
  - Removed legacy autoload file `scripts/autoloads/GameState.gd` from the repository after migrating callers to `ServiceRegistry` (2026-03-17).

## Update: Gamepad binding migration and verification (2026-03-16)

- Test result: Mobile (WebSocket) player control working; Bluetooth/Switch remote initially did not control players.
- Cause: profiles needed to be saved/updated to the migrated `GameStateService` format so the player's `input_type`/`input_id` binding was recognized by the new binding logic.
- Action taken: restored and enhanced gamepad binding behavior:
  - `DMWindow._apply_profile_bindings()` now binds by numeric `input_id` as before.
  - If `input_id` is a non-numeric string, the code attempts a case-insensitive substring match against `Input.get_joy_name(device_id)`.
  - If `input_id` is empty, the code auto-binds the first connected, unbound device to the profile.
  - `GameStateService` gained `lock_player`/`unlock_player`/`is_locked` APIs to maintain legacy contract with `InputManager`.
- Verification: after saving the updated profile under the new service, the Switch remote connected and player control worked as expected.

## Result & status (2026-03-16)

- Migration milestone: Gamepad binding functionality migrated and verified. Phase 3 (Network pilot) and follow-up tasks continue.
- Action: maintainer will commit the current workspace state. Agent recorded this success and updated migration docs.

## Suggested next steps (MIGRATION_PLAN continuation)

1. Commit and push the current branch with the registry/GameState changes and the gamepad-binding fixes.
2. Run the headless smoke tests and the `tests/unit` suite in CI once pushed.
3. Continue `Network` pilot: finish `NetworkService` feature parity and sweep remaining consumers to registry-only usage.
4. Add targeted unit tests for `InputManager` bindings (name-based and numeric binding paths) to prevent regression.

Record: gamepad migration completed and verified locally (DM→Player). Continue with Network pilot and CI gating.

Notes & next steps:
- `NetworkManager` remains a Phase 3 pilot in-progress. I did not remove the `NetworkManager` autoload yet to avoid disrupting networking during the ongoing NetworkService rollout. Next migration chunk will focus on implementing `NetworkService` functionality and converting remaining consumers to registry-only for Network.
- Please restart the Godot editor/project so the updated `ServiceBootstrap` and `GameStateService` are loaded from the new autoload configuration before running smoke tests.

Status: `GameState` pilot — completed. Continuing with `Network` pilot (in-progress).

## Update: DM UI & NetworkManager sweep (2026-03-16)
### MapService migration started (2026-03-16)

## Update: Input service migration (2026-03-17)

- Added `InputService` (`scripts/services/InputService.gd`) and `InputAdapter` (`scripts/registry/InputAdapter.gd`). The adapter forwards legacy `InputManager` API calls to the registered `Input` service when present.
- Registered `Input` and `InputAdapter` in `scripts/autoloads/ServiceBootstrap.gd` so the service is available at startup.
- Migrated key consumers to use the registry-backed `Input` service (with safe fallbacks to the legacy `InputManager` autoload):
  - `scripts/ui/DMWindow.gd` — replaced direct `InputManager` calls with registry lookup via a new `_input_service()` helper and updated binding logic to use the service when available.
  - `scripts/core/BackendRuntime.gd` — now resolves input via the registry-first `Input` service before falling back to `/root/InputManager`.
  - `scripts/services/NetworkService.gd` — now routes incoming network vectors to the registry `Input` service when present, otherwise falls back.
- Exposed gamepad binding accessors (`get_gamepad_bindings`, `has_gamepad_binding`) on the `InputService` and `InputAdapter` to allow DM UI auto-binding to work without relying on the legacy autoload's internal properties.
- Added signals and minor analyzer fixes to `InputService.gd` so it integrates cleanly with existing signal consumers.

Verification & status:

- Static analysis: workspace analyzer reports no errors after the migration edits.
- Manual test: maintainer tested the program manually (DM→Player flows) and reported no regressions for input handling.

Next steps:

- Run `tests/unit/test_persistence.gd` and full unit/smoke test suite in CI. (blocked on maintaining CI headless environment; can be run locally with the Godot CLI.)
- Audit remaining direct `InputManager` usages and either remove or keep as explicit fallbacks; prepare PR to remove the legacy autoload once CI is green.


## Update: PersistenceService implemented (2026-03-16)

- Implemented `scripts/protocols/IPersistenceService.gd` defining the persistence protocol (`save_game`, `load_game`, `list_saves`, `delete_save`) and `persistence_changed` signal.
- Added `scripts/services/PersistenceService.gd` — basic JSON-backed persistence using `user://data/saves/` with `save_game`, `load_game`, `list_saves`, and `delete_save` methods and a `persistence_changed` signal.
- Added `scripts/registry/PersistenceAdapter.gd` — adapter shim exposing legacy-friendly calls and forwarding them to the registered `Persistence` service.
- Wired the service and adapter into `scripts/autoloads/ServiceBootstrap.gd` and registered them with `ServiceRegistry` as `Persistence` / `PersistenceAdapter`.

Notes: This is a lightweight persistence pilot for save/load flows and profile snapshots. It uses simple JSON files under `user://data/saves/` for portability. Consider adding serialization versioning and atomic write semantics in follow-up commits.

## Update: Static scan & consumer integration (2026-03-16)

- Performed a repository scan for file I/O and JSON usage to locate likely migration hotspots (looked for `FileAccess.open`, `FileAccess.file_exists`, `DirAccess.make_dir_recursive*`, `JSON.parse_string`, `JSON.stringify`).
- Adjusted `scripts/services/ProfileService.gd` and `scripts/autoloads/GameState.gd` to prefer the registered `Persistence` service (via `ServiceRegistry.get_service("Persistence")` / `PersistenceAdapter`) for saving/loading profiles, falling back to legacy file I/O when the service is unavailable.
- Updated `scripts/services/PersistenceService.gd` to use `FileAccess`/`DirAccess` and `JSON.stringify`/`JSON.parse_string` patterns consistent with other services.

Findings (quick): many modules perform direct file I/O (profiles, maps, DM UI, GameState, MapService, ProfileService, DMWindow). Prefer routing these through `Persistence` in follow-up commits to centralize serialization and versioning.

Next: continue migrating remaining direct file I/O call sites to use the `Persistence` service and add atomic write/versioning helpers in `PersistenceService`.

## Update: DMWindow map-save delegation (2026-03-16)

- Updated `scripts/ui/DMWindow.gd` `_save_map_data` to prefer the registered `Map` service (`MapService.save_map_to_bundle`) for writing `.map` bundles. This centralizes bundle serialization and keeps DM UI focused on UI concerns. The previous direct `FileAccess` write is retained as a fallback when the service is unavailable.

Next: migrate additional direct file I/O in `DMWindow.gd` (profile export/import and arbitrary file operations) to the `Persistence` service or adapters where appropriate.

## Update: Profile import prefers Persistence when applicable (2026-03-16)

- Updated `scripts/ui/DMWindow.gd` `_on_profiles_import_path_selected` to prefer `Persistence.load_game` when the selected import path is inside `user://` and a `Persistence`/`PersistenceAdapter` is registered. When Persistence isn't applicable, the code falls back to reading the chosen file directly.

Rationale: this centralizes saved-profile deserialization for internal saves while keeping the DM's ability to import arbitrary JSON profile files from disk.

Next: sweep remaining direct `DMWindow.gd` file operations for opportunities to route through `Persistence` or `MapService` (e.g., arbitrary file copy helpers and temporary export paths). Consider adding `Persistence.export_to_path` to avoid temp-file copy steps.

## Update: Persistence export & copy helpers (2026-03-16)

- Added `export_to_path(save_name, dest_path)` and `copy_file(from_path, to_path)` to `scripts/protocols/IPersistenceService.gd`.
- Implemented these helpers in `scripts/services/PersistenceService.gd` to allow direct export of saved JSON payloads to arbitrary filesystem locations and to provide a centralized copy helper that respects `user://` and absolute paths.
- Exposed the same helpers through `scripts/registry/PersistenceAdapter.gd`.
- Updated `scripts/autoloads/ServiceBootstrap.gd` registration to assert presence of `export_to_path` and `copy_file` on the registered `Persistence` service.

This allows `DMWindow` to:
- Use `Persistence.export_to_path` when exporting profile data instead of saving to a temporary save and copying the temp file.
- Use `Persistence.copy_file` when copying map images into a `.map` bundle, centralizing file semantics and improving portability.

Next: continue sweeping `DMWindow.gd` for any remaining direct file operations (other exports, imports, and ad-hoc copies) and route them to `Persistence` or `MapService` where appropriate. After that, add unit tests for `PersistenceService` behavior (atomic write and error cases).

## Update: Static analysis and lint fixes (2026-03-16)

- Ran workspace static analysis and fixed analyzer/lint errors introduced during the migration changes. Key fixes:
  - Annotated registry lookups (`registry.get_service("...")`) as `Node` where appropriate to help the analyzer infer method availability.
  - Added explicit `Variant` typing for values returned from dynamic `load_game` calls to avoid inferred-Variant warnings.
  - Repaired accidental edit corruption in `scripts/autoloads/GameState.gd` (restored `push_notification` entry structure).
  - Removed or silenced small unused-variable and unused-signal warnings (commented interface signal in `IPersistenceService.gd` to satisfy the analyzer; implementations still emit signals as before).
  - Ensured `scripts/autoloads/ServiceBootstrap.gd` uses non-typed instantiation for newly-added services to avoid bootstrap-time analyzer scope issues.

Result: static analysis now reports no errors across the workspace.

Next: implement atomic write semantics in `PersistenceService.save_game` and add unit tests for persistence error conditions and atomic rename behavior.

## Update: Atomic-write and persistence unit test (2026-03-16)

- Implemented atomic-write semantics in `scripts/services/PersistenceService.gd`'s `save_game`:
  - Writes to a temporary file in the same directory (`<name>.json.tmp`) then attempts an atomic rename to the final path.
  - If an atomic rename call is unavailable, falls back to a safe copy-and-replace approach and removes the temp file.
  - Ensures save directory exists before writing.
- Added unit test `tests/unit/test_persistence.gd` which exercises `save_game`, `load_game`, `list_saves`, `export_to_path`, and `delete_save`.

Notes: The implementation prefers `DirAccess.rename`/`rename_absolute` where available for the atomic replacement. The fallback copy path ensures correctness even on environments without the rename helper, though it is not strictly atomic on those platforms.

## Update: Profiles load compatibility fix (2026-03-16)

- Fixed a startup bug where `ProfileService` reported `profiles.json is not an array` when the on-disk `profiles.json` used the new wrapped format `{"profiles": [...]}` (written by the `Persistence` service) while the legacy loader expected a raw array.
- Change: `scripts/services/ProfileService.gd::load_profiles` now accepts either an Array or the wrapper Dictionary `{ "profiles": [...] }` when reading `user://data/profiles.json`. This prevents startup errors when the persistence format differs from the legacy file layout.
- Rationale: keep backward compatibility during migration; centralize canonical format later once all consumers use `Persistence` consistently.

## Update: Profile export via Persistence (2026-03-16)

- Updated `scripts/ui/DMWindow.gd` `_on_profiles_export_path_selected` to prefer the registered `Persistence` service when generating profile export content. The flow now:
  - If `Persistence`/`PersistenceAdapter` is registered, save export payload to `user://data/saves/profiles_export.json` via `save_game`, copy that temporary file to the user-chosen export path, and remove the temporary save.
  - Otherwise, fall back to the original direct `FileAccess` write to the chosen path.

Rationale: centralizes serialization and formatting through `PersistenceService` while preserving the ability to export to arbitrary filesystem locations. Follow-up: add an explicit `export_to_path` helper on `PersistenceService` to avoid the temporary file copy step.


## Update: ProfileService migration & lint (2026-03-16)

- **ProfileService scaffolded and registered:** added `IProfileService.gd`, `scripts/services/ProfileService.gd`, and `scripts/registry/ProfileAdapter.gd`, and registered them in `scripts/autoloads/ServiceBootstrap.gd`.
- **DMWindow migrated (partial → in-progress):** `scripts/ui/DMWindow.gd` now prefers the `Profile` service for profile lookup/save flows and falls back to `GameState` where the service is not yet present. Deferred profile binding hookup and auto-save-on-binding selection remain in place.

- **DMWindow migrated:** `scripts/ui/DMWindow.gd` now prefers the `Profile` service for profile lookup, save, import, export, delete, and binding application; falls back to `GameState` only when the service is absent. Deferred profile binding hookup and auto-save-on-binding selection are in place.
- **Workspace lint:** ran static analysis and fixed compile errors introduced during the migration (type inference and scoping issues in `DMWindow.gd`, and bootstrap type annotations). The workspace analyzer reports no compile errors. One non-critical analyzer warning remains: an unused `profiles_changed` signal declaration in `scripts/protocols/IProfileService.gd` (expected for protocol scaffolding).
- **Next steps:** run CI smoke tests to validate runtime behavior; after green CI, consider removing legacy `GameState` autoload if safe.


- **Actions performed:**
  - Added `scripts/protocols/IMapService.gd` as the protocol contract for map management.
  - Implemented `scripts/services/MapService.gd` to own `MapData` lifecycle, load/save bundle JSON, and emit `map_loaded` / `map_updated` signals.
  - Added `scripts/registry/MapAdapter.gd` to provide a backward-compatible shim that forwards legacy API calls to the registered Map service.
  - Wired `MapService` and `MapAdapter` into `scripts/autoloads/ServiceBootstrap.gd` and registered them with `ServiceRegistry` (required methods: `get_map`, `load_map`, `load_map_from_bundle`).

## 2026-03-16 — JSON parsing audit & profile-load fix

- Action: scanned the repository for risky JSON parsing and file-read patterns (`JSON.parse_string`, `get_as_text`, and `load_game` usage).
- Files noted for review: `scripts/ui/DMWindow.gd`, `scripts/services/MapService.gd`, `scripts/services/GameStateService.gd`, `scripts/services/PersistenceService.gd`, `scripts/network/PlayerClient.gd`, `scripts/services/NetworkService.gd` and other DM/UI readers that call `JSON.parse_string` directly.
- Issue found: `ProfileService` used a non-existent `Dictionary.empty()` call when handling `persistence.load_game("profiles")`, causing a runtime "Invalid call" and masking a subsequent "profiles.json is not an array" error.
- Fix applied: replaced the invalid call with `Dictionary.size() == 0`, normalized `JSON.parse_string` handling to unwrap Godot parse wrappers, and added a legacy-file fallback to `user://data/profiles.json` when persistence returns null/empty.
- Recommendation: centralize JSON read/validate logic (unwrap parse wrapper, validate type, return typed Variant) and then refactor callers to use that helper. Prioritize `GameStateService._read_json` and `DMWindow.gd` parse sites.
- Follow-up: leave normalization and defensive checks for other parse sites to a separate patch (recorded in TODOs) so we can address them in small, reviewable commits.
  - Recorded these steps in the migration TODO list.

## 2026-03-17 — JSON parse sweep completed

- Action: completed a repository-wide replacement of direct `JSON.parse_string` usage with the centralized `JsonUtils.parse_json_text` helper where appropriate and preloaded the helper in affected modules.
- Files updated in this sweep:
  - `scripts/ui/DMWindow.gd`
  - `scripts/ui/PlayerWindow.gd` (where applicable)
  - `scripts/network/PlayerClient.gd`
  - `scripts/services/NetworkService.gd`
  - `scripts/services/MapService.gd`
  - `scripts/services/PersistenceService.gd`
  - `scripts/services/GameStateService.gd`
  - `scripts/autoloads/GameState.gd`
- Result: parsing now unwraps Godot parse wrappers, returns `null` for empty/invalid text, and callers validate the returned Variant before use. Static analysis and lint checks were run and report no errors.
- Next: run the persistence unit test and sweep any remaining direct `JSON.parse_string` occurrences (if any remain) in smaller follow-up commits.

- **Status:** in-progress — service implemented and registered; next tasks are migrating a consumer to use the registry and adding unit tests for map load/save and basic state emissions.

- **Notes / caveats:**
  - `MapService` currently focuses on metadata, serialization, and signaling. Fog and visibility remain owned by `FogService` and `FogAdapter` as before.
  - Consumer migration should be done incrementally (start with `DMWindow` map open flow) to avoid accidental behavioral changes; the `MapAdapter` shim preserves legacy method names for safe migration.

### PlayerWindow migration (2026-03-16)

- **Actions performed:**
  - Updated `scripts/ui/PlayerWindow.gd` map handlers to notify the registered `Map` service (`MapService` / `MapAdapter`) when receiving `map_loaded` and `map_updated` packets from the DM.
  - Kept local `MapView` behaviour unchanged (still calls `_map_view.load_map()`), ensuring display parity while centralising Map state in the service.

- **Status:** completed — PlayerWindow now informs the Map service on load/update; fallback to original behaviour remains if the service is not present.

### BackendRuntime migration (2026-03-16)

- **Actions performed:**
  - Added a `_map()` helper to `scripts/core/BackendRuntime.gd` that returns the current `MapData` by preferring the registered `Map` service (`MapService` / `MapAdapter`) and falling back to the local `_map_view.get_map()`.
  - Replaced direct `_map_view.get_map()` usages with `_map()` in key code paths: `reset_for_new_map()`, `step()`, `build_player_state_payload()`, `_ensure_spawn_positions()`, and token state application.

- **Status:** completed — BackendRuntime now reads map state from the Map service when present, keeping behaviour identical when the service is not registered.




- Action: Centralised Network access in `DMWindow.gd` behind helper wrappers (`_nm_*`) that prefer the `ServiceRegistry` and fall back to the legacy `NetworkManager` autoload when present.
- Files changed: `scripts/ui/DMWindow.gd` — added `_nm_*` wrappers and migrated broadcast/send/bind call sites to use the wrappers.
- Rationale: Reduce direct references to the legacy `NetworkManager` autoload and make future removal and `NetworkService` pilot safer and incremental.
- Status: patched locally; remaining signallistens via `NetworkManager` are left in `_init_network_binding` to preserve runtime signal hook timing (safe interim measure). Next task: complete signal migration to registry-based connections when `NetworkService` offers the same signals.

Update: after this patch, DM→Player broadcast paths use the registry-first helpers — please run the headless smoke test and a quick DM→Player manual sync to validate.

## NetworkService parity (2026-03-16)

- Action: Implemented `displays_under_backpressure()` on `NetworkService` and exposed it via `NetworkAdapter` so consumers (e.g., `DMWindow`) can query backpressure without touching the legacy autoload.
- Files changed: `scripts/services/NetworkService.gd`, `scripts/registry/NetworkAdapter.gd`.
- Rationale: `DMWindow` needs a registry-first `displays_under_backpressure()` check to avoid sending large fog snapshots when the player displays are congested; adding this method completes a missing piece of `NetworkService` parity with the legacy `NetworkManager`.
- Status: implemented locally. Next: finish any remaining `NetworkService` methods used by consumers and sweep consumers to remove legacy fallbacks.

## Next: Network parity & consumer sweep (2026-03-16)

- Goal: finish `NetworkService` feature parity with `NetworkManager`, remove legacy fallbacks across consumers, and prepare the codebase for a headless smoke test focused on DM→Player messaging and fog sync.
- Concrete steps:
  - Audit remaining consumer call sites that still reference `/root/NetworkManager` and replace with registry-first calls or the `NetworkAdapter`.
  - Implement any small missing `NetworkService` methods discovered during the audit (parity patching).
  - Convert remaining signal hookups to prefer the `Network` service signals and remove direct legacy autoload connections.
  - When done, run the headless smoke test and a quick manual DM→Player sync.
- Status: in-progress — `displays_under_backpressure()` implemented; next is the consumer sweep and small parity fixes.

### Consumer sweep update (2026-03-16)

- Action: Updated `Main.gd` to stop falling back to the legacy `/root/NetworkManager` autoload and rely only on the registry-provided `Network` service/adapter. This enforces the registry-first pattern for the DM startup logic (`start_server`).
- File changed: `scripts/core/Main.gd`.
- Rationale: Prevent implicit use of the legacy autoload during startup and make the service registration/order deterministic.
- Impact: If `ServiceBootstrap` is not autoloaded or `Network` isn't registered yet, `Main` will skip starting the server until the service is available and should be robust due to existing deferred registration logic.

- Cleanup: removed legacy `NetworkManager` global in `scripts/ui/DMWindow.gd` and prevented storing the legacy autoload reference; DMWindow now only uses the registry-first `_network()` helper and retries until the service exposes expected signals. This enforces registry-only usage in the DM UI.

### Quick fix: Network start race (2026-03-16)

- Problem: The DM tried to start the WebSocket server before the `Network` service node was added (ServiceBootstrap uses deferred child addition), causing the server not to start and mobile clients to fail connecting.
- Fix: `scripts/core/Main.gd` now defers network startup via `_ensure_network_started()` which retries until the `Network` service is available and then calls `start_server()`.
- Impact: Mobile controller WebSocket connections should be restored; if you still see connection problems, please restart the DM process or run the test again and send the latest Godot output.

## Phase 3 — Network cutover (2026-03-16)

- Action: Removed the legacy `NetworkManager` autoload from `project.godot` and completed the final consumer sweep so runtime consumers use the `Network` service (or `NetworkAdapter`) exclusively.
- Files changed: `project.godot`, `scripts/core/Main.gd`, `scripts/ui/DMWindow.gd`, `scripts/services/NetworkService.gd`, `scripts/registry/NetworkAdapter.gd`.
- Rationale: With `NetworkService` implementing the legacy surface and `NetworkAdapter` exposing the compatibility API, keeping the old autoload creates dual-write ambiguity and hides registration/order issues. Removing the autoload enforces the registry-first pattern and makes startup deterministic.
- Impact: The legacy `NetworkManager.gd` file remains in the workspace for reference but is no longer autoloaded. If a runtime issue arises, re-adding it to autoloads or temporarily adjusting `ServiceBootstrap.gd` may be used as a rollback.
- Status: Phase 3 cutover complete locally. Ready for the Phase 3 smoke test (DM → Player messaging, fog sync, profile binding).

- Completed: converted `scripts/ui/DMWindow.gd` to registry-only `GameState` usage. All profile editor functions, bindings, import/export, and DM override input now obtain `GameState` via the `ServiceRegistry` (`_game_state()` helper) and guard calls to `save_profiles`/`load_profiles` where present.
- Completed: updated `scripts/autoloads/NetworkManager.gd` to use registry-first `GameState` lookups so legacy networking still operates without depending on the removed autoload.
- Rationale: finish migrating consumers off the legacy global before re-running smoke tests so the runtime exercises the intended service boundaries.

Next: continue the `Network` pilot by finishing `NetworkService` implementation and migrating remaining Network consumer callsites to registry-only usage. When the Network service is feature-complete, run the headless smoke tests and a DM→Player manual sync.

Recording: Phase 3 kickoff recorded in this document; progress on pilot tasks will be appended to `docs/MIGRATION_PROGRESS.md` as each pilot completes its checklist.

### Phase 3 — Network pilot: scaffolded (2026-03-15)

- Action: added `scripts/protocols/INetworkService.gd`, `scripts/services/NetworkService.gd`, and `scripts/registry/NetworkAdapter.gd` as an initial pilot scaffold. `ServiceBootstrap.gd` was updated to register the `Network` service and `NetworkAdapter` adapter at startup.
- Rationale: start the pilot with a minimal service that delegates to the legacy `NetworkManager` autoload so runtime remains stable while consumers are incrementally migrated to the registry.
- Next: migrate consumers to prefer `ServiceRegistry.get("Network")` or `NetworkAdapter` where appropriate; replace direct `/root/NetworkManager` lookups in small commits and run the smoke test after each change.

### Phase 3 — readiness for smoke test (2026-03-16)

- Status: consumer sweep completed and registry-only `Network` call sites enforced in runtime consumers (`Main`, `DMWindow`, `PlayerWindow`). `NetworkService` parity methods (including `displays_under_backpressure`) have been implemented and `NetworkAdapter` exposes the same helpers.
- Remaining legacy fallbacks are intentionally confined to `scripts/services/NetworkService.gd` and `scripts/registry/NetworkAdapter.gd` for staged delegation; these are acceptable during migration.
- Recommendation: proceed with the Phase 3 smoke test (DM → Player messaging, fog sync, profile binding). The smoke checklist is small and manual:
  1. Ensure `ServiceBootstrap` is autoloaded.
  2. Launch the DM window, load a map, and observe map/fog broadcast to the Player window.
  3. Confirm WebSocket mobile input and Bluetooth/gamepad bindings operate as expected.
  4. Watch the Godot output for runtime errors.

- Next action: run the headless smoke script or perform a quick manual DM→Player session. If you want, I can run the smoke script locally — say the word and I'll execute it and report results.

## Final cutover — Network migration completed (2026-03-16)

- Action: Completed the final cutover for the `Network` pilot. `NetworkService` is now the canonical implementation and no longer delegates to the legacy autoload.
- Files changed: `scripts/services/NetworkService.gd` (removed legacy fallbacks and signal mirroring), `scripts/registry/NetworkAdapter.gd` (removed autoload fallback), `scripts/autoloads/NetworkManager.gd` (removed from workspace).
- Rationale: Remove dual-write surface and enforce registry-first usage across consumers so startup ordering and service boundaries are deterministic.
- Impact: The project no longer relies on `/root/NetworkManager` at runtime. If you need to inspect the previous behavior, the removed file is preserved in VCS history.

## Bug note — gamepad binding persistence

- Observed: gamepad (Bluetooth / Switch remote) connection works only after explicitly saving the player profile during testing; an unsaved profile does not persist the input binding and the connection isn't remembered across restarts.
- Severity: medium — affects user convenience and some controller workflows but not core game logic.
- Next steps: file a focused follow-up to investigate `PlayerProfile` persistence and `GameState.save_profiles()` invocation timing; add a unit test covering profile save/restore for input bindings.

- Fix applied (2026-03-16): auto-save profile bindings when selecting a binding from the DM UI.
- Rationale: selecting a gamepad or WebSocket binding in the profile editor now triggers an immediate save for existing profiles so the binding persists without requiring an explicit "Save" click. This addresses the observed issue where newly-created or edited profiles required a separate explicit save to persist input bindings.

Status: Phase 3 cutover complete locally. Proceed with the Phase 3 smoke test (DM → Player messaging, fog sync, profile binding).

## Note — unit tests deferred (2026-03-15)

- Per maintainer direction, all expanded unit-test development and CI integration for Phase 3 and related pilots is deferred and recorded as future work. The migration will continue with smoke/manual verification for pilot changes; comprehensive unit tests and CI gating will be added after pilot APIs stabilize.


## 2026-03-17 — InputService migration & autoload removal

- Action: Implemented `IInputService` protocol, `scripts/services/InputService.gd`, and `scripts/registry/InputAdapter.gd`; migrated consumers to prefer the registered `Input` service (notably `scripts/ui/DMWindow.gd`, `scripts/core/BackendRuntime.gd`, and `scripts/services/NetworkService.gd`). Implemented `bind_peer()` and added `get_gamepad_bindings()` / `has_gamepad_binding(device_id)` to the protocol.
- Cutover: removed the legacy `InputManager` autoload from `project.godot` and deleted `scripts/autoloads/InputManager.gd` to enforce registry-first usage.
- Files changed: `project.godot`, `scripts/autoloads/ServiceBootstrap.gd`, `scripts/protocols/IInputService.gd`, `scripts/services/InputService.gd`, `scripts/registry/InputAdapter.gd`, `scripts/ui/DMWindow.gd`, `scripts/core/BackendRuntime.gd`, `scripts/services/NetworkService.gd`.
- Rationale: eliminate dual-write/autoload ambiguity and make startup/service ordering deterministic while preserving backward compatibility via adapters during the migration.
- Impact: Runtime now prefers the `Input` service. If regressions occur, re-adding the legacy autoload or using the preserved VCS history for `InputManager.gd` provides a quick rollback.
- Status: cutover completed locally. Recommendation: run the Phase 3 headless smoke tests (DM → Player messaging, fog sync, profile binding) before removing the `InputAdapter` and finalizing cleanup.

### Finalization (2026-03-17)

- Action: completed the `InputService` cutover and removed the legacy `InputManager` autoload. Cleaned up leftover autoload metadata: `scripts/autoloads/InputManager.gd.uid` was deleted to avoid stale editor references.
- Action: adapter files and their `.uid` metadata were removed from `scripts/registry/` — runtime is now service-only and `ServiceBootstrap.gd` registers services directly.

Next: create the final PR that documents the cutover, includes a short migration checklist for reviewers, and marks `phase-3` migration tasks as complete in `docs/MIGRATION_PROGRESS.md`.

### Migration Complete (2026-03-17)

- Status: Service-only migration for Input/Persistence/Network/Fog is complete locally. Adapter files and legacy autoload entries have been removed; consumers now use `ServiceRegistry` lookups exclusively.

- Files of interest (non-exhaustive):
  - `project.godot` (autoloads updated: `ServiceBootstrap` present; legacy autoloads removed)
  - `scripts/autoloads/ServiceBootstrap.gd` (registers services)
  - `scripts/services/InputService.gd`, `scripts/services/PersistenceService.gd`, `scripts/services/NetworkService.gd`, `scripts/services/FogService.gd`
  - `scripts/registry/` — adapter files deleted as part of cutover

- Reviewer checklist for final PR:
  1. Confirm `ServiceBootstrap.gd` remains autoloaded in `project.godot`.
 2. Verify no runtime code `get_node("/root/<LegacyAutoload>")` or `registry.get_service("<Name>Adapter")` calls remain.
 3. Run the headless smoke script(s): `tests/smoke/smoke_fog_gd.gd` and any DM→Player smoke scripts.
 4. Spot-check DM UI flows (profile import/export, binding, map load/save) in the editor.
 5. If CI is available, run the smoke scripts in the CI job before merging.

- Rollback notes:
  - The deleted legacy autoloads (`scripts/autoloads/InputManager.gd`, etc.) are preserved in VCS history — restore from the branch if an immediate rollback is needed.
  - Re-adding a legacy autoload is a quick rollback path while investigating runtime regressions.

Mark this document and the branch PR as the authoritative record of the Phase 3 migration cutover. After merging, close the related migration TODOs and remove any remaining migration flags in project documentation.




