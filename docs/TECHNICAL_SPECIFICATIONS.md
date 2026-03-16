# Technical Architecture: Omni-Crawl
**Engine:** Godot 4.x (Standard)  
**Primary Language:** GDScript (Python-like syntax)  
**IDE:** VS Code + Godot Tools + GitHub Copilot  

---

## 1. System Topology
The application will operate as a **Local Server-Client Hybrid**. The Godot instance acts as the "Host," processing local HID (Human Interface Device) inputs and remote WebSocket inputs simultaneously.

### 1.1 Runtime Split (Phase 4)
The runtime is split into three roles:

| Role | Responsibility | Key Script |
| :--- | :--- | :--- |
| **Backend** | Authoritative simulation and state arbitration (inputs, movement, collisions). | `scripts/core/BackendRuntime.gd` |
| **DM Window** | UI/editor interactions and operator controls; forwards intent to backend and broadcasts DM-managed state (map, camera, fog snapshots). | `scripts/ui/DMWindow.gd` |
| **Player Window** | Render-only consumer of DM packets (`map`, `camera`, `state`, `fog`). | `scripts/ui/PlayerWindow.gd` |

Status: Phase 4 is complete.

## 2. Input Handling Strategy
To support 6+ players across Mac/Windows while bypassing Bluetooth hardware caps:

| Input Source | Protocol | Max Count | Use Case |
| :--- | :--- | :--- | :--- |
| **Physical Gamepads** | HID (XInput/DirectInput) | ~4 | Joy-Cons, Xbox/PS Controllers |
| **Mobile Devices** | WebSockets (TCP) | Unlimited | Phones acting as virtual joysticks |

### 2.1 Hardware Implementation
* **Gamepad API:** Utilize Godot's `Input` singleton to map specific `device_id` integers to Player Scenes.
* **WebSocket Server:** A lightweight `WebSocketMultiplayerPeer` node within Godot to receive JSON packets from mobile browsers (representing X/Y axis movement).

### 2.2 Input Arbitration
Input vectors are merged by source priority in the backend pipeline:

1. DM override input (highest priority)
2. Gamepad input
3. Network/websocket input

This allows asynchronous input collection from multiple sources while preserving a deterministic winner per frame.

### 2.3 Non-Goal: Deterministic Command Queue
Deterministic command ordering (timestamped global input queue/replay pipeline) is explicitly out of scope for this project.

## 3. Graphics & Rendering
* **Window Management:** * Primary Window: `DisplayServer.window_set_mode` for the DM.
    * Secondary Window: `DisplayServer.window_create` to spawn the Player View on the connected TV.
* **Vision System:** * `PointLight2D` attached to sprites with a "Mask" texture for the vision arc.
    * `LightOccluder2D` layers on the map to create real-time shadows.

### 3.1 Visibility Authority and Layering
* **Authoritative Runtime:** backend computes authoritative simulation state (movement, wall blocking, token state). Fog reveal/LOS is DM-managed via `scripts/fog/FogSystem.gd` and distributed as snapshots.
* **Player Runtime:** render-only consumer of DM packets. Player does not run fog-reveal or gameplay LOS logic.
* **Layer Policy:**
    * DM view can render additional control/debug layers (walls, traps, editing helpers, transparent fog).
    * Player view renders only gameplay-relevant layers with player-facing fog opacity.
    * DM/player fog-opacity difference is presentation-only, not separate visibility logic.

### 3.1.1 Shared Layer Stack
Both DM and Player render through the same `MapView` layer composition. Role-specific behavior is visibility gating, not separate rendering code.

1. Background
2. Map
3. Grid
4. Wall
5. Object
6. Player
7. Fog
8. Toolbar/DM UI (outside `MapView`)
9. Player viewport indicator (DM only)

The player viewport indicator layer is hidden in player profile mode.

### 3.2 Display Protocol (DM -> Player)
* `map_loaded`:
    * Full map payload for initial load / late-join recovery.
    * Does not inline fog snapshot bytes.
* `map_updated`:
    * Structural map changes (grid calibration, walls, map metadata).
    * Avoid for high-frequency fog updates.
* `fog_state_snapshot_begin` / `fog_state_snapshot_chunk` / `fog_state_snapshot_end`:
    * Chunked fog snapshot transport for large fog images.
    * Prevents websocket outbound OOM during initial sync and resync.
* `fog_state_snapshot`:
    * Reassembled snapshot message applied atomically on Player runtime.
    * Encodes fog history as PNG bytes (base64 in transport).
* `fog_updated` / `fog_delta`:
    * Legacy compatibility channels retained for non-snapshot paths.
    * Not the primary transport for DM toolbar fog edits.
* `camera_update`:
    * Player camera center/zoom from DM viewport controls.
* `state` / `delta`:
    * Token/player simulation state (position, facing, vision stats, etc.).

### 3.3 Performance Rule
* Never send full-map packets for per-frame visibility changes.
* Never inline large fog snapshots into `map_loaded` or `map_updated` payloads.
* Fog full-sync must use chunked snapshot transport.
* High-frequency gameplay updates should use narrow payloads (`state`/`delta`, camera updates) to minimize serialization and render churn.

### 3.4 Fog Authority
* DM process is authoritative for visibility output distributed to players.
* Fog runtime uses image-backed history plus live LOS lights compositing (`scripts/fog/FogSystem.gd`).
* DM brush/rectangle fog tools edit fog history directly in image space.
* Player runtime is render-only and applies DM snapshots without local fog-authority simulation.

### 3.5 Fog Rendering Pipeline (Current)
* Persistent fog history is stored as an L8 image/texture (`history_tex`).
* Live LOS is rendered in a dedicated lights-only SubViewport (`live_lights_tex`) using `PointLight2D` and `LightOccluder2D`.
* Composite shader (`assets/effects/dm_mask_fog.gdshader`) combines history and live masks:
    * DM: history-weighted dimming view.
    * Player: gameplay fog alpha from combined reveal mask.
* History merge is monotonic (`max(existing, live)`) so revealed areas are not lost.
* Initial sync and manual resync send PNG snapshot data through chunked fog snapshot messages.

## 4. Software Stack & Dev Workflow
* **Version Control:** Git.
* **Data Persistence:**
    * `.map` bundle directories for map definitions: `map.json` + copied image asset.
    * `.sav` bundle directories for session/runtime state that reference a `.map` bundle.
    * JSON remains the internal serialization format inside each bundle.
* **Agent Integration:** * VS Code "External Editor" mode enabled in Godot.
    * Copilot used for GDScript logic (utilizing its Python-context understanding).

## 5. Potential Constraints
* **Mac/Windows Parity:** Use Godot's `OS.get_name()` to handle pathing differences for map imports.
* **Bundle UX Parity:** `.map`/`.sav` are directory bundles internally; Finder/Explorer presentation and native dialog behavior depend on exported app metadata (macOS `Info.plist` package/document declarations, Windows file associations). Final polish is deferred to Phase 10.
* **Network Latency:** Local WiFi is required for Phone-based inputs to ensure <20ms latency.