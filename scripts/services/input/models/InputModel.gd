extends RefCounted
class_name InputModel

## Input data model.
##
## Mirrors the authoritative binding and per-player source-vector state from
## InputService. Held by InputManager; kept in sync after each coordination
## method call so callers can inspect bindings without going through the service.

var gamepad_bindings: Dictionary = {}
var source_vectors: Dictionary = {}
