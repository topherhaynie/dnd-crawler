# Phase 1 Implementation — Project Scaffold & Dual-Process Architecture

**Status:** ✅ Complete  
**Engine:** Godot 4.5 (GDScript, Forward Plus)  
**Platform:** macOS (dev) → Windows (deployment)

---

## Overview

Phase 1 establishes the runnable skeleton of Omni-Crawl: two fully independent OS windows (DM
host and Player TV display) that launch together from a single F5 press, backed by three core
autoload singletons and a local WebSocket channel between the two processes.

---

## Architecture Decision: Two-Process Model

The original design called for two `Window` nodes inside a single Godot process. On macOS, all
windows that belong to the same process are grouped by the OS (shared Dock icon, co-moving, shared
minimize). There is no Godot API that escapes this at the native window level.

**Solution:** spawn the Player display as a separate OS process using `OS.create_process()`. Each
process is its own App window — completely independent from the OS perspective. The two processes
communicate over a local WebSocket connection (port 9090) where the DM process is the authoritative
server and the Player process is a dumb renderer.

This also gives us a clean separation of concerns for free: game logic, state authority, and input
routing all live exclusively in the DM process. The Player process only knows how to render what it
is told.

### Process detection

The single project binary is used for both roles. `Main.gd` checks `OS.get_cmdline_user_args()`
at startup:

| Condition | Mode | What loads |
|---|---|---|
| No `--player-window` arg | **DM host** | `DMWindow.tscn` + WS server + spawns Player process |
| `--player-window` present | **Player client** | `PlayerMain.tscn` + WS client |

The `--` separator is required when passing user args via `OS.create_process()` so Godot does not
try to interpret `--player-window` as an engine flag.

---

## Files Created / Modified

### `project.godot`
- `[dotnet]` section removed (project is GDScript-only)
- `embed_subwindows=false` added to `[display]` — prevents any `Window` node from being drawn
  inside its parent's viewport
- `run/main_scene` and `config/main_scene` both point to `res://scenes/Main.tscn`
- Autoloads registered: `GameState`, `InputManager`, `NetworkManager`

### `scripts/Main.gd`
Entry point. Reads command-line user args to select DM or Player mode, then:
- **DM mode** — sets window title, appends window ID to `GameState.windows`, instantiates
  `DMWindow.tscn`, and (deferred by one frame) calls `_launch_player_process()`
- **Player mode** — sets window title and instantiates `PlayerMain.tscn`

`_launch_player_process()` builds the arg list dynamically: in editor builds it prepends
`--path <project_dir>` so the second Godot editor instance can find the project.

### `scripts/autoloads/GameState.gd`
Central authoritative state store (DM process only in Phase 1):
- `player_locked: Dictionary` — per-player lock flags
- `windows: Array` — registered window IDs
- `profiles: Array` — player profile objects (Phase 3)
- `lock_player()` / `unlock_player()` / `is_locked()`
- `push_notification()` / `dismiss_notification()`
- `save_state()` / `load_state()` stubs (Phase 9)

### `scripts/autoloads/InputManager.gd`
Routes physical input to per-player movement vectors:
- `DEAD_ZONE = 0.15`
- `get_vector(player_id)` — returns zero vector when player is locked
- `set_vector(player_id, vec)` — called by `NetworkManager` for WS clients
- `bind_gamepad(device_id, player_id)`

### `scripts/autoloads/NetworkManager.gd`
Owns the `WebSocketMultiplayerPeer` server on port 9090. Classifies connected peers into two
buckets:

| Peer type | Detection | Behaviour |
|---|---|---|
| **Display** (Player process) | sends `{"type":"display"}` handshake | added to `_display_peers`; receives state pushes via `broadcast_to_displays()` |
| **Input** (mobile client) | sends movement packets | validated and forwarded to `InputManager` |

Key public API:
- `broadcast_to_displays(data: Dictionary)` — serialises to UTF-8 and sends to every display peer
- `bind_peer(peer_id, player_id)` — associates a WS input peer with a player profile (Phase 5)

Peer cleanup on disconnect removes from both `ws_bindings` and `_display_peers`.

### `scripts/PlayerClient.gd`
WebSocket client that runs inside the Player process:
1. Connects to `ws://127.0.0.1:9090`
2. On `STATE_OPEN`, sends `{"type":"display","role":"player_window"}` handshake
3. Polls in `_process()`, drains packets, emits `state_received(data)` for `state` / `delta` msg types
4. On disconnect, schedules a 2-second retry via a one-shot `SceneTree` timer

### `scripts/PlayerMain.gd`
Root controller for the Player process. Instantiates:
- `PlayerWindow.tscn` — the display viewport (placeholder for Phase 4 map renderer)
- `PlayerClient` node — starts the WS connection immediately

Connects `PlayerClient.state_received` → `_on_state_received()` (stub; Phase 4 will route to
map/token/FoW renderers).

### `scripts/DMWindow.gd` / `scripts/PlayerWindow.gd`
Placeholder stubs that print their name on ready. UI and rendering built out in Phases 2–4.

### Scenes
| Scene | Root node | Script |
|---|---|---|
| `scenes/Main.tscn` | `Node` | `Main.gd` |
| `scenes/DMWindow.tscn` | `Node` | `DMWindow.gd` |
| `scenes/PlayerMain.tscn` | `Node` | `PlayerMain.gd` |
| `scenes/PlayerWindow.tscn` | `Node` | `PlayerWindow.gd` |

---

## How to Run

**In the Godot editor:**  
Press **F5** (or Run Project). The editor instance is the DM process. It automatically launches a
second Godot editor instance as the Player process. Two separate windows appear; the Output panel
shows both processes' print statements as they share stdout to the editor console.

**As an exported binary:**  
Run the exported executable normally — it starts as the DM process and spawns a sibling process
(`--player-window`) automatically.

---

## Verification Checklist

- [x] Two independent OS windows launch from F5 (no co-moving, no shared minimize on macOS)
- [x] DM window title: "Omni-Crawl — DM"
- [x] Player window title: "Omni-Crawl — Players"
- [x] Console: `Main: running as DM host`
- [x] Console: `Main: launched Player window process (pid=…)`
- [x] Console: `Main: running as Player display client`
- [x] Console: `PlayerClient: connected to DM server at ws://127.0.0.1:9090`
- [x] Console: `NetworkManager: display peer registered — peer_id … (total: 1)`
- [x] Console: `PlayerClient: ping from DM`

---

## Known Limitations & Phase 2 Prerequisites

- `DMWindow` and `PlayerWindow` are empty stubs — no UI yet
- The Player process window shows a blank black viewport
- `broadcast_to_displays()` is wired but nothing calls it yet (game systems start in Phase 4)
- Mobile WS input clients are not yet handled by `NetworkManager` (Phase 5)
