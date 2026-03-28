shader_type canvas_item;

// ---------------------------------------------------------------------------
// pillar_of_fire.gdshader — Vertical column of fire rising along a line.
//
// Line tool only. UV.y=0 is the draw-start (base), UV.y=1 is the draw-end
// (top). Flames are hottest at the base and taper toward the top.
// Uses the same multi-palette system as fire.gdshader.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform int shape_mode = 0;
uniform int palette_index = 0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
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

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amp * noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return value;
}

vec3 fire_palette(float t) {
	vec3 col = vec3(0.0);
	if (palette_index == 1) {
		col = mix(col, vec3(0.3, 0.0, 0.0), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.7, 0.05, 0.05), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(1.0, 0.15, 0.1), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(1.0, 0.5, 0.4), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(1.0, 0.9, 0.85), smoothstep(0.8, 1.0, t));
	} else if (palette_index == 2) {
		col = mix(col, vec3(0.0, 0.3, 0.0), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.0, 0.65, 0.1), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(0.2, 0.9, 0.1), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(0.6, 1.0, 0.3), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(0.9, 1.0, 0.85), smoothstep(0.8, 1.0, t));
	} else if (palette_index == 3) {
		col = mix(col, vec3(0.0, 0.0, 0.4), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.0, 0.15, 0.8), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(0.1, 0.4, 1.0), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(0.4, 0.7, 1.0), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(0.85, 0.95, 1.0), smoothstep(0.8, 1.0, t));
	} else if (palette_index == 4) {
		col = mix(col, vec3(0.25, 0.0, 0.3), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.5, 0.0, 0.6), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(0.7, 0.15, 0.85), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(0.9, 0.4, 1.0), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(1.0, 0.85, 1.0), smoothstep(0.8, 1.0, t));
	} else if (palette_index == 5) {
		col = mix(col, vec3(0.4, 0.25, 0.0), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.7, 0.5, 0.0), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(1.0, 0.85, 0.0), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(1.0, 1.0, 0.4), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(1.0, 1.0, 0.9), smoothstep(0.8, 1.0, t));
	} else if (palette_index == 6) {
		col = mix(col, vec3(0.15, 0.08, 0.05), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.25, 0.12, 0.08), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(0.35, 0.15, 0.1), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(0.2, 0.1, 0.08), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(0.5, 0.2, 0.1), smoothstep(0.8, 1.0, t));
	} else {
		col = mix(col, vec3(0.5, 0.0, 0.0), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.9, 0.15, 0.0), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(1.0, 0.5, 0.0), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(1.0, 0.9, 0.2), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(1.0, 1.0, 0.9), smoothstep(0.8, 1.0, t));
	}
	return col;
}

void fragment() {
	vec2 uv = UV;
	uv.y = 1.0 - uv.y; // Flip: _apply_line maps UV.y=0 to draw-end; we need 0=base.
	float t = TIME + time_offset;

	// UV.y runs along the line: 0 = base (draw start), 1 = top (draw end).
	// UV.x = perpendicular: 0.5 is the centre of the pillar.

	// Width — linear taper, blunt top
	float width_at_y = mix(0.48, 0.30, uv.y);
	float dist_from_centre = abs(uv.x - 0.5);
	float pillar_mask = 1.0 - smoothstep(width_at_y * 0.5, width_at_y, dist_from_centre);

	// Height fade — mild, keeps fire visible along the full shaft
	float height_fade = 1.0 - uv.y * 0.5;

	// --- Spiral: treat x as angular position around a cylinder ---
	// Normalize across-pillar position to -1..1 within the current width
	float norm_x = (uv.x - 0.5) / max(width_at_y, 0.001);
	float angle = norm_x * 3.14159;

	// Primary spiral: moderate twist + rotation
	float spiral = angle + uv.y * 20.0 + t * 6.5;
	// Counter-rotating second layer
	float spiral2 = angle - uv.y * 14.0 + t * 4.5;

	// Noise sampled along spiral paths
	vec2 noise_uv = vec2(
		sin(spiral) * 3.0 + cos(spiral * 0.7) * 2.0,
		uv.y * 8.0 - t * 6.0
	);
	vec2 noise_uv2 = vec2(
		sin(spiral2) * 2.5 + cos(spiral2 * 0.5) * 3.0,
		uv.y * 6.0 - t * 4.5
	);

	float n1 = fbm(noise_uv);
	float n2 = fbm(noise_uv2 + vec2(4.3, 1.7));

	// Visible spiral arms — sharp bright bands wound around the column
	float arm1 = pow(sin(spiral * 2.5) * 0.5 + 0.5, 0.4);
	float arm2 = pow(sin(spiral2 * 2.0 + 2.0) * 0.5 + 0.5, 0.4);

	// Arms dominate; noise fills texture within them
	float n = mix(n1, n2, 0.3) * 0.25 + arm1 * 0.35 + arm2 * 0.25;

	// Deep dark lanes between arms — stronger at base where it washes out
	float base_boost = mix(1.0, 0.55, uv.y); // extra darkening at base
	float dark_lane = 1.0 - pow(arm1 * arm2, 0.2) * 0.75 * base_boost;
	n *= dark_lane;

	// Minimal core — prevent centre washout
	float core = exp(-norm_x * norm_x * 8.0) * height_fade * 0.05;

	float flame = n * height_fade + core;
	// Lower pre-clamp multiplier so darks stay dark, then triple S-curve
	flame = clamp(flame * 2.2 * intensity, 0.0, 1.0);
	flame = flame * flame * (3.0 - 2.0 * flame);
	flame = flame * flame * (3.0 - 2.0 * flame);
	flame = flame * flame * (3.0 - 2.0 * flame); // triple S-curve

	vec3 col = fire_palette(flame) * color_tint.rgb;
	float alpha = flame * pillar_mask * progress * color_tint.a;

	COLOR = vec4(col, alpha);
}
