shader_type canvas_item;

// ---------------------------------------------------------------------------
// rain_of_fire.gdshader — Fire bombardment: random small fire pillars
// strike down across a circular area.
//
// Circle shape only. Each pillar is a short-lived column that appears
// at a random position, rises briefly, then fades — staggered in time.
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

float hash1(float p) {
	return fract(sin(p * 127.1) * 43758.5453123);
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
	for (int i = 0; i < 4; i++) {
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
	vec2 centered = (UV - 0.5) * 2.0;
	float dist = length(centered);
	float t = TIME + time_offset;

	// Soft circular boundary
	float boundary = 1.0 - smoothstep(0.85, 1.0, dist);

	// All pillars extend in one uniform direction: -Y in UV space.
	// The sprite is rotated so UV -Y aligns with the DM's drag direction.
	vec2 fire_dir = vec2(0.0, -1.0); // "up" in screen = -Y in UV
	vec2 fire_perp = vec2(1.0, 0.0);

	float total_flame = 0.0;
	vec3 total_col = vec3(0.0);

	const int NUM_PILLARS = 14;
	float cycle_duration = 0.45;

	for (int i = 0; i < NUM_PILLARS; i++) {
		float fi = float(i);

		// Stagger phase
		float phase_offset = hash1(fi * 31.7) * cycle_duration;
		float local_t = mod(t + phase_offset, cycle_duration);
		float life = local_t / cycle_duration;

		// Random base position within the circle for this lifecycle
		float cycle_id = floor((t + phase_offset) / cycle_duration);
		float bx = hash(vec2(fi * 13.3, cycle_id * 7.1)) * 1.2 - 0.6;
		float by = hash(vec2(cycle_id * 11.3, fi * 17.7)) * 1.2 - 0.6;
		vec2 base_pos = vec2(bx, by);
		if (length(base_pos) > 0.65) { continue; }

		// Pillar dimensions
		float pillar_length = 0.30 + hash1(fi * 3.3 + cycle_id) * 0.22;
		float pillar_width = 0.05 + hash1(fi * 5.3 + cycle_id) * 0.04;

		// Project pixel onto pillar local space (all same direction)
		vec2 delta = centered - base_pos;
		float along = dot(delta, fire_dir);
		float across = abs(dot(delta, fire_perp));

		// Cull outside bounds
		if (along < -pillar_width || along > pillar_length) { continue; }
		if (across > pillar_width * 2.5) { continue; }

		// Normalized: 0 = base, 1 = tip
		float py = clamp(along / pillar_length, 0.0, 1.0);

		// Width taper
		float width_at_py = pillar_width * mix(1.3, 0.2, py * py);
		float horiz_mask = 1.0 - smoothstep(width_at_py * 0.4, width_at_py, across);
		if (horiz_mask < 0.001) { continue; }

		float height_fade = 1.0 - py * 0.85;

		// Lifecycle — instant ignition, very brief burn
		float life_alpha = smoothstep(0.0, 0.04, life) * (1.0 - smoothstep(0.25, 1.0, life));

		// Fire noise scrolling along the pillar
		float px_norm = dot(delta, fire_perp) / max(width_at_py, 0.001);
		vec2 noise_uv = vec2(px_norm * 3.0, py * 6.0);
		noise_uv.y -= t * 6.0 + fi * 3.0;
		noise_uv.x += sin(t * 3.0 + fi + py * 4.0) * 0.4;

		float n = fbm(noise_uv);
		float core = exp(-px_norm * px_norm * 3.0) * 0.4 * height_fade;

		float flame = n * height_fade + core;
		flame = clamp(flame * 4.0 * intensity, 0.0, 1.0);

		float pillar_alpha = flame * horiz_mask * life_alpha;
		vec3 pillar_col = fire_palette(flame);

		total_flame += pillar_alpha;
		total_col += pillar_col * pillar_alpha;
	}

	// Stronger ambient ground glow
	float ground_glow = fbm(centered * 3.0 + vec2(t * 0.5, -t * 0.3)) * 0.2 * intensity;
	total_flame += ground_glow;
	total_col += fire_palette(ground_glow * 3.0) * ground_glow;

	// Normalise colour
	vec3 col = total_flame > 0.001 ? total_col / total_flame : vec3(0.0);
	col *= color_tint.rgb;

	float alpha = clamp(total_flame, 0.0, 1.0) * boundary * progress * color_tint.a;

	COLOR = vec4(col, alpha);
}
