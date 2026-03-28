shader_type canvas_item;

// ---------------------------------------------------------------------------
// fire.gdshader — Procedural fire effect for DM-placed magic effects.
//
// Renders animated flames using multi-octave noise with upward scroll,
// a colour gradient ramp (black → red → orange → yellow → white tips),
// and a circular area mask for area-of-effect shape.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform int shape_mode = 0; // 0 = full quad (circle/line), 1 = cone mask

// Hash-based pseudo-random for noise generation (no texture needed).
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep
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
	// Black → deep red → red → orange → yellow → white
	vec3 col = vec3(0.0);
	col = mix(col, vec3(0.5, 0.0, 0.0), smoothstep(0.0, 0.2, t));
	col = mix(col, vec3(0.9, 0.15, 0.0), smoothstep(0.2, 0.4, t));
	col = mix(col, vec3(1.0, 0.5, 0.0), smoothstep(0.4, 0.6, t));
	col = mix(col, vec3(1.0, 0.9, 0.2), smoothstep(0.6, 0.8, t));
	col = mix(col, vec3(1.0, 1.0, 0.9), smoothstep(0.8, 1.0, t));
	return col;
}

void fragment() {
	vec2 uv = UV;
	// Centre UV to [-1, 1]
	vec2 centered = (uv - 0.5) * 2.0;

	// Circular mask — soft falloff at edge
	float dist = length(centered);
	float mask = 1.0 - smoothstep(0.5, 1.0, dist);

	// Noise coordinates — scroll upward for flame motion
	vec2 noise_uv = uv * 4.0;
	float t = TIME + time_offset;
	noise_uv.y -= t * 1.8; // upward scroll
	noise_uv.x += sin(t * 0.7 + uv.y * 3.0) * 0.15; // horizontal flicker

	float n = fbm(noise_uv);
	// Bias flame intensity toward the bottom (flames rise)
	float flame = n * (1.0 - uv.y * 0.6);
	flame = clamp(flame * 2.0 * intensity, 0.0, 1.0);

	vec3 col = fire_palette(flame) * color_tint.rgb;

	float alpha = flame * mask * progress * color_tint.a;

	// Cone mask: apex at UV (0.5, 0.0), full width at UV.y = 1.0
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col, alpha);
}
