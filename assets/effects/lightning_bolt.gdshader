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

	// Main bolt
	float bolt = bolt_shape(uv, t);

	// Secondary branch (thinner, offset)
	vec2 branch_uv = uv;
	branch_uv.x = branch_uv.x * 0.8 + 0.2;
	branch_uv.y = branch_uv.y * 0.7 + 0.15;
	float branch = bolt_shape(branch_uv, t + 2.0) * 0.4;

	float total = (bolt + branch) * flicker * intensity;

	// Colour: white-hot core blending to electric blue
	vec3 col = mix(vec3(0.3, 0.5, 1.0), vec3(1.0, 1.0, 1.0), clamp(total, 0.0, 1.0));
	col *= color_tint.rgb;

	// Vertical fade at top and bottom edges
	float edge_fade = smoothstep(0.0, 0.1, uv.y) * smoothstep(1.0, 0.9, uv.y);

	float alpha = clamp(total, 0.0, 1.0) * edge_fade * progress * color_tint.a;

	// Cone mask: apex at UV (0.5, 0.0), full width at UV.y = 1.0
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col * total, alpha);
}
