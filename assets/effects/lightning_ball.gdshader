shader_type canvas_item;

// ---------------------------------------------------------------------------
// lightning_ball.gdshader — Procedural electric sphere effect.
//
// Radial distance field with noise-based displacement creating arcing
// tendrils. White-hot centre fading to electric blue/purple at edges.
// Rapidly shifting noise for a crackling energy ball.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(0.5, 0.7, 1.0, 1.0);
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
	vec2 uv = (UV - 0.5) * 2.0; // [-1, 1]
	float dist = length(uv);

	// Angle for polar noise
	float angle = atan(uv.y, uv.x);

	float t = TIME + time_offset;
	// Noise-displaced radius for electric arcs
	float arc_noise = fbm(vec2(angle * 3.0 + t * 4.0, dist * 2.0 + t * 2.0));
	float arc_noise2 = fbm(vec2(angle * 5.0 - t * 6.0, dist * 3.0 - t * 1.5));

	// Displaced distance creates arcing tendrils
	float displaced_dist = dist - arc_noise * 0.3 - arc_noise2 * 0.15;

	// Core glow (white-hot centre)
	float core = exp(-displaced_dist * displaced_dist * 8.0);

	// Outer energy ring
	float ring_dist = abs(displaced_dist - 0.4);
	float ring = exp(-ring_dist * ring_dist * 40.0);

	// Crackling tendrils reaching outward
	float tendril = exp(-max(displaced_dist - 0.1, 0.0) * 6.0);
	tendril *= (arc_noise * 0.5 + 0.5);

	float total = (core + ring * 0.6 + tendril * 0.4) * intensity;

	// Flicker
	float flicker = 0.8 + 0.2 * sin(t * 25.0) * sin(t * 37.0);
	total *= flicker;

	// Colour gradient: white centre → blue → purple edges
	vec3 col = mix(vec3(0.4, 0.2, 0.8), vec3(0.4, 0.6, 1.0), smoothstep(0.6, 0.2, dist));
	col = mix(col, vec3(1.0, 1.0, 1.0), smoothstep(0.3, 0.0, dist));
	col *= color_tint.rgb;

	// Circular boundary fade
	float boundary = 1.0 - smoothstep(0.7, 1.0, dist);

	float alpha = clamp(total, 0.0, 1.0) * boundary * progress * color_tint.a;

	// Cone mask: apex at UV (0.5, 0.0), full width at UV.y = 1.0
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col * clamp(total, 0.0, 2.0), alpha);
}
