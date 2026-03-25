extends RefCounted
class_name GameStateModel

const _GameSaveDataClass = preload("res://scripts/services/game_state/models/GameSaveData.gd")

## GameState data model.
##
## Owns the authoritative runtime state for player locks, positions, and
## window registrations. Held by GameStateManager and shared with
## GameStateService via injection before _ready() runs.

var player_locked: Dictionary = {}
var player_light_off: Dictionary = {}
var player_positions: Dictionary = {}
var windows: Array = []

## The currently-loaded game save (null when no save is active).
var active_save: RefCounted = null ## _GameSaveDataClass instance or null

## Player camera state (DM-controlled viewport for player displays).
## Authoritative at runtime; persisted into GameSaveData on save.
var player_camera_position: Vector2 = Vector2(960.0, 540.0)
var player_camera_zoom: float = 1.0
var player_camera_rotation: int = 0
