shader_type canvas_item;

// ---------------------------------------------------------------------------
// ring_of_fire.gdshader — Procedural ring-of-fire effect.
//
// Renders animated flames in an annular ring pattern with a hollow center.
// Uses the same multi-palette system as fire.gdshader.
// Circle shape only.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform int shape_mode = 0; // 0 = full quad (circle), unused for ring
uniform int palette_index = 0; // 0=orange,1=red,2=green,3=blue,4=violet,5=yellow,6=black

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
		col = mix(col, vec3(0.02, 0.02, 0.03), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.05, 0.05, 0.06), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(0.10, 0.10, 0.12), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(0.25, 0.25, 0.28), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(0.40, 0.38, 0.44), smoothstep(0.8, 1.0, t));
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
	vec2 centered = (UV - 0.5) * 2.0;
	float dist = length(centered);
	float angle = atan(centered.y, centered.x);
	float t = TIME + time_offset;

	// Subtle slow rotation — spin the whole ring
	float rot_speed = 0.15;
	float rot_angle = t * rot_speed;
	float ca = cos(rot_angle);
	float sa = sin(rot_angle);
	centered = vec2(ca * centered.x - sa * centered.y,
	                sa * centered.x + ca * centered.y);
	dist = length(centered);
	angle = atan(centered.y, centered.x);

	// Annular ring mask — flames live between inner and outer radius.
	float inner_radius = 0.45;
	float outer_radius = 1.0;
	float ring_band = smoothstep(inner_radius - 0.08, inner_radius + 0.08, dist)
	                 * (1.0 - smoothstep(outer_radius - 0.25, outer_radius, dist));

	// Seamless tiling noise: sample on a circular path in noise-space so the
	// start and end of the ring meet without a seam.
	float loop_r = 1.3;
	float nx = cos(angle) * loop_r;
	float ny = sin(angle) * loop_r;
	vec2 noise_uv = vec2(nx + dist * 3.0, ny + dist * 3.0);

	// Flames scroll outward with slow angular drift
	float radial_scroll = dist * 4.0 - t * 3.0;
	noise_uv -= vec2(t * 0.9, t * 0.9);

	// Flicker wobble
	float wobble = sin(t * 1.2 + dist * 3.0) * 0.18;
	noise_uv.x += wobble;

	// Two-layer FBM for richer seamless flames
	float n = fbm(noise_uv) * 0.6 + fbm(noise_uv * 1.7 + vec2(radial_scroll, wobble)) * 0.4;

	// Bias intensity toward outer edge (flames lick outward from ring center)
	float radial_bias = smoothstep(inner_radius, outer_radius, dist);
	float flame = n * (0.5 + 0.5 * radial_bias);
	flame = clamp(flame * 2.2 * intensity, 0.0, 1.0);

	vec3 col = fire_palette(flame) * color_tint.rgb;
	float alpha = flame * ring_band * progress * color_tint.a;
	if (palette_index == 6) { alpha = min(alpha * 2.5, 1.0); }

	COLOR = vec4(col, alpha);
}
