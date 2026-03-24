extends RefCounted
class_name NetworkUtils

## Returns the best LAN IPv4 address for other devices to reach this machine.
## Prefers 192.168.* > 10.* > 172.16-31.* > any non-loopback IPv4.
## Returns "127.0.0.1" if no LAN address is found.
static func get_best_lan_ip() -> String:
	var addresses: PackedStringArray = IP.get_local_addresses()
	var best: String = ""
	var best_priority: int = 999

	for addr: String in addresses:
		# Skip IPv6 and loopback
		if ":" in addr:
			continue
		if addr.begins_with("127."):
			continue

		var priority: int = _lan_priority(addr)
		if priority < best_priority:
			best = addr
			best_priority = priority

	if best.is_empty():
		return "127.0.0.1"
	return best


static func _lan_priority(addr: String) -> int:
	if addr.begins_with("192.168."):
		return 0
	if addr.begins_with("10."):
		return 1
	# 172.16.0.0 – 172.31.255.255
	if addr.begins_with("172."):
		var parts: PackedStringArray = addr.split(".")
		if parts.size() >= 2:
			var second: int = parts[1].to_int()
			if second >= 16 and second <= 31:
				return 2
	return 3
