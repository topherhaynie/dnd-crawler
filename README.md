# The Vault

A virtual tabletop (VTT) application for D&D, built with Godot 4.5. Designed for in-person play with a dual-screen setup — one screen for the DM, one for the players.

## Downloads

| Platform | Download | Size |
| :--- | :--- | :--- |
| macOS (x86_64 / Apple Silicon) | [TheVault-1.0.0-beta11-macOS.zip](https://github.com/topherhaynie/dnd-crawler/releases/download/v1.0.0-beta11/TheVault-1.0.0-beta11-macOS.zip) | ~149 MB |
| Windows (x86_64) | [TheVault-1.0.0-beta11-Windows.zip](https://github.com/topherhaynie/dnd-crawler/releases/download/v1.0.0-beta11/TheVault-1.0.0-beta11-Windows.zip) | ~90 MB |

## Installation

### macOS

1. Download and unzip **TheVault-1.0.0-beta11-macOS.zip**.
2. Move **The Vault.app** to your Applications folder (or wherever you prefer).
3. The app is ad-hoc signed and not notarized, so macOS will quarantine it. Remove the quarantine flag:
   ```bash
   xattr -cr "/Applications/The Vault.app"
   ```
4. Double-click **The Vault.app** to launch.

> **Note:** If you still see a "damaged" or "unidentified developer" warning, open **System Settings → Privacy & Security** and click **Open Anyway**.

### Windows

1. Download and unzip **TheVault-1.0.0-beta11-Windows.zip**.
2. Run **The Vault.exe**.
3. If Windows SmartScreen warns about an unrecognized app, click **More info → Run anyway**.

## Usage

The Vault runs as two processes:

- **DM Window** — the authoritative host. Load maps (`.map` bundles), paint fog of war, manage tokens and game state.
- **Player Display** — a render-only client that connects automatically over the local network. Point a second monitor or projector at this window.

Launch the app and the DM window opens. The player display connects via WebSocket on your LAN — no internet required.

## Building from Source

Requires:
- [Godot 4.5 .NET (mono)](https://godotengine.org/download)
- .NET SDK 8.0+

```bash
# macOS
./build_macos.sh

# Windows (cross-compile from macOS)
./build_windows.sh
```

Build output lands in `build/macos/` or `build/windows/`.

## License

© EverstoneKeep. All rights reserved.
