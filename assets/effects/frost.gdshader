shader_type canvas_item;

// ---------------------------------------------------------------------------
// frost.gdshader — Procedural frost/ice effect.
//
// Voronoi/cellular noise for crystalline ice patterns.
// Spreads outward from centre (controlled by time or progress).
// Blue-white-cyan palette with subtle shimmer.
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

float voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash2(i + neighbor);
			// Animate cell points slowly for shimmer
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

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	float dist = length(uv);

	// Frost spread — expands outward from centre over time
	float spread = clamp(mod((TIME + time_offset) * 0.3, 3.0), 0.0, 1.5);
	float spread_mask = 1.0 - smoothstep(spread * 0.5, spread * 0.5 + 0.3, dist);

	// Crystalline patterns
	vec2 cell_uv = UV * 6.0;
	float cells = voronoi(cell_uv);
	float edges = voronoi_edges(cell_uv);

	// Ice crystal pattern: bright edges, darker cells
	float crystal = smoothstep(0.0, 0.08, edges) * 0.6 + (1.0 - cells) * 0.4;
	crystal *= intensity;

	// Colour: deep blue → cyan → white
	vec3 col = mix(vec3(0.1, 0.3, 0.7), vec3(0.5, 0.8, 1.0), crystal);
	col = mix(col, vec3(0.9, 0.95, 1.0), smoothstep(0.6, 1.0, crystal));
	col *= color_tint.rgb;

	// Sparkle/shimmer
	float sparkle = hash(floor(UV * 30.0) + floor(vec2(TIME * 2.0)));
	sparkle = step(0.97, sparkle) * 0.5;

	col += vec3(sparkle);

	// Circular boundary
	float boundary = 1.0 - smoothstep(0.7, 1.0, dist);

	float alpha = clamp(crystal + sparkle, 0.0, 1.0) * boundary * spread_mask * progress * color_tint.a;

	// Cone mask: apex at UV (0.5, 0.0), full width at UV.y = 1.0
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col, alpha);
}
