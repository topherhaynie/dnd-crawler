shader_type canvas_item;
render_mode unshaded;

// 0 = square, 1 = hex flat-top, 2 = hex pointy-top
uniform int grid_type : hint_range(0, 2) = 0;
uniform float cell_size : hint_range(1.0, 4096.0) = 64.0;
uniform float hex_radius : hint_range(1.0, 4096.0) = 40.0;
uniform vec2 grid_offset = vec2(0.0);
uniform vec4 grid_color : source_color = vec4(1.0, 1.0, 1.0, 0.25);
uniform float line_width : hint_range(0.5, 8.0) = 1.0;
uniform vec2 map_size = vec2(4096.0);

const float SQRT3   = 1.7320508;
const float SQRT3_2 = 0.8660254; // sqrt(3) / 2

// ── Square grid ──────────────────────────────────────────────────────────
float square_dist(vec2 pos) {
	vec2 cell = mod(pos, cell_size);
	float dx = min(cell.x, cell_size - cell.x);
	float dy = min(cell.y, cell_size - cell.y);
	return min(dx, dy);
}

// ── Hex signed distance functions ────────────────────────────────────────
// Returns signed distance to hex boundary (negative inside, positive outside).
float sd_hex_flat(vec2 p, float r) {
	float apothem = r * SQRT3_2;
	p = abs(p);
	return max(dot(p, vec2(SQRT3_2, 0.5)), p.y) - apothem;
}

float sd_hex_pointy(vec2 p, float r) {
	float apothem = r * SQRT3_2;
	p = abs(p);
	return max(dot(p, vec2(0.5, SQRT3_2)), p.x) - apothem;
}

// ── Cube-coordinate rounding (shared by both hex orientations) ───────────
vec3 cube_round(vec3 c) {
	vec3 r = round(c);
	vec3 d = abs(r - c);
	if (d.x > d.y && d.x > d.z)       r.x = -r.y - r.z;
	else if (d.y > d.z)                r.y = -r.x - r.z;
	else                                r.z = -r.x - r.y;
	return r;
}

// ── Nearest hex centre (flat-top) ────────────────────────────────────────
vec2 nearest_hex_flat(vec2 pos, float r) {
	// pixel → fractional axial
	float q = (2.0 / 3.0) * pos.x / r;
	float s = (-1.0 / 3.0 * pos.x + SQRT3 / 3.0 * pos.y) / r;
	vec3 cube = cube_round(vec3(q, s, -q - s));
	// axial → pixel
	return vec2(r * 1.5 * cube.x,
				r * (SQRT3_2 * cube.x + SQRT3 * cube.y));
}

// ── Nearest hex centre (pointy-top) ─────────────────────────────────────
vec2 nearest_hex_pointy(vec2 pos, float r) {
	float q = (SQRT3 / 3.0 * pos.x - 1.0 / 3.0 * pos.y) / r;
	float s = (2.0 / 3.0) * pos.y / r;
	vec3 cube = cube_round(vec3(q, s, -q - s));
	return vec2(r * (SQRT3 * cube.x + SQRT3_2 * cube.y),
				r * 1.5 * cube.y);
}

// ── Fragment ─────────────────────────────────────────────────────────────
void fragment() {
	vec2 pos = UV * map_size - grid_offset;
	float dist;

	if (grid_type == 0) {
		dist = square_dist(pos);
	} else if (grid_type == 1) {
		vec2 c = nearest_hex_flat(pos, hex_radius);
		dist = abs(sd_hex_flat(pos - c, hex_radius));
	} else {
		vec2 c = nearest_hex_pointy(pos, hex_radius);
		dist = abs(sd_hex_pointy(pos - c, hex_radius));
	}

	float half_lw = line_width * 0.5;
	float alpha = 1.0 - smoothstep(half_lw - 0.5, half_lw + 0.5, dist);
	COLOR = vec4(grid_color.rgb, grid_color.a * alpha);
}
