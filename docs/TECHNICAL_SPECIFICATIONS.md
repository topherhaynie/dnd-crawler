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
| **Backend** | Authoritative simulation and state arbitration (inputs, movement, fog reveal/LOS, collisions). | `scripts/core/BackendRuntime.gd` |
| **DM Window** | UI/editor interactions and operator controls; forwards intent to backend and broadcasts backend-authoritative state. | `scripts/ui/DMWindow.gd` |
| **Player Window** | Render-only consumer of DM packets (`map`, `camera`, `state`, `fog`). | `scripts/ui/PlayerWindow.gd` |

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
* **Authoritative Runtime:** backend computes gameplay visibility state (fog reveal, LOS, wall blocking, token state).
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
* `map_updated`:
    * Structural map changes (grid calibration, walls, map metadata).
    * Avoid for high-frequency fog updates.
* `fog_updated`:
    * Lightweight fog-only update payload (`fog_cell_px`, `fog_hidden_cells`).
    * Used for frequent visibility changes to avoid player-side full map reload hitches.
* `camera_update`:
    * Player camera center/zoom from DM viewport controls.
* `state` / `delta`:
    * Token/player simulation state (position, facing, vision stats, etc.).

### 3.3 Performance Rule
* Never send full-map packets for per-frame visibility changes.
* High-frequency gameplay updates should use narrow payloads (`state`/`delta`, `fog_updated`) to minimize serialization and map rebuild cost.

### 3.4 Fog Authority
* LOS-driven fog reveal is backend-authoritative (`BackendRuntime.gd`) and runs on a fixed reveal tick.
* DM brush/rectangle fog edits are treated as DM input events and serialized/broadcast from DM runtime.
* `MapView.gd` is now rendering/application logic for fog state, not fog-visibility authority.

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