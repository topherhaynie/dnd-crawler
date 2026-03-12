extends Node

# ---------------------------------------------------------------------------
# DMWindow — root controller for the DM's window.
# Hosts the map view (full visibility), DM UI panels, editor/play mode
# controls, and the notification queue. Expanded each phase.
# ---------------------------------------------------------------------------

func _ready() -> void:
	print("DMWindow: ready")
