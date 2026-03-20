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

## Ratio between fog-image pixels and world (map) pixels.
## 1.0 means fog resolution == map resolution (no downscaling).
## < 1.0 means the fog image is smaller than the map (e.g. 0.25 for a 4× downscale).
var fog_scale: float = 1.0
