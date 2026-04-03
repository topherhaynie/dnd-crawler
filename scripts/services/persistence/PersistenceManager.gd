extends RefCounted
class_name PersistenceManager

## Typed manager for the persistence service.
## Access via: get_node("/root/ServiceRegistry").persistence

var service: IPersistenceService = null


func save_game(save_name: String, state: Dictionary) -> bool:
	if service == null:
		return false
	return service.save_game(save_name, state)


func export_to_path(save_name: String, dest_path: String) -> bool:
	if service == null:
		return false
	return service.export_to_path(save_name, dest_path)


func delete_save(save_name: String) -> bool:
	if service == null:
		return false
	return service.delete_save(save_name)


func load_game(save_name: String) -> Dictionary:
	if service == null:
		return {}
	return service.load_game(save_name)


func copy_file(from_path: String, to_path: String) -> int:
	if service == null:
		return -1
	return service.copy_file(from_path, to_path)


func list_map_bundles() -> Array:
	if service == null:
		return []
	return service.list_map_bundles()


func list_save_bundles() -> Array:
	if service == null:
		return []
	return service.list_save_bundles()


func load_bundle_metadata(bundle_path: String) -> Dictionary:
	if service == null:
		return {}
	return service.load_bundle_metadata(bundle_path)


func generate_thumbnail(image_path: String, dest_path: String, max_size: Vector2i = Vector2i(400, 300)) -> bool:
	if service == null:
		return false
	return service.generate_thumbnail(image_path, dest_path, max_size)


func is_ffmpeg_available() -> bool:
	if service == null:
		return false
	return service.is_ffmpeg_available()


func convert_video_to_ogv(
	src_path: String,
	dest_path: String,
	progress_file: String = "",
	max_width: int = 1920,
	fps: int = 30,
	video_quality: int = 6,
	audio_quality: int = 4,
) -> int:
	if service == null:
		return -1
	return service.convert_video_to_ogv(src_path, dest_path, progress_file, max_width, fps, video_quality, audio_quality)


func probe_video_duration(path: String) -> float:
	if service == null:
		return 0.0
	return service.probe_video_duration(path)


func probe_video_dimensions(path: String) -> Vector2i:
	if service == null:
		return Vector2i.ZERO
	return service.probe_video_dimensions(path)


func generate_video_thumbnail(src_video: String, dest_png: String, max_size: Vector2i = Vector2i(400, 300)) -> bool:
	if service == null:
		return false
	return service.generate_video_thumbnail(src_video, dest_png, max_size)
