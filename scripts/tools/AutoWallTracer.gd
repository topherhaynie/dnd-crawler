extends RefCounted
class_name AutoWallTracer

## AutoWallTracer — image-based wall polygon generation.
##
## Analyses a map Image to detect boundaries between content and background
## (transparent or solid-color) and returns simplified polygon outlines
## suitable for appending to MapData.wall_polygons.

enum DetectMode {ALPHA, COLOR}

# ── Public API ───────────────────────────────────────────────────────────────

## Trace wall boundaries in [param image] and return an array of wall polygons.
##
## By default the binary mask is [b]inverted[/b] so that wall / background
## pixels become the traced foreground.  Enclosed room regions are connected
## to the image border via narrow canals so the wall foreground contains no
## holes.  Each resulting wall piece traces as a simple polygon suitable for
## LightOccluder2D without covering the play area.
##
## [param config] dictionary keys (all optional):
##   mode          : DetectMode  (default ALPHA)
##   threshold     : float       (0.0–1.0, default 0.5)
##   sample_color  : Color       (required when mode == COLOR)
##   invert        : bool        (default true — invert mask so walls are
##                                traced; set false for raw content contours)
##   trace_scale   : float       (0.25–1.0, default 0.5)
##   epsilon       : float       (RDP tolerance in world px, default 2.0)
##   min_area      : float       (minimum enclosed area in world px², default 0.0 = auto)
##   min_points    : int         (minimum raw contour points, default 20)
func trace(image: Image, config: Dictionary = {}) -> Array:
	if image == null or image.is_empty():
		return []

	var mode: int = int(config.get("mode", DetectMode.ALPHA))
	var threshold: float = float(config.get("threshold", 0.5))
	var sample_color: Color = config.get("sample_color", Color.BLACK) as Color
	var invert: bool = bool(config.get("invert", true))
	var trace_scale: float = clampf(float(config.get("trace_scale", 0.5)), 0.1, 1.0)
	var epsilon: float = float(config.get("epsilon", 2.0))
	var min_area: float = float(config.get("min_area", 0.0))
	var min_points: int = int(config.get("min_points", 20))

	# --- Step 1: downscale ---
	var src: Image = image.duplicate() as Image
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var full_w: int = src.get_width()
	var full_h: int = src.get_height()
	var sw: int = maxi(1, roundi(full_w * trace_scale))
	var sh: int = maxi(1, roundi(full_h * trace_scale))
	if sw != full_w or sh != full_h:
		src.resize(sw, sh, Image.INTERPOLATE_BILINEAR)

	# --- Step 2: build binary mask ---
	var mask: PackedByteArray = _build_mask(src, mode, threshold, sample_color)

	# --- Step 2.5: invert mask and carve canals to eliminate holes ---
	if invert:
		_invert_and_carve(mask, sw, sh)

	# --- Step 3: trace contours ---
	var raw_contours: Array = _trace_contours(mask, sw, sh, min_points)

	# --- Step 4: simplify and scale back ---
	var inv_scale: float = 1.0 / trace_scale
	var result: Array = []
	for contour: Variant in raw_contours:
		var pts: PackedVector2Array = contour as PackedVector2Array
		var world_pts: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in pts:
			world_pts.append(p * inv_scale)
		var area: float = absf(_polygon_area(world_pts))
		if min_area > 0.0 and area < min_area:
			continue
		var simplified: PackedVector2Array = _rdp_simplify(world_pts, epsilon)
		if simplified.size() < 3:
			continue
		result.append(simplified)

	return result

# ── Binary mask ──────────────────────────────────────────────────────────────

func _build_mask(img: Image, mode: int, threshold: float, sample_color: Color) -> PackedByteArray:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)

	for y: int in range(h):
		for x: int in range(w):
			var c: Color = img.get_pixel(x, y)
			var is_foreground: bool = false
			if mode == DetectMode.ALPHA:
				is_foreground = c.a >= threshold
			else:
				# Color distance (Euclidean in RGB)
				var dr: float = c.r - sample_color.r
				var dg: float = c.g - sample_color.g
				var db: float = c.b - sample_color.b
				var dist: float = sqrt(dr * dr + dg * dg + db * db)
				# If pixel is far from the background color → foreground
				is_foreground = dist >= threshold
			if is_foreground:
				mask[y * w + x] = 1
	return mask

# ── Contour tracing (Moore Neighborhood) ────────────────────────────────────

## Trace all contours in the binary mask. Returns Array[PackedVector2Array].
func _trace_contours(mask: PackedByteArray, w: int, h: int, min_points: int) -> Array:
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(w * h)
	visited.fill(0)
	var contours: Array = []

	# Moore neighborhood offsets (8-connected, clockwise from left)
	var dx: Array[int] = [-1, -1, 0, 1, 1, 1, 0, -1]
	var dy: Array[int] = [0, -1, -1, -1, 0, 1, 1, 1]

	for y: int in range(h):
		for x: int in range(w):
			var idx: int = y * w + x
			if mask[idx] == 0 or visited[idx] == 1:
				continue
			# Check this is a boundary pixel (has at least one background neighbor or is on edge)
			if not _is_boundary(mask, w, h, x, y):
				continue

			var contour: PackedVector2Array = _trace_single_contour(mask, visited, w, h, x, y, dx, dy)
			if contour.size() >= min_points:
				contours.append(contour)

	return contours


func _is_boundary(mask: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	if x == 0 or y == 0 or x == w - 1 or y == h - 1:
		return true
	# Check 4-connected neighbors
	if mask[y * w + (x - 1)] == 0:
		return true
	if mask[y * w + (x + 1)] == 0:
		return true
	if mask[(y - 1) * w + x] == 0:
		return true
	if mask[(y + 1) * w + x] == 0:
		return true
	return false


func _trace_single_contour(mask: PackedByteArray, visited: PackedByteArray,
		w: int, h: int, start_x: int, start_y: int,
		dx: Array[int], dy: Array[int]) -> PackedVector2Array:
	var contour: PackedVector2Array = PackedVector2Array()

	# Find the initial backtrack direction: first background neighbor
	var start_dir: int = 0
	for i: int in range(8):
		var nx: int = start_x + dx[i]
		var ny: int = start_y + dy[i]
		if nx < 0 or ny < 0 or nx >= w or ny >= h or mask[ny * w + nx] == 0:
			start_dir = i
			break

	var cx: int = start_x
	var cy: int = start_y
	var backtrack_dir: int = start_dir
	var first_step: bool = true
	var max_steps: int = w * h * 2 # safety limit

	while max_steps > 0:
		max_steps -= 1
		contour.append(Vector2(cx, cy))
		visited[cy * w + cx] = 1

		# Search clockwise from (backtrack_dir + 1) for the next foreground pixel
		var found: bool = false
		var search_start: int = (backtrack_dir + 1) % 8
		for i: int in range(8):
			var dir: int = (search_start + i) % 8
			var nx: int = cx + dx[dir]
			var ny: int = cy + dy[dir]
			if nx >= 0 and ny >= 0 and nx < w and ny < h and mask[ny * w + nx] == 1:
				# Move to this neighbor
				backtrack_dir = (dir + 4) % 8 # opposite direction
				cx = nx
				cy = ny
				found = true
				break

		if not found:
			break # isolated pixel
		if not first_step and cx == start_x and cy == start_y:
			break # returned to start
		first_step = false

	return contour

# ── Ramer-Douglas-Peucker simplification ────────────────────────────────────

func _rdp_simplify(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() <= 3:
		return points
	# For closed polygons, operate on the full ring
	return _rdp_closed(points, epsilon)


func _rdp_closed(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var n: int = points.size()
	if n <= 3:
		return points

	# Find the two points furthest apart to anchor the split
	var max_dist: float = -1.0
	var idx_a: int = 0
	var idx_b: int = 0
	# Sample evenly spaced pairs for speed
	@warning_ignore("integer_division")
	var step: int = maxi(1, n / 40)
	for i: int in range(0, n, step):
		@warning_ignore("integer_division")
		for j: int in range(i + n / 4, mini(i + 3 * n / 4, n), step):
			var d: float = points[i].distance_squared_to(points[j])
			if d > max_dist:
				max_dist = d
				idx_a = i
				idx_b = j

	if idx_a > idx_b:
		var tmp: int = idx_a
		idx_a = idx_b
		idx_b = tmp

	# Split into two chains at idx_a and idx_b
	var chain1: PackedVector2Array = PackedVector2Array()
	for i: int in range(idx_a, idx_b + 1):
		chain1.append(points[i])
	var chain2: PackedVector2Array = PackedVector2Array()
	for i: int in range(idx_b, n):
		chain2.append(points[i])
	for i: int in range(0, idx_a + 1):
		chain2.append(points[i])

	# Simplify each open chain then merge (excluding duplicated endpoints)
	var s1: PackedVector2Array = _rdp_open(chain1, epsilon)
	var s2: PackedVector2Array = _rdp_open(chain2, epsilon)

	var result: PackedVector2Array = PackedVector2Array()
	for i: int in range(s1.size()):
		result.append(s1[i])
	for i: int in range(1, s2.size() - 1):
		result.append(s2[i])

	return result


func _rdp_open(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() <= 2:
		return points

	# Find the point with the maximum distance from the line start→end
	var start: Vector2 = points[0]
	var end: Vector2 = points[points.size() - 1]
	var max_dist: float = 0.0
	var max_idx: int = 0
	for i: int in range(1, points.size() - 1):
		var d: float = _point_line_dist(points[i], start, end)
		if d > max_dist:
			max_dist = d
			max_idx = i

	if max_dist > epsilon:
		var left: PackedVector2Array = PackedVector2Array()
		for i: int in range(0, max_idx + 1):
			left.append(points[i])
		var right: PackedVector2Array = PackedVector2Array()
		for i: int in range(max_idx, points.size()):
			right.append(points[i])
		var r_left: PackedVector2Array = _rdp_open(left, epsilon)
		var r_right: PackedVector2Array = _rdp_open(right, epsilon)
		var result: PackedVector2Array = PackedVector2Array()
		for i: int in range(r_left.size()):
			result.append(r_left[i])
		for i: int in range(1, r_right.size()):
			result.append(r_right[i])
		return result
	else:
		return PackedVector2Array([start, end])


func _point_line_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var proj: Vector2 = a + ab * t
	return p.distance_to(proj)

# ── Mask inversion + canal carving ───────────────────────────────────────────

## Invert the mask in-place so that wall / background pixels become foreground,
## then carve narrow (2 px) vertical canals from every enclosed room region to
## the image border.  After carving the wall foreground contains no holes and
## contour tracing produces simple polygons covering wall areas only.
func _invert_and_carve(mask: PackedByteArray, w: int, h: int) -> void:
	var total: int = w * h

	# --- Invert ---
	for i: int in range(total):
		mask[i] = 1 - mask[i]

	# --- Flood-fill exterior background from image border (4-connected) ---
	var exterior := PackedByteArray()
	exterior.resize(total)
	exterior.fill(0)
	var queue: Array[int] = []

	# Seed with border background pixels
	for x: int in range(w):
		if mask[x] == 0 and exterior[x] == 0:
			exterior[x] = 1
			queue.append(x)
		var ib: int = (h - 1) * w + x
		if mask[ib] == 0 and exterior[ib] == 0:
			exterior[ib] = 1
			queue.append(ib)
	for y: int in range(1, h - 1):
		var il: int = y * w
		if mask[il] == 0 and exterior[il] == 0:
			exterior[il] = 1
			queue.append(il)
		var ir: int = y * w + w - 1
		if mask[ir] == 0 and exterior[ir] == 0:
			exterior[ir] = 1
			queue.append(ir)

	var qi: int = 0
	while qi < queue.size():
		var idx: int = queue[qi]
		qi += 1
		@warning_ignore("integer_division")
		var px: int = idx % w
		@warning_ignore("integer_division")
		var py: int = idx / w
		if py > 0:
			var ni: int = idx - w
			if mask[ni] == 0 and exterior[ni] == 0:
				exterior[ni] = 1
				queue.append(ni)
		if py < h - 1:
			var ni: int = idx + w
			if mask[ni] == 0 and exterior[ni] == 0:
				exterior[ni] = 1
				queue.append(ni)
		if px > 0:
			var ni: int = idx - 1
			if mask[ni] == 0 and exterior[ni] == 0:
				exterior[ni] = 1
				queue.append(ni)
		if px < w - 1:
			var ni: int = idx + 1
			if mask[ni] == 0 and exterior[ni] == 0:
				exterior[ni] = 1
				queue.append(ni)

	# --- Carve canals from enclosed rooms to the exterior ---
	# Scan top→bottom.  The first enclosed pixel found for each room is its
	# topmost row, giving the shortest possible canal.
	for y: int in range(h):
		for x: int in range(w):
			var idx: int = y * w + x
			if mask[idx] != 0 or exterior[idx] != 0:
				continue
			# Enclosed background pixel — carve a 2 px canal upward.
			for cy: int in range(y - 1, -1, -1):
				var ci: int = cy * w + x
				if exterior[ci] == 1:
					break # reached exterior
				mask[ci] = 0
				if x + 1 < w:
					mask[cy * w + x + 1] = 0
			# Mark this room + canal as exterior via flood fill.
			var rq: Array[int] = [idx]
			exterior[idx] = 1
			var ri: int = 0
			while ri < rq.size():
				var ridx: int = rq[ri]
				ri += 1
				@warning_ignore("integer_division")
				var rx: int = ridx % w
				@warning_ignore("integer_division")
				var ry: int = ridx / w
				if ry > 0:
					var ni: int = ridx - w
					if mask[ni] == 0 and exterior[ni] == 0:
						exterior[ni] = 1
						rq.append(ni)
				if ry < h - 1:
					var ni: int = ridx + w
					if mask[ni] == 0 and exterior[ni] == 0:
						exterior[ni] = 1
						rq.append(ni)
				if rx > 0:
					var ni: int = ridx - 1
					if mask[ni] == 0 and exterior[ni] == 0:
						exterior[ni] = 1
						rq.append(ni)
				if rx < w - 1:
					var ni: int = ridx + 1
					if mask[ni] == 0 and exterior[ni] == 0:
						exterior[ni] = 1
						rq.append(ni)

# ── Geometry helpers ─────────────────────────────────────────────────────────

## Shoelace formula for polygon area (signed; positive = CCW).
func _polygon_area(pts: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = pts.size()
	for i: int in range(n):
		var j: int = (i + 1) % n
		area += pts[i].x * pts[j].y
		area -= pts[j].x * pts[i].y
	return area * 0.5
