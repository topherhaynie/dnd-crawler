extends RefCounted
class_name NetworkManager

## Typed manager for the network service.
## Access via: get_node("/root/ServiceRegistry").network.service

var service: INetworkService = null
