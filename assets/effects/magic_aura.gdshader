shader_type canvas_item;

// ---------------------------------------------------------------------------
// magic_aura.gdshader — Procedural generic magic aura effect.
//
// Noise-thresholded sparkle field with configurable base colour via tint.
// Orbiting energy wisps on a polar coordinate noise field.
// Soft outer glow ring.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(0.6, 0.4, 1.0, 1.0);
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

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	float dist = length(uv);
	float angle = atan(uv.y, uv.x);

	float t = TIME + time_offset;
	// Orbiting energy wisps — polar noise rotating over time
	float wisp_angle = angle + t * 0.6;
	float wisp = fbm(vec2(wisp_angle * 2.0, dist * 3.0 + t * 0.5));
	wisp = smoothstep(0.4, 0.7, wisp);

	// Inner aura glow
	float inner = exp(-dist * dist * 3.0) * 0.6;

	// Outer glow ring
	float ring_dist = abs(dist - 0.55);
	float ring = exp(-ring_dist * ring_dist * 25.0) * 0.5;

	// Sparkle field
	float sparkle_uv_scale = 20.0;
	vec2 sparkle_cell = floor(UV * sparkle_uv_scale);
	float sparkle_hash = hash(sparkle_cell + floor(vec2(t * 3.0)));
	float sparkle = step(0.95, sparkle_hash) * (0.5 + 0.5 * sin(t * 10.0 + sparkle_hash * 50.0));

	// Combine
	float total = (inner + ring + wisp * 0.5) * intensity;

	// Colour: use tint as base, brighten toward centre
	vec3 col = color_tint.rgb;
	col = mix(col, col * 1.5 + vec3(0.2), smoothstep(0.5, 0.0, dist));
	col += vec3(sparkle) * 0.4;

	// Pulsing
	float pulse = 0.9 + 0.1 * sin(t * 2.0);
	total *= pulse;

	// Boundary
	float boundary = 1.0 - smoothstep(0.7, 1.0, dist);

	float alpha = clamp(total + sparkle * 0.3, 0.0, 1.0) * boundary * progress * color_tint.a;

	// Cone mask: apex at UV (0.5, 0.0), full width at UV.y = 1.0
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col, alpha);
}
