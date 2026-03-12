# Phase 2 Implementation — UX Polish & Player Viewport Control

**Status:** ✅ Complete  
**Focus:** Menu bar UI, toolbar controls, calibration workflow, viewport indicator sync, and live grid refinement

---

## Overview

Phase 2 polishes the user experience by implementing a full-featured DM interface with menu bar, toolbar controls, and real-time player viewport synchronization. The DM can now seamlessly drag a green "Player View" box on the map to control what players see, or pan/zoom independently. Grid overlay now respects map boundaries.

---

## Major Features Completed

### 1. **Native macOS Menu Bar**
- **File Menu:** Load Map, Save Map, Quit
- **Edit Menu:** Calibrate Grid, Set Scale Manually
- **View Menu:** Toggle Toolbar, Grid Overlay, Reset View, Launch Player Window
- Uses `MenuBar.prefer_global_menu = true` to merge native OS menu bar (not in-window)

### 2. **Collapsible Toolbar**
- **Tool Toggle:** Select / Pan modes (radio group)
- **DM Zoom:** Zoom In, Zoom Out, Reset View
- **Grid Type Selector:** Square, Hex (flat), Hex (pointy) with live grid redraw
- **Status Label:** Real-time feedback for all actions
- **Player View Controls:** Zoom ±, Sync to DM Player button
- **Play Mode Button:** Launch player display process on-demand

### 3. **Map Loading & Persistence**
- **Native FileDialog** for selecting map images (PNG, JPG, JPEG, WebP, BMP, TGA)
- **Automatic JSON save/load** in `user://data/maps/`
- Metadata includes grid type, calibration, scale, and saved camera state
- Late-joining players auto-receive the active map via `display_peer_registered` signal

### 4. **Calibration Workflow**
- **Interactive Tool:**
  - Click-drag a line on the map to define distance
  - Release → dialog asks "How many feet?"
  - Applies calibration and broadcasts to all players
  - **Fixed Behavior:** Grid calibration no longer resets player cameras (see `map_updated` below)

### 5. **Manual Scale Entry**
- Dialog to manually set grid scale: pixels per cell ↔ feet per cell
- Normalizes to 5-ft cell reference internally
- Works for square and hex grids (hex converts internally)

### 6. **Player Viewport Control (DM View)**
- **Green Indicator Box:** Drawn on DM map showing what players currently see
- **Drag Interaction:** DM drags the box to reposition player camera (debounced 50ms broadcast)
- **Zoom Controls:** "Zoom +/−" buttons adjust player camera zoom independently
- **Sync to DM:** Button snaps player view to match DM's current camera state
- **Dynamic Synchronization:** Player window resize event immediately updates indicator box on DM view

### 7. **Play Mode Button**
- **On Click:** Launches a new Player display process (independent OS window)
- **Process Spawning:** Uses `OS.create_process()` with `--player-window` argument
- **Late-Joining Sync:** New player auto-receives current map and camera state
- **No Auto-Launch:** Players no longer spawn automatically at startup; DM launches them on-demand

### 8. **Grid Overlay Refinement**
- **Square Grid:** Lines drawn up to and including map boundaries (no overflow)
- **Hex Grid:** Cells calculated precisely to cover texture; cells clipped if extending beyond bounds
- **Boundary Clip:** Both square and hex respect `texture.get_size()` exactly
- **Bug Fix:** Larger map images now render full grid coverage without gaps

### 9. **Network Messaging**
- **New Signals:**
  - `NetworkManager.display_peer_registered(peer_id, viewport_size)` — fired when player connects
  - `NetworkManager.display_viewport_resized(peer_id, viewport_size)` — fired when player resizes window
- **Packet Types:**
  - `map_loaded` — full map reload (resets player camera) — sent on initial file load + late joiners
  - `map_updated` — grid/scale changes (preserves player camera) — sent on calibration/grid/scale/save
  - `camera_update` — player camera position/zoom — sent when DM drags indicator or adjusts zoom
  - `viewport_resize` — player sends actual window size when resized

### 10. **IndicatorOverlay Scene**
- Dedicated `IndicatorOverlay.gd` node renders the green box on top of map
- Solves rendering order issue (Godot's `_draw()` renders before children)
- Border width stays crisp across zoom levels via camera zoom compensation

---

## Technical Decisions & Rationale

### Two Separate Message Types for Map Updates
| Message | Behavior | Use Case |
|---------|----------|----------|
| `map_loaded` | Reload entire map + reset camera | New map file load, late-joining player, map fundamentals change |
| `map_updated` | Update grid/scale only, preserve camera | Calibration, grid type change, scale adjustment, save |

This prevents player camera from resetting during UX-only changes (e.g., calibrating the grid).

### Dynamic Viewport Size Reporting
Players send their actual viewport size in the handshake + report resizes. DM uses this to:
1. Calculate the exact world-space visible area
2. Draw indicator box with correct dimensions
3. Update immediately when player resizes window

No guessing or hardcoded defaults — the indicator is always accurate.

### Debounced Viewport Broadcasts
DM drags the indicator box and emits `viewport_indicator_moved` signals at high frequency. To avoid flooding the network, broadcasts are debounced at 50ms (20 times per second) — enough for smooth interaction without overhead.

---

## Files Changed/Created

| File | Change |
|------|--------|
| `scripts/DMWindow.gd` | Rebuilt: MenuBar, Toolbar, Dialogs, Viewport Control, Play Mode |
| `scripts/MapView.gd` | Added IndicatorOverlay integration, dynamic indicator rect sync |
| `scripts/IndicatorOverlay.gd` | **NEW:** Dedicated rendering layer for green box |
| `scripts/GridOverlay.gd` | Fixed hex/square grid boundary clipping; precise cell calculation |
| `scripts/PlayerClient.gd` | Added viewport size handshake + `size_changed` monitoring |
| `scripts/PlayerWindow.gd` | Added `_handle_map_updated()` for grid-only updates |
| `scripts/Main.gd` | Removed auto-launching player; moved to DMWindow |
| `scripts/autoloads/NetworkManager.gd` | Added `display_peer_registered/resized` signals, `broadcast_map_update()`, viewport_resize packet routing |

---

## Testing Checklist

✅ **Map Loading:**
- Load image → grid overlay renders  
- Save map → JSON persists metadata  
- Load saved map → grid/calibration restored  

✅ **Calibration:**
- Calibrate grid → indicator stays in place, players don't zoom out  
- Change grid type → grid redraws, player view unchanged  
- Manual scale entry → works for square and hex  

✅ **Player Viewport:**
- DM drags green box → player camera follows (debounced)  
- DM clicks "Zoom +" → green box shrinks, player zooms in  
- DM clicks "Sync to DM" → player view jumps to DM's current view  
- Player resizes window → green box on DM updates immediately  

✅ **Play Mode:**
- DM clicks "▶ Play Mode" → separate player window launches  
- Player connects late → receives map + current camera state  
- DM pan/zoom/calibrate → all players see updates in real time  

✅ **Grid Boundaries:**
- Small map: grid stops at edge, no overflow  
- Large map (>4096px): grid extends fully, no gaps  
- Hex grids: cells clipped at boundary, not bleeding beyond  

---

## Known Limitations & Future Work

- **Phase 3 (Token Placement):** Player sprite spawning, FoW, and visibility culling (requires extending `PlayerWindow` to manage Token nodes)
- **Phase 4 (Input Routing):** Mobile controller input and gamepad mapping (network packet routing exists; just needs HID binding on Phase 5)
- **Phase 5 (Initiative & Events):** Event trigger system, conditional movement locks, status effects (game logic layer)
- **Phase 6+ (Polish):** Particle effects, sound, accessibility, performance optimization

---

## Commit Message

```
Phase 2 Complete: DM UI, Viewport Control, Grid Refinement

• Added native macOS menu bar (File/Edit/View menus)
• Built collapsible toolbar with Select/Pan tools, Zoom, Grid selector, Status
• Implemented calibration workflow (interactive line draw, ft input, live refresh)
• Added manual scale dialog (pixels ↔ feet for square + hex grids)
• Built player viewport control on DM map (draggable green indicator box)
  - Drag to move player camera (debounced 50ms)
  - Zoom +/- buttons for player view zoom
  - Sync to DM button to snap player to DM's current view
• Added Play Mode button: launches player process on-demand (not auto-launch)
• Implemented dynamic viewport size sync (player reports actual window size on connect + resize)
• Added IndicatorOverlay node (avoids _draw() rendering-order issue, renders on top of map)
• Fixed grid boundaries: square/hex grids now stop exactly at map edge, no overflow
• Added map_updated message type (grid/scale changes preserve player camera)
• Late-joining players now auto-receive current map + camera state
• Calibration no longer resets player view (uses map_updated, not map_loaded)

Network Changes:
  - PlayerClient sends viewport_width/height in handshake
  - PlayerClient monitors size_changed and broadcasts viewport_resize packets
  - NetworkManager emits display_peer_registered(peer_id, viewport_size) signal
  - NetworkManager emits display_viewport_resized(peer_id, viewport_size) signal
  - broadcast_map() now only for initial load + late joiners
  - Added broadcast_map_update() for grid/calibration changes

Ready for Phase 3: Token Placement & Fog of War
```
