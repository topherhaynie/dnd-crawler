shader_type canvas_item;

// ---------------------------------------------------------------------------
// lightning_bolt.gdshader — Procedural lightning bolt effect.
//
// Renders a jagged lightning bolt along the vertical axis using fractal noise
// displacement. Bright white-blue core with electric-blue glow falloff.
// Rapid flickering via high-frequency sine modulation.
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

float bolt_shape(vec2 uv, float time_val) {
	// Displace the centre line with multi-frequency noise
	float displacement = 0.0;
	displacement += noise(vec2(uv.y * 4.0, time_val * 3.0)) * 0.25;
	displacement += noise(vec2(uv.y * 8.0, time_val * 5.0)) * 0.12;
	displacement += noise(vec2(uv.y * 16.0, time_val * 8.0)) * 0.06;

	float dist_from_bolt = abs(uv.x - 0.5 - displacement + 0.22);

	// Sharp core with soft glow
	float core = exp(-dist_from_bolt * 60.0);
	float glow = exp(-dist_from_bolt * 12.0);
	return core + glow * 0.5;
}

void fragment() {
	vec2 uv = UV;

	float t = TIME + time_offset;
	// Flickering — rapid intensity variation
	float flicker = 0.7 + 0.3 * sin(t * 30.0) * sin(t * 47.0 + 1.3);

	float total = 0.0;

	if (shape_mode == 1) {
		// --- CONE MODE: multiple bolts fanning from apex to mouth ---
		// UV.y=0 is apex, UV.y=1 is open end.
		// Bolts originate from apex (0.5, 0) and spread to different X positions.
		float cone_half_w = uv.y * 0.5;
		if (abs(uv.x - 0.5) > cone_half_w) { discard; }

		const int NUM_ARCS = 4;
		for (int i = 0; i < NUM_ARCS; i++) {
			float fi = float(i);
			// Target X at mouth: evenly spread across cone width
			float target_x = 0.5 + (fi / float(NUM_ARCS - 1) - 0.5) * 0.8;
			// Bolt centre line interpolates from apex (0.5) to target
			float bolt_center = mix(0.5, target_x, uv.y);

			// Centered noise displacement — suppressed near apex so arcs converge at tip
			float disp_strength = smoothstep(0.0, 0.15, uv.y);
			float seed = fi * 7.3;
			float disp = 0.0;
			disp += (noise(vec2(uv.y * 4.0 + seed, t * 3.0 + fi * 2.0)) - 0.5) * 0.08;
			disp += (noise(vec2(uv.y * 10.0 + seed, t * 6.0 + fi * 3.0)) - 0.5) * 0.04;
			disp += (noise(vec2(uv.y * 20.0 + seed, t * 9.0 + fi * 1.5)) - 0.5) * 0.02;
			disp *= disp_strength;

			float dist = abs(uv.x - bolt_center - disp);
			float core = exp(-dist * 80.0);
			float glow = exp(-dist * 18.0);
			float arc = core + glow * 0.4;

			// Per-arc flicker
			float arc_flicker = 0.6 + 0.4 * sin(t * 25.0 + fi * 11.0) * sin(t * 41.0 + fi * 7.0);
			total += arc * arc_flicker;
		}
		total *= intensity;
	} else {
		// --- LINE MODE (default): single bolt along vertical ---
		float bolt = bolt_shape(uv, t);
		vec2 branch_uv = uv;
		branch_uv.x = branch_uv.x * 0.8 + 0.2;
		branch_uv.y = branch_uv.y * 0.7 + 0.15;
		float branch = bolt_shape(branch_uv, t + 2.0) * 0.4;
		total = (bolt + branch) * flicker * intensity;
	}

	// Colour: white-hot core blending to electric blue
	vec3 col = mix(vec3(0.3, 0.5, 1.0), vec3(1.0, 1.0, 1.0), clamp(total, 0.0, 1.0));
	col *= color_tint.rgb;

	// Edge fade — no apex fade in cone mode so lightning starts right at the tip
	float edge_fade = smoothstep(1.0, 0.9, uv.y);
	if (shape_mode == 0) {
		edge_fade *= smoothstep(0.0, 0.1, uv.y);
	}

	// Cone boundary mask (soft edge — fade starts inside the boundary)
	if (shape_mode == 1) {
		float cone_half_w = uv.y * 0.5;
		float cone_edge = abs(uv.x - 0.5) - cone_half_w;
		edge_fade *= 1.0 - smoothstep(-0.04, 0.0, cone_edge);
	}

	float alpha = clamp(total, 0.0, 1.0) * edge_fade * progress * color_tint.a;

	COLOR = vec4(col * total, alpha);
}
