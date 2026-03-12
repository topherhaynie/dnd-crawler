extends Node

# ---------------------------------------------------------------------------
# PlayerWindow — root controller for the shared Player / TV window.
# Hosts the map view with Fog of War, player sprites, and effect layers.
# No DM UI is shown here. Expanded each phase.
# ---------------------------------------------------------------------------

func _ready() -> void:
	print("PlayerWindow: ready")
