extends Node
class_name ServiceRegistry

var _services: Dictionary = {}

func register(svc_name: String, instance: Object, required_methods: Array = []) -> void:
    assert(svc_name != "")
    assert(instance != null)
    if required_methods.size() > 0:
        for m in required_methods:
            assert(instance.has_method(m), "Service '%s' missing required method '%s'" % [svc_name, m])
    _services[svc_name] = instance

func get_service(svc_name: String) -> Object:
    return _services.get(svc_name, null)

func unregister(svc_name: String) -> void:
    _services.erase(svc_name)
