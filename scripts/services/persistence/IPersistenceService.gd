extends Node
class_name IPersistenceService

const _GameSaveDataClass = preload("res://scripts/services/game_state/models/GameSaveData.gd")

## Protocol: IPersistenceService
##
## Base class for JSON file persistence and .sav bundle I/O.
## Extend this class for a concrete save/load implementation.

@warning_ignore("unused_signal")
signal persistence_changed(save_name: String)

# --- Legacy JSON saves (backward compat) -----------------------------------

func save_game(_save_name: String, _state: Dictionary) -> bool:
	push_error("IPersistenceService.save_game: not implemented")
	return false

func load_game(_save_name: String) -> Dictionary:
	push_error("IPersistenceService.load_game: not implemented")
	return {}

func list_saves() -> Array:
	push_error("IPersistenceService.list_saves: not implemented")
	return []

func delete_save(_save_name: String) -> bool:
	push_error("IPersistenceService.delete_save: not implemented")
	return false

func export_to_path(_save_name: String, _dest_path: String) -> bool:
	push_error("IPersistenceService.export_to_path: not implemented")
	return false

func copy_file(_from_path: String, _to_path: String) -> int:
	push_error("IPersistenceService.copy_file: not implemented")
	return -1

# --- .sav bundle I/O -------------------------------------------------------

func save_game_bundle(_bundle_path: String, _state: RefCounted, _fog_image: Image, _map_bundle_path: String) -> bool:
	push_error("IPersistenceService.save_game_bundle: not implemented")
	return false

func load_game_bundle(_bundle_path: String) -> Dictionary:
	push_error("IPersistenceService.load_game_bundle: not implemented")
	return {}

func list_save_bundles() -> Array:
	push_error("IPersistenceService.list_save_bundles: not implemented")
	return []

func delete_save_bundle(_save_name: String) -> bool:
	push_error("IPersistenceService.delete_save_bundle: not implemented")
	return false

# --- Map bundle enumeration & metadata --------------------------------------

func list_map_bundles() -> Array:
	push_error("IPersistenceService.list_map_bundles: not implemented")
	return []

func load_bundle_metadata(_bundle_path: String) -> Dictionary:
	push_error("IPersistenceService.load_bundle_metadata: not implemented")
	return {}

func generate_thumbnail(_image_path: String, _dest_path: String, _max_size: Vector2i) -> bool:
	push_error("IPersistenceService.generate_thumbnail: not implemented")
	return false

# --- Video conversion (ffmpeg CLI) ------------------------------------------

func is_ffmpeg_available() -> bool:
	push_error("IPersistenceService.is_ffmpeg_available: not implemented")
	return false

func convert_video_to_ogv(
	_src_path: String,
	_dest_path: String,
	_progress_file: String = "",
	_max_width: int = 1920,
	_fps: int = 30,
	_video_quality: int = 6,
	_audio_quality: int = 4,
) -> int:
	push_error("IPersistenceService.convert_video_to_ogv: not implemented")
	return -1

func probe_video_duration(_path: String) -> float:
	push_error("IPersistenceService.probe_video_duration: not implemented")
	return 0.0

func probe_video_dimensions(_path: String) -> Vector2i:
	push_error("IPersistenceService.probe_video_dimensions: not implemented")
	return Vector2i.ZERO

func generate_video_thumbnail(_src_video: String, _dest_png: String, _max_size: Vector2i) -> bool:
	push_error("IPersistenceService.generate_video_thumbnail: not implemented")
	return false
