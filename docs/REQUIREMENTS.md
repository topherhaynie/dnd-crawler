# Product Requirements Document: Project "Omni-Crawl"
**Version:** 1.0  
**Status:** Draft / Conceptual  
**Target Platforms:** macOS (Development/DM), Windows (Deployment)

---

## 1. Executive Summary
Omni-Crawl is a specialized Virtual Tabletop (VTT) designed to solve the "DM Bottleneck" during D&D dungeon exploration. It enables simultaneous, independent player movement via multiple input sources, transitioning to a "Locked" state for DM-led roleplay and encounters.

## 2. Core Functional Requirements

### 2.1 Display & Viewports
* **Dual-Window Architecture:** * **DM Window:** Master control interface with full map visibility, hidden layers (traps/secret doors), and UI for player management.
    * **Player Window:** A "Clean" display optimized for a secondary monitor (TV). Shows only revealed areas and active player sprites.
* **Dynamic Fog of War (FoW):** * Automatic line-of-sight based on player position and an "Arc" of vision.
    * DM "Brush" tool to manually reveal or hide areas.

### 2.2 Movement & Interaction
* **Simultaneous Sandbox:** Players move sprites independently without waiting for turns until an event is triggered.
* **The "Event Lock":** * **Trigger-Based:** Stepping on a trap or proximity trigger "freezes" that specific player's input and changes their marker color.
    * **DM Override:** DM can globally freeze all movement for Initiative or individualize a freeze for specific roleplay.
* **The "Dash" Mechanic:** Players can toggle a Dash.
    * *Effect:* +50% Movement Speed.
    * *Penalty:* -50% Vision Radius/Passive Perception.

### 2.3 Map & Grid Tools
* **Calibration:** Define "5 Feet" by dragging a ruler across the imported map.
* **Templates:** Persistent overlays for Cones, Circles (Radius), and Straight Lines.

## 3. User Profiles
* **Persistent Stats:** Save profiles with Name, Base Speed, Vision Type (Darkvision/Normal), and Perception modifiers.
* **Input Binding:** Assign a specific Controller ID or WebSocket ID to a Player Profile.

## 4. Future "Fun" Features
* **Particle Effects:** Fire bursts, lightning, and lingering poisonous fog.
* **Status Indicators:** Visual overlays on sprites for conditions (Prone, Charmed, etc.).