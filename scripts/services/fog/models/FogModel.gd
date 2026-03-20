extends RefCounted
class_name FogModel

## FogModel — CPU-side fog-of-war state.
##
## Holds the authoritative history Image and configuration for one map session.
## GPU-side pipeline state (viewport handles, ping-pong indices, swap flags)
## remains exclusively in FogSystem.

var history_image: Image = null
var size: Vector2i = Vector2i.ZERO
var enabled: bool = false
var is_dm: bool = true
