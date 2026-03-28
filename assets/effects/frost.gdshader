shader_type canvas_item;

// ---------------------------------------------------------------------------
// frost.gdshader — Procedural frost/ice effect.
//
// Voronoi/cellular noise for crystalline ice crack patterns.
// Soft drifting snowflakes via layered animated noise dots.
// Blue-white-cyan palette with subtle shimmer. No fade-in/out.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform int shape_mode = 0; // 0 = full quad (circle/line), 1 = cone mask

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash2(i + neighbor);
			point = 0.5 + 0.5 * sin((TIME + time_offset) * 0.3 + 6.2831 * point);
			float d = length(neighbor + point - f);
			min_dist = min(min_dist, d);
		}
	}
	return min_dist;
}

float voronoi_edges(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist = 1.0;
	float second_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash2(i + neighbor);
			point = 0.5 + 0.5 * sin((TIME + time_offset) * 0.2 + 6.2831 * point);
			float d = length(neighbor + point - f);
			if (d < min_dist) {
				second_dist = min_dist;
				min_dist = d;
			} else if (d < second_dist) {
				second_dist = d;
			}
		}
	}
	return second_dist - min_dist;
}

// Soft round snowflake layer — returns brightness for one layer of drifting flakes.
float snowflake_layer(vec2 uv, float t, float scale, float drift_speed, float seed) {
	// Drift downward + slight horizontal sway
	vec2 drift_uv = uv * scale;
	drift_uv.y += t * drift_speed;
	drift_uv.x += sin(t * 0.7 + seed + uv.y * 2.0) * 0.3;

	// Cell-based: each grid cell may contain a flake
	vec2 cell_id = floor(drift_uv);
	vec2 cell_frac = fract(drift_uv);

	float flakes = 0.0;
	for (int cy = -1; cy <= 1; cy++) {
		for (int cx = -1; cx <= 1; cx++) {
			vec2 neighbor = vec2(float(cx), float(cy));
			vec2 cid = cell_id + neighbor;
			// Random position within cell
			vec2 flake_pos = hash2(cid + seed);
			// Only ~40% of cells have a flake
			float exists = step(0.6, hash(cid * 17.3 + seed));
			vec2 diff = neighbor + flake_pos - cell_frac;
			float d = length(diff);
			// Soft circular flake with slight size variation
			float radius = 0.06 + hash(cid * 31.7 + seed) * 0.06;
			float flake = smoothstep(radius, radius * 0.3, d) * exists;
			// Twinkle
			float twinkle = 0.7 + 0.3 * sin(t * 4.0 + hash(cid) * 6.28);
			flakes += flake * twinkle;
		}
	}
	return flakes;
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	float dist = length(uv);
	float t = TIME + time_offset;

	// Crystalline patterns (unchanged — the ice cracks)
	vec2 cell_uv = UV * 6.0;
	float cells = voronoi(cell_uv);
	float edges = voronoi_edges(cell_uv);

	// Ice crystal pattern: bright edges, darker cells
	float crystal = smoothstep(0.0, 0.08, edges) * 0.6 + (1.0 - cells) * 0.4;
	crystal *= intensity;

	// Colour: deep blue → cyan → white
	vec3 col = mix(vec3(0.1, 0.3, 0.7), vec3(0.5, 0.8, 1.0), crystal);
	col = mix(col, vec3(0.9, 0.95, 1.0), smoothstep(0.6, 1.0, crystal));

	// Drifting snowflakes — two layers at different scales/speeds for depth
	float snow1 = snowflake_layer(UV, t, 8.0, 0.4, 0.0);
	float snow2 = snowflake_layer(UV, t, 12.0, 0.6, 47.3);
	float snow = (snow1 + snow2 * 0.7) * 0.5;

	// Snow is bright white, additive on top of ice
	col += vec3(0.9, 0.95, 1.0) * snow;

	col *= color_tint.rgb;

	// Circular boundary
	float boundary = 1.0 - smoothstep(0.7, 1.0, dist);

	float alpha = clamp(crystal + snow * 0.8, 0.0, 1.0) * boundary * progress * color_tint.a;

	// Cone mask
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col, alpha);
}
