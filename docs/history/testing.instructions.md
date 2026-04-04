---
applyTo: "tests/**"
---

# Testing Conventions

## Test Location

| Test type | Directory |
|---|---|
| Unit tests | `tests/unit/` |
| Smoke / integration tests | `tests/smoke/` |
| In-engine addon tests | `addons/tests/` |

## Naming

- Test files: `test_<feature>.gd` (e.g. `test_fog_service.gd`)
- Test methods: `test_<behaviour>` (e.g. `test_apply_snapshot_returns_false_on_empty`)
- Helper methods: prefix with `_` (e.g. `_make_fog_service()`)

## GDScript Typing in Tests

Follow the same strict-typing rules as production code (see `gdscript-style.instructions.md`). All variables, parameters, and return types must be explicitly declared.

## Protocol Stubs in Tests

When testing code that depends on a service, create a minimal stub that extends the relevant protocol:

```gdscript
class _StubFogService extends IFogService:
    var last_enabled: bool = false
    func set_fog_enabled(enabled: bool) -> void:
        last_enabled = enabled
```

This ensures the stub satisfies the type contract without triggering `push_error` stubs from the protocol base.

## No Real File I/O in Unit Tests

Unit tests must not read/write real files. Use `PersistenceService` mocks or `tmp://` paths when testing persistence logic.

## Assert Style

Use Godot's built-in `assert()` or GUT assertions (`assert_eq`, `assert_true`, etc.) consistently within the same test file. Do not mix assertion styles.

## FogSystem Tests

`FogSystem` cannot be unit-tested in isolation (requires a running scene tree with SubViewports). Use smoke tests that instantiate a minimal scene and verify observable side-effects (e.g. `get_fog_state()` returns non-empty after seeding).
