extends RefCounted
class_name GameStateModel

## GameState data model.
##
## Owns the authoritative runtime state for player locks, positions, and
## window registrations. Held by GameStateManager and shared with
## GameStateService via injection before _ready() runs.

var player_locked: Dictionary = {}
var player_positions: Dictionary = {}
var windows: Array = []
