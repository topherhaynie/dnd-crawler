extends RefCounted
class_name FogManager

## Typed manager for the fog-of-war service.
## Access via: get_node("/root/ServiceRegistry").fog.service

var service: IFogService = null
