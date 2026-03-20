extends RefCounted
class_name ProfileManager

## Typed manager for the profile service.
## Access via: get_node("/root/ServiceRegistry").profile.service

var service: IProfileService = null
