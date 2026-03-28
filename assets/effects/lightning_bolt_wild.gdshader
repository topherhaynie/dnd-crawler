shader_type canvas_item;

// ---------------------------------------------------------------------------
// lightning_bolt_wild.gdshader — Chaotic multi-fork lightning bolt effect.
//
// Multiple jagged bolts with aggressive noise displacement, forking branches,
// and rapid flickering. More stray arcs than the calm variant.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform int shape_mode = 0; // 0 = full quad (circle/line), 1 = cone mask

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

float bolt_shape(vec2 uv, float time_val, float freq_scale, float disp_scale) {
	// Multi-frequency noise displacement — more aggressive than calm variant
	float displacement = 0.0;
	displacement += noise(vec2(uv.y * 3.0 * freq_scale, time_val * 4.0)) * 0.30 * disp_scale;
	displacement += noise(vec2(uv.y * 7.0 * freq_scale, time_val * 7.0)) * 0.18 * disp_scale;
	displacement += noise(vec2(uv.y * 14.0 * freq_scale, time_val * 11.0)) * 0.10 * disp_scale;
	displacement += noise(vec2(uv.y * 28.0 * freq_scale, time_val * 15.0)) * 0.05 * disp_scale;

	float dist_from_bolt = abs(uv.x - 0.5 - displacement + 0.27);

	// Sharp core with wider glow
	float core = exp(-dist_from_bolt * 50.0);
	float glow = exp(-dist_from_bolt * 10.0);
	return core + glow * 0.4;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME + time_offset;

	// Aggressive flickering
	float flicker = 0.5 + 0.5 * sin(t * 40.0) * sin(t * 63.0 + 0.7);
	float flicker2 = 0.6 + 0.4 * sin(t * 27.0 + 2.1) * sin(t * 51.0);

	float total = 0.0;

	if (shape_mode == 1) {
		// --- CONE MODE: wild forking arcs fanning from apex ---
		float cone_half_w = uv.y * 0.5;
		if (abs(uv.x - 0.5) > cone_half_w) { discard; }

		// 6 main arcs spreading from apex
		const int NUM_ARCS = 6;
		float disp_strength = smoothstep(0.0, 0.15, uv.y);
		for (int i = 0; i < NUM_ARCS; i++) {
			float fi = float(i);
			float target_x = 0.5 + (fi / float(NUM_ARCS - 1) - 0.5) * 0.9;
			float bolt_center = mix(0.5, target_x, uv.y);

			float seed = fi * 7.3;
			float disp = 0.0;
			disp += (noise(vec2(uv.y * 3.0 + seed, t * 4.0 + fi * 2.5)) - 0.5) * 0.12;
			disp += (noise(vec2(uv.y * 8.0 + seed, t * 7.0 + fi * 3.5)) - 0.5) * 0.07;
			disp += (noise(vec2(uv.y * 16.0 + seed, t * 11.0 + fi * 1.5)) - 0.5) * 0.04;
			disp += (noise(vec2(uv.y * 30.0 + seed, t * 15.0 + fi * 4.0)) - 0.5) * 0.02;
			disp *= disp_strength;

			float dist = abs(uv.x - bolt_center - disp);
			float core = exp(-dist * 60.0);
			float glow = exp(-dist * 12.0);
			float arc = core + glow * 0.4;

			float arc_flicker = 0.4 + 0.6 * sin(t * 35.0 + fi * 13.0) * sin(t * 55.0 + fi * 9.0);
			total += arc * arc_flicker;
		}

		// Fork branches — diverge from mid-cone
		for (int j = 0; j < 3; j++) {
			float fj = float(j);
			float fork_start_y = 0.25 + fj * 0.2;
			float fork_vis = smoothstep(fork_start_y - 0.05, fork_start_y + 0.1, uv.y);
			float fork_target = 0.3 + fj * 0.2;
			float fork_center = mix(0.5, fork_target, (uv.y - fork_start_y) / (1.0 - fork_start_y));

			float seed_f = fj * 11.7 + 50.0;
			float disp_f = (noise(vec2(uv.y * 6.0 + seed_f, t * 5.0 + fj * 4.0)) - 0.5) * 0.08;
			disp_f += (noise(vec2(uv.y * 14.0 + seed_f, t * 9.0 + fj * 2.0)) - 0.5) * 0.04;

			float dist_f = abs(uv.x - fork_center - disp_f);
			float fork_arc = exp(-dist_f * 50.0) + exp(-dist_f * 10.0) * 0.3;
			fork_arc *= fork_vis * 0.5;
			fork_arc *= step(0.6, sin(t * 3.5 + fj * 5.0)); // intermittent blink
			total += fork_arc;
		}

		total *= intensity;
	} else {
		// --- LINE MODE: original multi-fork bolt ---
		float bolt = bolt_shape(uv, t, 1.0, 1.0);
		vec2 uv2 = uv;
		uv2.x = uv2.x * 0.9 + 0.08;
		float bolt2 = bolt_shape(uv2, t + 3.7, 1.2, 1.1) * 0.7;

		vec2 fork1_uv = uv;
		fork1_uv.x = fork1_uv.x * 0.7 + 0.25;
		fork1_uv.y = fork1_uv.y * 0.6 + 0.2;
		float fork1 = bolt_shape(fork1_uv, t + 1.5, 1.4, 1.3) * 0.45;
		fork1 *= smoothstep(0.2, 0.4, uv.y);

		vec2 fork2_uv = uv;
		fork2_uv.x = fork2_uv.x * 0.75 + 0.1;
		fork2_uv.y = fork2_uv.y * 0.5 + 0.35;
		float fork2 = bolt_shape(fork2_uv, t + 5.2, 1.6, 1.2) * 0.35;
		fork2 *= smoothstep(0.35, 0.55, uv.y);

		vec2 stray1_uv = uv;
		stray1_uv.x = stray1_uv.x * 0.6 + 0.35;
		float stray1 = bolt_shape(stray1_uv, t + 8.0, 2.0, 1.5) * 0.25;
		stray1 *= step(0.7, sin(t * 3.5 + 1.0));

		vec2 stray2_uv = uv;
		stray2_uv.x = stray2_uv.x * 0.65 + 0.05;
		float stray2 = bolt_shape(stray2_uv, t + 11.0, 1.8, 1.4) * 0.2;
		stray2 *= step(0.65, sin(t * 4.2 + 3.0));

		total = (bolt * flicker + bolt2 * flicker2 + fork1 + fork2 + stray1 + stray2) * intensity;
	}

	// Colour: white-hot core blending to electric blue, with purple edges
	vec3 col = mix(vec3(0.25, 0.4, 1.0), vec3(0.6, 0.7, 1.0), clamp(total * 0.8, 0.0, 1.0));
	col = mix(col, vec3(1.0, 1.0, 1.0), clamp(total * 1.2 - 0.3, 0.0, 1.0));
	col *= color_tint.rgb;

	// Edge fade — no apex fade in cone mode so lightning starts at the tip
	float edge_fade = smoothstep(1.0, 0.92, uv.y);
	if (shape_mode == 0) {
		edge_fade *= smoothstep(0.0, 0.08, uv.y);
	}

	// Cone boundary mask (soft edge — fade starts inside the boundary)
	if (shape_mode == 1) {
		float cone_half_w2 = uv.y * 0.5;
		float cone_edge = abs(uv.x - 0.5) - cone_half_w2;
		edge_fade *= 1.0 - smoothstep(-0.04, 0.0, cone_edge);
	}

	float alpha = clamp(total, 0.0, 1.0) * edge_fade * progress * color_tint.a;

	COLOR = vec4(col * total, alpha);
}
