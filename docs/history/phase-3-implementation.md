# Phase 3 Implementation — Extensible Player Profiles & Input Binding

**Status:** Complete  
**Focus:** Persistent player profiles, profile editor UI, input binding, import/export, and stability/UX hardening

---

## Overview

Phase 3 delivers a full player profile system with durable persistence, extensible schema, DM-side profile management, and binding of gamepad/WebSocket inputs to profile IDs.

This phase also includes critical stability and UX fixes discovered during testing:
- global class naming conflicts removed
- WebSocket peer tracking fixed for Godot 4.5 API behavior
- `.map` bundle open/load robustness improvements
- DM/player viewport sync smoothing on player connect/resize
- HiDPI + fullscreen UI scaling fixes for DM toolbar and profile editor

---

## Major Features Completed

### 1. `PlayerProfile` Resource Model
- Added `scripts/PlayerProfile.gd` as `class_name PlayerProfile`.
- Core typed fields:
  - `id` (generated string ID)
  - `player_name`
  - `base_speed`
  - `vision_type` (`NORMAL` / `DARKVISION`)
  - `darkvision_range`
  - `perception_mod`
  - `input_id`
  - `input_type` (`NONE` / `GAMEPAD` / `WEBSOCKET`)
- Extensible payload:
  - `extras: Dictionary`
- Serialization:
  - `to_dict()` / `from_dict()`
  - unknown keys round-trip via `extras`
- Derived utility:
  - `get_passive_perception()` returns `10 + perception_mod`

### 2. Profile Persistence in `GameState`
- `save_profiles()` and `load_profiles()` now fully implemented.
- Backing file:
  - `user://data/profiles.json`
- Runtime behavior:
  - profiles load on `GameState._ready()`
  - `profiles_changed` signal emitted after save/load
  - player lock/position dictionaries rebuilt from profile IDs

### 3. DM Profile Editor UI
- Added `Edit > Player Profiles...` in DM menu.
- Profile editor supports:
  - list view + add/edit/delete
  - name/speed/vision/darkvision/perception
  - live passive perception display
  - input type + input ID
  - `extras` JSON editor
- Save flow now resilient:
  - if no profile is selected, it auto-selects or creates one

### 4. Input Binding Integration
- `InputManager` now supports profile IDs as variant keys.
- Added helper APIs:
  - `clear_all_bindings()` in `InputManager`
  - `bind_peer(...)`, `clear_all_peer_bindings()`, `get_connected_input_peers()` in `NetworkManager`
- DM applies bindings from profiles via `_apply_profile_bindings()`.

### 5. Import / Export
- Added profile import/export in DM profile editor:
  - export profiles to JSON
  - import profiles from JSON array

---

## Bug Fixes and Hardening Included During Phase 3

### A. Global Class Naming Conflict
- Removed `const PlayerProfile = preload(...)` from scripts using global class names.
- Prevents parser/runtime warning/error about constant name collision.

### B. Static Constructor Context Fix
- In `PlayerProfile.from_dict()`, switched to `new()` self-instantiation.

### C. WebSocket Peer Enumeration Fix
- Replaced invalid `WebSocketMultiplayerPeer.get_peers()` usage.
- Added explicit `_input_peers` tracking for connected input peers.

### D. `.map` Bundle Open/Load UX Fixes
- Open map now resolves bundle paths robustly from native dialog variants.
- Supports direct `.map` selection and nested-path resolution to nearest `.map` parent.

### E. Map Image Load Guardrails
- Added empty-image detection and clear status feedback when texture load fails.

### F. UI Scaling + Profile Dialog Usability
- Enabled HiDPI setting in project.
- Added responsive UI scaling logic for DM controls.
- Profile dialog content now scales; close button sizing corrected.

### G. Player Viewport Jump Fix
- On player register/resize, DM preserves world-space viewport footprint by compensating zoom.
- Prevents abrupt viewport-size jumps when player window starts or toggles fullscreen.

---

## Verification Summary

Completed checks:
- create/edit/delete profiles in DM editor
- save/reload profile data from `user://data/profiles.json`
- passive perception updates from `perception_mod`
- bind gamepad and WebSocket peer IDs to profiles
- import/export profile JSON
- open existing `.map` bundles reliably
- profile editor remains usable at larger/smaller display sizes
- player viewport indicator stays stable on player window connect/resize

---

## Ready for Phase 4

Phase 3 goals from the implementation plan are satisfied:
- extensible profile schema
- profile persistence
- DM profile editor
- input binding model
- passive perception support

Next phase can proceed with movement + fog-of-war systems using profile IDs as stable player keys.
