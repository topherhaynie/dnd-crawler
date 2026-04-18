extends SubViewportContainer
class_name DiceRenderer3D

# ---------------------------------------------------------------------------
# DiceRenderer3D — 3D physics-based dice rolling renderer.
#
# A self-contained SubViewportContainer that:
#   1. Manages a SubViewport with a Node3D scene (camera, light, table)
#   2. Spawns RigidBody3D dice from DiceMeshFactory
#   3. Applies random impulse + torque to simulate a throw
#   4. Polls until all dice settle (velocity < threshold)
#   5. Reads the top face via dot-product of face normals with Vector3.UP
#   6. Emits `roll_finished` with the results
#
# Lifecycle: create once, call `start_roll(groups)` each time.
# The renderer shows itself, animates, emits result, then hides.
# ---------------------------------------------------------------------------

signal roll_finished(results: Array) ## Array[Dictionary] — [{sides, values: Array[int]}]

# ── Tunables ────────────────────────────────────────────────────────────

const SETTLE_THRESHOLD: float = 0.05 ## m/s — linear + angular
const SETTLE_FRAMES: int = 10 ## consecutive frames below threshold
const MAX_SETTLE_TIME: float = 5.0 ## seconds — safety timeout
const THROW_IMPULSE_MIN: float = 1.0
const THROW_IMPULSE_MAX: float = 2.5
const THROW_TORQUE_MIN: float = 4.0
const THROW_TORQUE_MAX: float = 10.0
const TABLE_SIZE: float = 6.0
const WALL_HEIGHT: float = 4.0
const SPAWN_Y: float = 1.5
const DIE_SCALE: float = 0.7
const CAMERA_Y_BASE: float = 3.5 ## camera height for 1-4 dice
const CAMERA_Y_PER_DIE: float = 0.15 ## extra height per die beyond 4
const CAMERA_Y_MAX: float = 7.0

# ── State ───────────────────────────────────────────────────────────────

var _viewport: SubViewport = null
var _world_root: Node3D = null
var _camera: Camera3D = null
var _dice_bodies: Array[RigidBody3D] = []
var _dice_meta: Array[Dictionary] = [] ## {sides, face_normals, face_values, body}
var _rolling: bool = false
var _settle_counter: int = 0
var _elapsed: float = 0.0


func _ready() -> void:
	_build_scene()
	visible = false
	stretch = true
	custom_minimum_size = Vector2i(480, 360)
	# Disable rendering until a roll starts
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	if not _rolling:
		return
	_elapsed += delta
	if _elapsed > MAX_SETTLE_TIME:
		_finish_roll()
		return
	if _all_settled():
		_settle_counter += 1
		if _settle_counter >= SETTLE_FRAMES:
			_finish_roll()
	else:
		_settle_counter = 0


## Start a new roll.
## `groups` — Array of {count: int, sides: int} describing which dice to roll.
## e.g. [{count: 2, sides: 8}, {count: 1, sides: 20}]
func start_roll(groups: Array) -> void:
	_clear_dice()
	_rolling = true
	_settle_counter = 0
	_elapsed = 0.0
	visible = true
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Spawn dice — grid pattern, camera adapts to count
	var total: int = _total_dice(groups)
	var cols: int = ceili(sqrt(float(total)))
	var rows: int = ceili(float(total) / float(cols))

	# Adjust camera height so all dice (plus scatter room) stay in view
	var cam_y: float = clampf(
		CAMERA_Y_BASE + float(maxi(total - 4, 0)) * CAMERA_Y_PER_DIE,
		CAMERA_Y_BASE, CAMERA_Y_MAX,
	)
	_camera.position.y = cam_y

	# Visible half-extent at floor level: cam_y * tan(fov/2)
	var vis_half: float = cam_y * tan(deg_to_rad(_camera.fov * 0.5))
	# Leave margin so dice bounce room stays in view
	var usable_half: float = vis_half * 0.65
	# Spacing: fill the usable area but cap min distance so dice don't overlap
	var grid_span: float = maxf(float(maxi(cols, rows) - 1), 1.0)
	var spacing: float = clampf(usable_half * 2.0 / grid_span, DIE_SCALE * 1.3, 1.2)
	var grid_w: float = float(cols - 1) * spacing
	var grid_h: float = float(rows - 1) * spacing

	var idx: int = 0
	for group: Dictionary in groups:
		var count: int = int(group.get("count", 1))
		var sides: int = int(group.get("sides", 6))
		for _i: int in range(count):
			@warning_ignore("integer_division")
			var row: int = idx / cols
			var col: int = idx % cols
			var spawn_pos := Vector3(
				- grid_w * 0.5 + float(col) * spacing + randf_range(-0.08, 0.08),
				SPAWN_Y + randf_range(0.0, 0.3),
				- grid_h * 0.5 + float(row) * spacing + randf_range(-0.08, 0.08),
			)
			_spawn_die(sides, spawn_pos)
			idx += 1


## Resize the render viewport.
## With stretch = true the SubViewport follows the container size,
## so we adjust the container's minimum size instead.
func set_render_size(sz: Vector2i) -> void:
	custom_minimum_size = sz


# ── Scene setup ─────────────────────────────────────────────────────────

func _build_scene() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.physics_object_picking = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = true
	add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "DiceWorld"
	_viewport.add_child(_world_root)

	# Camera — top-down looking at the table centre
	_camera = Camera3D.new()
	_camera.position = Vector3(0, CAMERA_Y_BASE, 0)
	_camera.rotation_degrees = Vector3(-90, 0, 0)
	_camera.fov = 55.0
	_camera.current = true
	_world_root.add_child(_camera)

	# Light — nearly overhead to minimise shadow spread
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-75, 30, 0)
	light.shadow_enabled = true
	light.light_energy = 1.0
	_world_root.add_child(light)

	# Ambient fill
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.08, 0.12)
	environment.ambient_light_color = Color(0.35, 0.35, 0.4)
	environment.ambient_light_energy = 0.8
	env.environment = environment
	_world_root.add_child(env)

	# Table (floor)
	_add_static_plane(Vector3.ZERO, Vector3(TABLE_SIZE, 0.1, TABLE_SIZE), Color(0.18, 0.14, 0.1))

	# Invisible containment walls (collision only — no mesh to cast shadows)
	var half: float = TABLE_SIZE * 0.5
	_add_collision_wall(Vector3(0, WALL_HEIGHT * 0.5, -half), Vector3(TABLE_SIZE, WALL_HEIGHT, 0.1))
	_add_collision_wall(Vector3(0, WALL_HEIGHT * 0.5, half), Vector3(TABLE_SIZE, WALL_HEIGHT, 0.1))
	_add_collision_wall(Vector3(-half, WALL_HEIGHT * 0.5, 0), Vector3(0.1, WALL_HEIGHT, TABLE_SIZE))
	_add_collision_wall(Vector3(half, WALL_HEIGHT * 0.5, 0), Vector3(0.1, WALL_HEIGHT, TABLE_SIZE))


func _add_static_plane(pos: Vector3, extents: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	_world_root.add_child(body)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extents
	col.shape = box
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = extents
	mesh_inst.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)


func _add_collision_wall(pos: Vector3, extents: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	_world_root.add_child(body)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extents
	col.shape = box
	body.add_child(col)


# ── Dice spawning ───────────────────────────────────────────────────────

func _spawn_die(sides: int, pos: Vector3) -> void:
	var info: Dictionary = DiceMeshFactory.create_die(sides)
	var scene_root: Node3D = info.get("scene_root") as Node3D
	var shape: ConvexPolygonShape3D = info.get("shape") as ConvexPolygonShape3D
	var face_normals: Array = info.get("face_normals", []) as Array
	var face_values: Array = info.get("face_values", []) as Array

	if scene_root == null or shape == null:
		push_error("DiceRenderer3D: failed to create die for d%d" % sides)
		return

	var body := RigidBody3D.new()
	body.position = pos
	# Random initial rotation
	body.rotation = Vector3(
		randf_range(0, TAU),
		randf_range(0, TAU),
		randf_range(0, TAU),
	)
	body.mass = 0.3
	body.physics_material_override = _create_die_physics_material()

	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3.ONE * DIE_SCALE
	body.add_child(col)

	# Add the .glb scene (body + numbers meshes) as a visual child
	scene_root.scale = Vector3.ONE * DIE_SCALE
	body.add_child(scene_root)

	_world_root.add_child(body)

	# Apply random impulse + torque
	var impulse := Vector3(
		randf_range(-0.3, 0.3),
		randf_range(-1.0, -0.5),
		randf_range(-0.3, 0.3),
	).normalized() * randf_range(THROW_IMPULSE_MIN, THROW_IMPULSE_MAX)
	body.apply_central_impulse(impulse)

	var torque := Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
	).normalized() * randf_range(THROW_TORQUE_MIN, THROW_TORQUE_MAX)
	body.apply_torque_impulse(torque)

	_dice_bodies.append(body)
	_dice_meta.append({
		"sides": sides,
		"face_normals": face_normals,
		"face_values": face_values,
		"body": body,
	})


func _create_die_physics_material() -> PhysicsMaterial:
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.3
	mat.friction = 0.6
	return mat


# ── Settlement check ────────────────────────────────────────────────────

func _all_settled() -> bool:
	for body: RigidBody3D in _dice_bodies:
		if not is_instance_valid(body):
			continue
		var lin: float = body.linear_velocity.length()
		var ang: float = body.angular_velocity.length()
		if lin > SETTLE_THRESHOLD or ang > SETTLE_THRESHOLD:
			return false
	return true


# ── Result reading ──────────────────────────────────────────────────────

func _finish_roll() -> void:
	_rolling = false
	var results: Array = _read_all_results()
	roll_finished.emit(results)
	# Hide after a brief pause so the user sees the final state
	var tw: Tween = create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(_hide_after_roll)


func _hide_after_roll() -> void:
	visible = false
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_clear_dice()


func _read_all_results() -> Array:
	# Group results by sides so the caller gets one entry per dice group
	var by_sides: Dictionary = {} # sides → Array[int]
	for meta: Dictionary in _dice_meta:
		var sides: int = int(meta.get("sides", 6))
		var body: RigidBody3D = meta.get("body") as RigidBody3D
		var val: int = _read_top_face(body, meta)
		if not by_sides.has(sides):
			by_sides[sides] = []
		(by_sides[sides] as Array).append(val)

	var results: Array = []
	for sides_key: Variant in by_sides:
		results.append({"sides": int(sides_key), "values": by_sides[sides_key]})
	return results


func _read_top_face(body: RigidBody3D, meta: Dictionary) -> int:
	if not is_instance_valid(body):
		var face_vals: Array = meta.get("face_values", []) as Array
		return face_vals[0] if face_vals.size() > 0 else 1

	var face_normals: Array = meta.get("face_normals", []) as Array
	var face_values: Array = meta.get("face_values", []) as Array
	var sides: int = int(meta.get("sides", 6))
	var basis: Basis = body.global_transform.basis

	# d4 (tetrahedron) reads the BOTTOM face — the result is the value
	# mapped to whichever face points most downward (rests on the table).
	# All other dice read the TOP face (highest dot with UP).
	var seek_up: bool = sides != 4
	var best_dot: float = -2.0 if seek_up else 2.0
	var best_val: int = 1

	for fi: int in range(face_normals.size()):
		var local_normal: Vector3 = face_normals[fi] as Vector3
		var world_normal: Vector3 = basis * local_normal
		var dot: float = world_normal.dot(Vector3.UP)
		if seek_up:
			if dot > best_dot:
				best_dot = dot
				best_val = int(face_values[fi]) if fi < face_values.size() else 1
		else:
			if dot < best_dot:
				best_dot = dot
				best_val = int(face_values[fi]) if fi < face_values.size() else 1

	return best_val


# ── Cleanup ─────────────────────────────────────────────────────────────

func _clear_dice() -> void:
	for body: RigidBody3D in _dice_bodies:
		if is_instance_valid(body):
			body.queue_free()
	_dice_bodies.clear()
	_dice_meta.clear()
	_settle_counter = 0
	_elapsed = 0.0


func _total_dice(groups: Array) -> int:
	var total: int = 0
	for g: Dictionary in groups:
		total += int(g.get("count", 1))
	return total
