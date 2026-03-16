
---
description: Loaded when working on tests or CI configuration for service behavior
applyTo: 'tests/**'
---

Testing and CI guidance for services and integration flows.

- Unit tests: keep pure logic tests for services; test public API behavior and edge cases.
- Integration tests: cover DM→player message flows for critical subsystems (fog, map load).
- CI: run static analysis (godot-analyzer), unit tests, and a headless smoke test on PRs.

Test tips:
- Mock out heavyweight dependencies in unit tests; test the service contract, not scene internals.
- For integration tests, provide small sample map bundles under `tests/fixtures/`.
