# Technical Architecture: Omni-Crawl
**Engine:** Godot 4.x (Standard)  
**Primary Language:** GDScript (Python-like syntax)  
**IDE:** VS Code + Godot Tools + GitHub Copilot  

---

## 1. System Topology
The application will operate as a **Local Server-Client Hybrid**. The Godot instance acts as the "Host," processing local HID (Human Interface Device) inputs and remote WebSocket inputs simultaneously.

## 2. Input Handling Strategy
To support 6+ players across Mac/Windows while bypassing Bluetooth hardware caps:

| Input Source | Protocol | Max Count | Use Case |
| :--- | :--- | :--- | :--- |
| **Physical Gamepads** | HID (XInput/DirectInput) | ~4 | Joy-Cons, Xbox/PS Controllers |
| **Mobile Devices** | WebSockets (TCP) | Unlimited | Phones acting as virtual joysticks |

### 2.1 Hardware Implementation
* **Gamepad API:** Utilize Godot's `Input` singleton to map specific `device_id` integers to Player Scenes.
* **WebSocket Server:** A lightweight `WebSocketMultiplayerPeer` node within Godot to receive JSON packets from mobile browsers (representing X/Y axis movement).

## 3. Graphics & Rendering
* **Window Management:** * Primary Window: `DisplayServer.window_set_mode` for the DM.
    * Secondary Window: `DisplayServer.window_create` to spawn the Player View on the connected TV.
* **Vision System:** * `PointLight2D` attached to sprites with a "Mask" texture for the vision arc.
    * `LightOccluder2D` layers on the map to create real-time shadows.

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