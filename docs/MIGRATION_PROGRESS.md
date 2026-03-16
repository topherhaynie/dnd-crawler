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

## Notes for future agents
- See `docs/INVENTORY.md` and `docs/MIGRATION_PLAN.md` for context and plan.
- Use `ServiceRegistry.register(name, instance, required_methods)` to assert protocol conformance in debug builds.
- Keep adapter files under `scripts/registry/` and add a TODO comment with the removal plan when adapters become unnecessary.
