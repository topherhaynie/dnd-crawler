# Runtime Protocols and Message Schemas

This document defines the canonical runtime message schemas and conventions used by the DM and display clients. It is the single source of truth for message formats, chunking/backpressure rules, example payloads, versioning expectations, and security guidance.

## Top-level rules

- Messages are JSON objects encoded as UTF-8.
- Every message MUST include a `type` string and a `msg_id` (string or integer) when request/response correlation is needed.
- Timestamps, when present, MUST be ISO 8601 strings in UTC (e.g. `2024-01-01T12:00:00Z`).
- Use compact, stable field names. Field additions are allowed; removals or renames require version bumping and migration notes.
- Transport is assumed to be reliable ordered (WebSocket/TCP). Where unreliable transports are used, the payloads must include explicit sequence/correlation info.

## Common fields

- `type` (string): canonical message type name.
- `msg_id` (string|int, optional): client-generated id for correlating responses.
- `in_reply_to` (string|int, optional): id of message being replied to.
- `version` (string, optional): schema version for this message, e.g. `1.0`.
- `ts` (string, optional): ISO 8601 timestamp indicating when the message was produced.
- `sender` (string, optional): logical sender id (e.g. `dm`, `display-<id>`).

## Client -> Server message definitions (examples)

The following example messages are common client (display) -> server (DM) messages. Fields shown are illustrative; implementations should follow the Top-level rules and Common fields.

- Connect / handshake

```json
{
  "type": "handshake",
  "msg_id": "c1",
  "version": "1.0",
  "sender": "display-42",
  "payload": { "role": "display", "capabilities": ["fog_reveal","viewport_sync"] }
}
```

- Input / control message

```json
{
  "type": "input_event",
  "msg_id": "c2",
  "payload": {
    "input_type": "pointer_move",
    "pos": {"x": 123.4, "y": 567.8},
    "buttons": 1
  }
}
```

- Request resource / save

```json
{
  "type": "save_request",
  "msg_id": "c3",
  "payload": { "map_id": "mymap", "slot": "quick1" }
}
```

## Server -> Client (DM -> displays) message definitions (examples)

Messages from the authoritative DM process to display clients. Many messages may be broadcast; when large payloads are required, see Backpressure & chunking rules.

- Map loaded

```json
{
  "type": "map_loaded",
  "msg_id": "s1",
  "payload": {
    "map_id": "mymap",
    "map_meta": { "width": 2048, "height": 1536 },
    "assets": ["image.0.png", "image.1.png"]
  }
}
```

- Fog update (small)

```json
{
  "type": "fog_updated",
  "msg_id": "s2",
  "payload": {
    "reveal": [{"x":100,"y":200,"radius":32}],
    "timestamp": "2026-03-18T12:34:56Z"
  }
}
```

- State delta (small)

```json
{
  "type": "state_delta",
  "msg_id": "s3",
  "payload": { "entities": [{ "id": "e1", "x": 10, "y": 20 }] }
}
```

- Camera / viewport update (DM -> displays)

Sent by the DM whenever the player viewport position, zoom, or rotation changes.

```json
{
  "msg": "camera_update",
  "position": { "x": 960.0, "y": 540.0 },
  "zoom": 1.0,
  "rotation": 90
}
```

**Fields:**
- `msg` (string): always `"camera_update"`
- `position.x`, `position.y` (float): world-space centre of the player viewport
- `zoom` (float, range `0.1–8.0`): camera zoom level
- `rotation` (int, one of `0 | 90 | 180 | 270`, default `0`): map rotation in degrees clockwise. Applied to the display camera and compounded with each player's `table_orientation` for input-vector compensation.

- Window resize request (DM -> displays)

Sent by the DM when the player viewport indicator is resized and the player is **not** fullscreen. The player should resize its OS window to the requested pixel dimensions if possible.

```json
{
  "msg": "window_resize",
  "width": 1280,
  "height": 720
}
```

**Fields:**
- `msg` (string): always `"window_resize"`
- `width` (int): requested window width in pixels
- `height` (int): requested window height in pixels

When the player is fullscreen this message is not sent; instead the DM adjusts its `camera_update` zoom/position to reflect the zoom change.

- Viewport resize notification (display -> DM)

Sent by a display peer on initial connection (as part of the `display` handshake) and whenever the window is resized. The DM uses this to keep its indicator box in sync.

**Handshake** (`type: "display"`) and **resize** (`type: "viewport_resize"`) now both carry:
- `viewport_width` (float): current pixel width
- `viewport_height` (float): current pixel height
- `fullscreen` (bool): whether the window is in fullscreen mode. The DM uses this to choose between physical resize (windowed) and zoom-only (fullscreen) when the indicator is dragged.
```

## Backpressure & chunking rules

- Large or countably unbounded payloads (map tiles, full fog bitmaps, big asset bundles) MUST be chunked.
- Chunking model:
  - A chunked transfer begins with a `chunk_start` control message identifying `transfer_id`, `total_chunks` (optional), `content_type` and metadata.
  - Each chunk is sent as a `chunk` message with `transfer_id`, `index` (0-based), and `data` (base64 or binary-capable transport). Example:

```json
{
  "type": "chunk",
  "msg_id": "s-ch-1",
  "payload": { "transfer_id": "t123", "index": 0, "data_b64": "..." }
}
```

  - The sender SHOULD include checksums (e.g., SHA256 hex) in `chunk_start` or `chunk_end` messages for integrity verification.
  - Receivers MUST acknowledge chunks or the transfer using `chunk_ack` messages. Lack of `chunk_ack` within a reasonable timeout signals backpressure and the sender should slow or pause transmission.
  - If `total_chunks` is not known up-front, the sender SHOULD include an explicit `chunk_end` message with final metadata.

- Backpressure guidance:
  - Use per-connection outstanding-chunk limits (e.g., max 3 unacked chunks) to avoid overwhelming clients.
  - Respect explicit `pause`/`resume` control messages from the receiver.
  - For very large assets, prefer out-of-band delivery (HTTP range, separate CDN) with an in-protocol pointer.

## Versioning and compatibility

- Message `version` is optional but recommended for schema evolution.
- Compatibility rules:
  - Adding optional fields is backwards-compatible.
  - Removing or renaming fields is breaking and requires a version bump and clear migration steps.
  - If a receiver does not understand a `type`, it SHOULD ignore it and log a warning. If the type is critical, use `error` responses.
  - The DM should include a server-side `protocol_version` in the handshake response.

## Security & robustness

- Authentication and authorization:
  - All connections MUST be authenticated before accepting control messages. Use mTLS, tokens, or WebSocket subprotocol with signed tokens as appropriate.
  - Validate sender permissions for sensitive actions (fog reveal, map modifications).

- Input validation:
  - Never trust client-provided coordinates or ids; validate ranges and types server-side.
  - Enforce maximum payload sizes and reject oversized messages with clear `error` responses.

- Integrity and replay protection:
  - For critical operations, include monotonic sequence numbers or nonces and reject replayed messages.
  - Use checksums or signatures for large transfers.

- Failure handling:
  - For malformed messages, respond with an `error` message including `msg_id`/`in_reply_to` when available.
  - For transient failures, use retry with exponential backoff; avoid silent drops for important user actions.

## Examples and quick patterns

- Simple request/response

```json
{
  "type": "ping",
  "msg_id": "c-ping-1"
}
```

Response

```json
{
  "type": "pong",
  "in_reply_to": "c-ping-1",
  "msg_id": "s-pong-1",
  "payload": { "server_time": "2026-03-18T12:35:00Z" }
}
```

---

If more detailed per-message schemas are needed (types, required/optional fields, value ranges), consider adding a machine-readable JSON Schema or OpenAPI fragment referenced from this file.
Client → Server: `input` packet

- **Required fields**:
  - `type`: must be the string `"input"`
  - `x`: numeric (float or int) — horizontal axis in range `[-1.0, 1.0]`
  - `y`: numeric (float or int) — vertical axis in range `[-1.0, 1.0]`

- **Optional fields**:
  - `player_id`: string token identifying the input source (player id, input_id, or player name). If omitted, server will attempt to resolve by peer binding.

- **Types and ranges**:
  - `x` and `y` must be JSON numbers. The server will coerce to float and clamp values into `[-1.0, 1.0]`. Non-numeric or NaN/Inf values are rejected.

- **Example valid packet**:

```
{"type":"input","x":0.5,"y":-0.25,"player_id":"player-123"}
```

- **Server acceptance behavior**:
  - On receipt the server parses JSON and checks `type == "input"`.
  - If `x` or `y` are missing the server ignores the packet and logs a debug warning.
  - If `x` or `y` are present but non-numeric (or NaN/Inf), the server ignores the packet and logs a debug warning.
  - If fields are present and numeric, the server clamps `x`/`y` to `[-1.0,1.0]`, resolves `player_id` (or uses the peer binding), and forwards the vector to the Input service.
# Network Protocols

Display handshake
-----------------

When a display client connects to the DM WebSocket server it sends a JSON
handshake packet to identify itself. The handshake MUST include `type: "display"`.

Optional fields
- `role` (string, optional): a free-form identifier describing the display
  client's role. Examples include `player_window`, `gm_dashboard`, or any
  environment-specific tag. The server treats `role` as informational only:
  - The DM host will log the role when received.
  - The role may be stored in peer metadata for diagnostics and UI features.
  - The role does NOT affect the canonical peer classification — peers are
    still classified as display peers when `type == "display"` regardless of
    `role`.

Other common handshake fields
- `viewport_width`, `viewport_height`: numeric viewport size reported by the
  display client.

Example handshake:

```json
{
  "type": "display",
  "role": "player_window",
  "viewport_width": 1920,
  "viewport_height": 1080
}
```

Notes
- The `role` field is optional; servers and clients should handle its absence
  gracefully.
# Network Protocols

This document describes the JSON-over-WebSocket protocol used between the DM host
and display/player clients.

## Versioning and compatibility

- Each top-level message MAY contain an integer `protocol_version` field.
- The current server default version is `1`.
- Servers SHOULD accept messages without a `protocol_version` field and treat them
  as version `1` for backward compatibility.
- If a server receives a message with `protocol_version` present and not equal
  to `1`, it SHOULD log a warning but continue processing the message.

When introducing incompatible protocol changes, increment the `protocol_version`
and publish migration notes here so clients can adapt gracefully.

## Message types

See code comments and `scripts/protocols` for detailed message schemas.

---

## Token messages (DM → display)

Token messages are broadcast by the DM process to all connected display clients
whenever the visible token set changes.  Display clients are **render-only** —
they never send token mutations back to the DM.

### `token_state` — full snapshot

Sent on initial connect and after every map load.  Contains the complete list of
tokens currently visible to players (`is_visible_to_players == true`).

```json
{
  "msg": "token_state",
  "tokens": [
    {
      "id": "1714000000_4028",
      "label": "Iron Door",
      "category": 0,
      "world_pos": { "x": 320.0, "y": 480.0 },
      "is_visible_to_players": true,
      "perception_dc": -1,
      "autopause": false,
      "pause_on_interact": false,
      "notes": "",
      "icon_key": ""
    }
  ]
}
```

**Fields:**
- `tokens` (Array): zero or more serialised `TokenData` objects (visible tokens only).

---

### `token_added` — single token revealed or created

Sent when the DM places a new token that is immediately visible, or toggles an
existing token from hidden → visible.

```json
{
  "msg": "token_added",
  "token": { "id": "…", "label": "Goblin Scout", "category": 4, "world_pos": { "x": 640.0, "y": 320.0 }, "is_visible_to_players": true, "perception_dc": -1, "autopause": false, "pause_on_interact": false, "notes": "", "icon_key": "" }
}
```

---

### `token_removed` — token hidden or deleted

Sent when the DM deletes a token or toggles it from visible → hidden.

```json
{
  "msg": "token_removed",
  "token_id": "1714000000_4028"
}
```

---

### `token_moved` — position update

Sent when the DM drags a visible token to a new world position.

```json
{
  "msg": "token_moved",
  "token_id": "1714000000_4028",
  "world_pos": { "x": 400.0, "y": 512.0 }
}
```

---

### `token_updated` — metadata change

Sent when the DM edits a visible token's label, category, or other non-position
fields via the token editor popup.

```json
{
  "msg": "token_updated",
  "token": { "id": "…", "label": "Trapped Chest", "category": 1, "world_pos": { "x": 200.0, "y": 300.0 }, "is_visible_to_players": true, "perception_dc": 15, "autopause": false, "pause_on_interact": true, "notes": "Deals 2d6 piercing on trigger.", "icon_key": "" }
}
```

---

### `TokenCategory` enum reference

| Value | Name |
|---|---|
| 0 | DOOR |
| 1 | TRAP |
| 2 | HIDDEN_OBJECT |
| 3 | SECRET_PASSAGE |
| 4 | MONSTER |
| 5 | EVENT |
| 6 | NPC |
| 7 | GENERIC |
