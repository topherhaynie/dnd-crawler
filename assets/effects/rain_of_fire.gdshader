shader_type canvas_item;

// ---------------------------------------------------------------------------
// rain_of_fire.gdshader — Fire bombardment: random small fire pillars
// strike down across a circular area.
//
// Circle shape only. Each pillar is a short-lived column that appears
// at a random position, rises briefly, then fades — staggered in time.
// Fire rendering shared with pillar_of_fire via pillar_fire_common.gdshaderinc.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform int shape_mode = 0;
uniform int palette_index = 0;

#include "res://assets/effects/pillar_fire_common.gdshaderinc"

float hash1(float p) {
	return fract(sin(p * 127.1) * 43758.5453123);
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
		float bx = _pf_hash(vec2(fi * 13.3, cycle_id * 7.1)) * 1.2 - 0.6;
		float by = _pf_hash(vec2(cycle_id * 11.3, fi * 17.7)) * 1.2 - 0.6;
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

		// Lifecycle — instant ignition, very brief burn
		float life_alpha = smoothstep(0.0, 0.04, life) * (1.0 - smoothstep(0.25, 1.0, life));

		// Fire rendering via shared pillar flame function
		float px_norm = dot(delta, fire_perp) / max(width_at_py, 0.001);
		float flame = compute_pillar_flame(px_norm, py, t, fi, intensity);

		float pillar_alpha = flame * horiz_mask * life_alpha;
		vec3 pillar_col = _pf_fire_palette(flame);

		total_flame += pillar_alpha;
		total_col += pillar_col * pillar_alpha;
	}

	// Stronger ambient ground glow
	float ground_glow = _pf_fbm(centered * 3.0 + vec2(t * 0.5, -t * 0.3)) * 0.2 * intensity;
	total_flame += ground_glow;
	total_col += _pf_fire_palette(ground_glow * 3.0) * ground_glow;

	// Normalise colour
	vec3 col = total_flame > 0.001 ? total_col / total_flame : vec3(0.0);
	col *= color_tint.rgb;

	float alpha = clamp(total_flame, 0.0, 1.0) * boundary * progress * color_tint.a;

	COLOR = vec4(col, alpha);
}
