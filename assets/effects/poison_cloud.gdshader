shader_type canvas_item;

// ---------------------------------------------------------------------------
// poison_cloud.gdshader — Procedural poison/acid cloud effect.
//
// Multi-octave fbm noise with green-yellow colour. Billowing motion via
// UV rotation over time. Soft alpha falloff at circular edge.
// Subtle purple accents in dark regions.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(0.6, 1.0, 0.3, 1.0);
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
	for (int i = 0; i < 5; i++) {
		value += amp * noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return value;
}

vec2 rotate_uv(vec2 uv, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	float dist = length(uv);

	float t = TIME + time_offset;
	// Billowing rotation over time
	vec2 rotated = rotate_uv(uv, t * 0.15);

	// Multi-layer cloud noise
	vec2 noise_uv = rotated * 1.5;
	float cloud1 = fbm(noise_uv + vec2(t * 0.2, t * 0.1));
	float cloud2 = fbm(noise_uv * 1.5 + vec2(-t * 0.15, t * 0.25));
	float cloud = (cloud1 + cloud2) * 0.5;

	// Pulsing density
	cloud *= 0.8 + 0.2 * sin(t * 0.8);
	cloud *= intensity;

	// Colour: green-yellow with purple accents in dark regions
	vec3 green = vec3(0.2, 0.6, 0.1);
	vec3 yellow = vec3(0.7, 0.8, 0.1);
	vec3 purple = vec3(0.3, 0.1, 0.4);
	vec3 col = mix(purple, green, smoothstep(0.2, 0.5, cloud));
	col = mix(col, yellow, smoothstep(0.5, 0.8, cloud));
	col *= color_tint.rgb;

	// Soft circular edge falloff
	float boundary = 1.0 - smoothstep(0.5, 1.0, dist);

	float alpha = clamp(cloud, 0.0, 1.0) * boundary * progress * color_tint.a;

	// Cone mask: apex at UV (0.5, 0.0), full width at UV.y = 1.0
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col, alpha * 0.85);
}
