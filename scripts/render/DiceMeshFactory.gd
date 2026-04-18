extends RefCounted
class_name DiceMeshFactory

# ---------------------------------------------------------------------------
# DiceMeshFactory — loads Miltage "Tabletop Dice" .glb meshes (CC0) and
# provides collision shapes + face-normal-to-value mappings for the renderer.
#
# Each .glb contains two child meshes: the die body and extruded numbers.
# Face normals come from the mathematical primitive extracted via Blender;
# face values were visually verified from per-face renders.
#
# Usage:
#   var info: Dictionary = DiceMeshFactory.create_die(20)
#   # info.scene_root   — Node3D instance (body + numbers meshes)
#   # info.shape        — ConvexPolygonShape3D
#   # info.face_normals — Array[Vector3]
#   # info.face_values  — Array[int]
# ---------------------------------------------------------------------------

# ── .glb scene paths ────────────────────────────────────────────────────

const _PATH_D4: String = "res://assets/dice/d4.glb"
const _PATH_D6: String = "res://assets/dice/d6.glb"
const _PATH_D8: String = "res://assets/dice/d8.glb"
const _PATH_D10: String = "res://assets/dice/d10.glb"
const _PATH_D12: String = "res://assets/dice/d12.glb"
const _PATH_D20: String = "res://assets/dice/d20.glb"

static var _cache: Dictionary = {} ## path → PackedScene

# ── Face-value mappings (verified from Blender renders) ─────────────────
# Index order matches the unique-normal extraction from each die's
# _primitive object in dice_1.blend.  Opposite faces sum to max+1.

const _VALUES_D4: Array[int] = [1, 4, 3, 2]
const _VALUES_D6: Array[int] = [4, 5, 3, 2, 6, 1]
const _VALUES_D8: Array[int] = [6, 7, 5, 8, 4, 1, 3, 2]
const _VALUES_D10: Array[int] = [8, 3, 10, 9, 5, 7, 6, 2, 4, 1]
const _VALUES_D12: Array[int] = [12, 7, 9, 11, 3, 8, 10, 5, 6, 4, 2, 1]
const _VALUES_D20: Array[int] = [5, 13, 11, 4, 18, 15, 1, 9, 14, 2, 7, 19, 6, 20, 12, 17, 3, 16, 8, 10]

# ── Face normals from Blender primitive objects ─────────────────────────
# Extracted via bpy from each dN_primitive mesh's unique polygon normals.

static var _NORMALS_D4: Array[Vector3] = [
	Vector3(-0.069915, 0.376996, -0.923572),
	Vector3(0.024416, -0.998524, -0.048522),
	Vector3(0.837248, 0.33323, 0.433559),
	Vector3(-0.791749, 0.288297, 0.538534),
]

static var _NORMALS_D6: Array[Vector3] = [
	Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 1.0, 0.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.0, -1.0, 0.0),
	Vector3(0.0, 0.0, -1.0),
	Vector3(0.0, 0.0, 1.0),
]

static var _NORMALS_D8: Array[Vector3] = [
	Vector3(-0.501867, -0.675975, 0.539618),
	Vector3(0.160308, -0.912525, -0.376298),
	Vector3(-0.315645, -0.02964, -0.948414),
	Vector3(-0.97782, 0.206909, -0.032499),
	Vector3(0.315645, 0.02964, 0.948414),
	Vector3(0.97782, -0.206909, 0.032499),
	Vector3(0.501867, 0.675975, -0.539618),
	Vector3(-0.160308, 0.912525, 0.376298),
]

static var _NORMALS_D10: Array[Vector3] = [
	Vector3(-0.244279, 0.044535, 0.968682),
	Vector3(-0.955413, -0.259999, -0.139954),
	Vector3(0.023133, -0.763864, 0.644962),
	Vector3(-0.023132, 0.763864, -0.644962),
	Vector3(-0.764583, 0.6307, -0.13278),
	Vector3(-0.331902, -0.677316, -0.656569),
	Vector3(0.955413, 0.259998, 0.139954),
	Vector3(0.331902, 0.677316, 0.656569),
	Vector3(0.764583, -0.6307, 0.13278),
	Vector3(0.244279, -0.044535, -0.968682),
]

static var _NORMALS_D12: Array[Vector3] = [
	Vector3(0.036488, 0.012414, -0.999257),
	Vector3(0.012673, -0.888797, -0.458125),
	Vector3(0.865269, -0.274672, -0.419363),
	Vector3(0.544644, 0.726713, -0.41863),
	Vector3(-0.506109, 0.731478, -0.45694),
	Vector3(-0.834886, -0.266963, -0.481349),
	Vector3(0.506109, -0.731477, 0.45694),
	Vector3(0.834886, 0.266963, 0.481349),
	Vector3(-0.012673, 0.888798, 0.458125),
	Vector3(-0.865269, 0.274672, 0.419362),
	Vector3(-0.544644, -0.726713, 0.41863),
	Vector3(-0.036488, -0.012414, 0.999257),
]

static var _NORMALS_D20: Array[Vector3] = [
	Vector3(0.447267, -0.566274, -0.692305),
	Vector3(0.923829, -0.163264, -0.346243),
	Vector3(0.737324, 0.520373, -0.430772),
	Vector3(0.145495, 0.539873, -0.829077),
	Vector3(-0.03377, -0.131712, -0.990713),
	Vector3(0.11006, -0.971252, -0.211085),
	Vector3(0.881154, -0.319167, 0.348855),
	Vector3(0.579382, 0.78698, 0.212083),
	Vector3(-0.378216, 0.818531, -0.432387),
	Vector3(-0.668274, -0.268115, -0.693919),
	Vector3(0.378216, -0.818531, 0.432387),
	Vector3(0.668274, 0.268115, 0.693919),
	Vector3(-0.11006, 0.971252, 0.211085),
	Vector3(-0.881154, 0.319167, -0.348855),
	Vector3(-0.579382, -0.78698, -0.212083),
	Vector3(-0.145495, -0.539873, 0.829077),
	Vector3(0.03377, 0.131712, 0.990713),
	Vector3(-0.447267, 0.566274, 0.692305),
	Vector3(-0.923829, 0.163264, 0.346243),
	Vector3(-0.737325, -0.520373, 0.430772),
]


## Returns {scene_root: Node3D, shape: ConvexPolygonShape3D,
##          face_normals: Array[Vector3], face_values: Array[int]}
static func create_die(sides: int) -> Dictionary:
	var path: String
	var normals: Array[Vector3]
	var values: Array[int]

	match sides:
		4:
			path = _PATH_D4
			normals = _NORMALS_D4
			values = _VALUES_D4
		6:
			path = _PATH_D6
			normals = _NORMALS_D6
			values = _VALUES_D6
		8:
			path = _PATH_D8
			normals = _NORMALS_D8
			values = _VALUES_D8
		10:
			path = _PATH_D10
			normals = _NORMALS_D10
			values = _VALUES_D10
		12:
			path = _PATH_D12
			normals = _NORMALS_D12
			values = _VALUES_D12
		20:
			path = _PATH_D20
			normals = _NORMALS_D20
			values = _VALUES_D20
		_:
			path = _PATH_D6
			normals = _NORMALS_D6
			values = _VALUES_D6

	var scene: PackedScene = _load_cached(path)
	if scene == null:
		push_error("DiceMeshFactory: failed to load %s" % path)
		return {}

	var root: Node3D = scene.instantiate() as Node3D
	var shape: ConvexPolygonShape3D = _build_shape_from_scene(root)

	return {
		"scene_root": root,
		"shape": shape,
		"face_normals": normals,
		"face_values": values,
	}


static func _load_cached(path: String) -> PackedScene:
	if _cache.has(path):
		return _cache[path] as PackedScene
	var res: Variant = load(path)
	if res is PackedScene:
		_cache[path] = res
		return res as PackedScene
	return null


## Build ConvexPolygonShape3D from all MeshInstance3D vertices in the scene.
static func _build_shape_from_scene(root: Node3D) -> ConvexPolygonShape3D:
	var all_verts: PackedVector3Array = PackedVector3Array()
	for child: Node in root.get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for surf_idx: int in range(mi.mesh.get_surface_count()):
			var arrays: Array = mi.mesh.surface_get_arrays(surf_idx)
			if arrays.size() > Mesh.ARRAY_VERTEX:
				var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
				if verts is PackedVector3Array:
					var pv3: PackedVector3Array = verts as PackedVector3Array
					var xform: Transform3D = mi.transform
					for v: Vector3 in pv3:
						all_verts.append(xform * v)
	var shape := ConvexPolygonShape3D.new()
	shape.points = all_verts
	return shape
