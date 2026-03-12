# Phase 3.5 Cleanup — Organization, Documentation, and Workspace Hygiene

**Status:** Complete  
**Purpose:** Make the codebase easier to navigate for future agents and reduce avoidable workspace noise before Phase 4.

---

## What Was Done

### 1. Added Agent Navigation Guide
- New root guide: [AGENTS.md](AGENTS.md)
- Includes:
  - architecture map (DM process vs Player process)
  - key files by concern
  - singleton responsibilities
  - persistence paths and bundle layout
  - message flow summary
  - practical conventions for future code changes

### 2. Added Cleanup Report
- This report documents the Phase 3.5 intent and outcomes for future agents.

### 3. Reduced Singleton Analyzer Friction
- Updated direct singleton references to explicit root lookups in core scripts:
  - [scripts/autoloads/InputManager.gd](scripts/autoloads/InputManager.gd)
  - [scripts/autoloads/NetworkManager.gd](scripts/autoloads/NetworkManager.gd)
  - [scripts/Main.gd](scripts/Main.gd)
- Why: VS Code/Godot language analysis can misreport unresolved autoload symbols in some contexts.

### 4. Main Window Positioning Cleanup
- Refined window-centering math in [scripts/Main.gd](scripts/Main.gd) to avoid mixed vector type math and keep intent explicit.

---

## Known Workspace Analysis Noise (Current)

Some diagnostics still appear inconsistent with on-disk source (e.g., stale references to symbols or files that exist). This is a known behavior when the GDScript language server cache gets out of sync.

Suggested local remedy if this reappears:
1. Reload VS Code window.
2. Restart the Godot editor and reattach the language server.
3. Re-run project once so autoload metadata is refreshed.

No runtime regressions were introduced by this cleanup pass.

---

## Why This Matters Before Phase 4

Phase 4 will add movement + FoW complexity across DM, Player, and autoload systems. This cleanup ensures:
- clearer ownership boundaries
- faster file discovery for future agents
- fewer false starts from analyzer confusion

That lowers risk when introducing `PlayerSprite` movement, camera interactions, and visibility logic.
