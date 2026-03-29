extends RefCounted
class_name SelectableHit

## SelectableHit — lightweight result type returned by MapView._pick_selectable_at().
##
## Carries the winning selection layer, the entity id, and optional sub-info
## (resize/rotate handle index, measurement endpoint tag).  An empty hit has
## layer == -1; callers should test is_empty() before dispatching.

var layer: int = -1
var id: Variant = null
var handle: int = -1       ## resize/rotate handle index; -1 = body hit
var endpoint: String = ""  ## "start" or "end" for measurement endpoint hits


func is_empty() -> bool:
	return layer == -1


static func make(
		p_layer: int,
		p_id: Variant,
		p_handle: int = -1,
		p_endpoint: String = "") -> SelectableHit:
	var h := SelectableHit.new()
	h.layer = p_layer
	h.id = p_id
	h.handle = p_handle
	h.endpoint = p_endpoint
	return h
