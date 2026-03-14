# AGENTS — Omni-Crawl Codebase Guide

This file is a quick navigation and workflow guide for future coding agents.

## Scope
- Engine: Godot 4.5
- Language: GDScript
- Architecture: dual-process runtime
  - DM host process (authoritative game state)
  - Player display process (render-only client)

## Where To Look First
- Entry and mode split: [scripts/core/Main.gd](scripts/core/Main.gd)
- DM runtime UI/controller: [scripts/ui/DMWindow.gd](scripts/ui/DMWindow.gd)
- Player runtime root: [scripts/player/PlayerMain.gd](scripts/player/PlayerMain.gd)
- Player renderer: [scripts/ui/PlayerWindow.gd](scripts/ui/PlayerWindow.gd)
- Shared map renderer: [scripts/render/MapView.gd](scripts/render/MapView.gd)
- Map model + persistence format: [scripts/data/MapData.gd](scripts/data/MapData.gd)

## Core Singletons (autoloads)
- Global state and profile persistence: [scripts/autoloads/GameState.gd](scripts/autoloads/GameState.gd)
- Input vector aggregation: [scripts/autoloads/InputManager.gd](scripts/autoloads/InputManager.gd)
- WebSocket server and display peer routing: [scripts/autoloads/NetworkManager.gd](scripts/autoloads/NetworkManager.gd)

## Data and Persistence
- Map bundles: directory package `*.map`
  - `map.json`
  - `image.<ext>`
- Runtime map storage root (dev): `user://data/maps/`
- Profile storage file: `user://data/profiles.json`
  - macOS dev path:
    - `~/Library/Application Support/Godot/app_userdata/DnD Crawler/data/profiles.json`

## Phase 3 Profile System
- Profile resource class: [scripts/data/PlayerProfile.gd](scripts/data/PlayerProfile.gd)
- DM profile editor is built dynamically in [scripts/ui/DMWindow.gd](scripts/ui/DMWindow.gd)
  - menu path: Edit -> Player Profiles...
  - supports add/edit/delete/import/export and gamepad/WS binding

## Network Message Flow
- Display client handshake: `{"type":"display", ...}`
- Display viewport resize: `{"type":"viewport_resize", ...}`
- DM -> display map, fog, camera, and state messages:
  - `map_loaded`
  - `map_updated`
  - `fog_updated`
  - `camera_update`
  - `state`
  - `delta`

## Visibility Authority
- DM process is authoritative for LOS/fog reveal and gameplay visibility logic.
- Player process is render-only for visibility and should consume DM packets.
- DM/player fog-opacity differences are visual-only (same underlying revealed/hidden state).
- Prefer `fog_updated` over `map_updated` for frequent fog changes to avoid player map reload churn.

## Recent Stability Notes
- Map open flow accepts native dialog path variants and resolves nearest `.map` bundle.
- Player window connect/resize preserves world-space viewport footprint by compensating zoom.
- UI scales for HiDPI/fullscreen via [scripts/ui/DMWindow.gd](scripts/ui/DMWindow.gd) and `window/dpi/allow_hidpi=true`.

## Documentation Index
- Requirements: [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- Technical architecture: [docs/TECHNICAL_SPECIFICATIONS.md](docs/TECHNICAL_SPECIFICATIONS.md)
- Master phased plan: [docs/plan-omniCrawlVtt.prompt.md](docs/plan-omniCrawlVtt.prompt.md)
- Completed phase reports:
  - [docs/phase-1-implementation.md](docs/phase-1-implementation.md)
  - [docs/phase-2-implementation.md](docs/phase-2-implementation.md)
  - [docs/phase-3-implementation.md](docs/phase-3-implementation.md)

## Conventions For Future Agents
- Avoid naming `const` preload aliases the same as global `class_name` scripts.
- Prefer explicit autoload lookups (`/root/<SingletonName>`) in scripts where analyzer cannot resolve singleton identifiers.
- Keep `.map` and `.sav` semantics separate (`.map` is definition, `.sav` is runtime/session state).
- When changing DM/player viewport behavior, update both DM indicator behavior and `camera_update` broadcasts together.
