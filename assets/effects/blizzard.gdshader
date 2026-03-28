shader_type canvas_item;

// ---------------------------------------------------------------------------
// blizzard.gdshader — Procedural blizzard/ice-storm effect.
//
// Fire-like scrolling turbulence structure but with an icy white-blue palette.
// Swirling cold wind + drifting snowflakes layered on top.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform int shape_mode = 0; // 0 = full quad (circle/line), 1 = cone mask

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
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

vec3 frost_palette(float t) {
	// Dark blue → blue → cyan → light blue → bright white
	vec3 col = vec3(0.01, 0.03, 0.12);
	col = mix(col, vec3(0.06, 0.18, 0.45), smoothstep(0.0, 0.2, t));
	col = mix(col, vec3(0.15, 0.35, 0.7), smoothstep(0.2, 0.4, t));
	col = mix(col, vec3(0.3, 0.55, 0.85), smoothstep(0.4, 0.6, t));
	col = mix(col, vec3(0.55, 0.75, 0.92), smoothstep(0.6, 0.8, t));
	col = mix(col, vec3(0.92, 0.95, 1.0), smoothstep(0.85, 1.0, t));
	return col;
}

// Chaotic drifting snowflake layer — flows with the wind
float snowflake_layer(vec2 uv, float t, float scale, float drift_speed, float seed) {
	vec2 drift_uv = uv * scale;
	// Main flow matches storm turbulence direction (negative Y = toward mouth)
	drift_uv.y -= t * drift_speed;
	// Chaotic lateral gusts — multiple sine frequencies for unpredictable sway
	drift_uv.x += sin(t * 2.3 + seed + uv.y * 4.0) * 0.4;
	drift_uv.x += sin(t * 4.7 + seed * 1.7 + uv.y * 7.0) * 0.15;
	// Wind turbulence: noise-based displacement so flakes don't move in unison
	drift_uv.x += noise(vec2(uv.y * 3.0 + seed, t * 2.0)) * 0.5;
	drift_uv.y += noise(vec2(uv.x * 2.0 + seed, t * 1.5)) * 0.2;

	vec2 cell_id = floor(drift_uv);
	vec2 cell_frac = fract(drift_uv);

	float flakes = 0.0;
	for (int cy = -1; cy <= 1; cy++) {
		for (int cx = -1; cx <= 1; cx++) {
			vec2 neighbor = vec2(float(cx), float(cy));
			vec2 cid = cell_id + neighbor;
			vec2 flake_pos = hash2(cid + seed);
			float exists = step(0.55, hash(cid * 17.3 + seed));
			vec2 diff = neighbor + flake_pos - cell_frac;
			float d = length(diff);
			float radius = 0.05 + hash(cid * 31.7 + seed) * 0.07;
			float flake = smoothstep(radius, radius * 0.2, d) * exists;
			float twinkle = 0.7 + 0.3 * sin(t * 5.0 + hash(cid) * 6.28);
			flakes += flake * twinkle;
		}
	}
	return flakes;
}

void fragment() {
	vec2 uv = UV;
	vec2 centered = (uv - 0.5) * 2.0;
	float dist = length(centered);
	float t = TIME + time_offset;

	// Circular mask
	float mask = 1.0 - smoothstep(0.5, 1.0, dist);

	// Fire-like scrolling turbulence — flows from apex toward mouth (along -Y)
	// Two layers at different speeds for organic storm feel
	vec2 noise_uv = uv * 4.0;
	noise_uv.y -= t * 2.5; // fast main flow
	noise_uv.x += sin(t * 1.2 + uv.y * 4.0) * 0.3; // lateral sway

	float n = fbm(noise_uv);

	// Second turbulence layer — different scale/speed for depth
	vec2 noise_uv2 = uv * 3.0;
	noise_uv2.y -= t * 1.8;
	noise_uv2.x -= sin(t * 0.8 + uv.y * 3.0) * 0.35;
	noise_uv2 += vec2(sin(t * 0.6), cos(t * 0.7)) * 0.3;
	float n2 = fbm(noise_uv2);

	// Combine
	float storm = n * 0.6 + n2 * 0.4;
	storm = clamp(storm * 2.4 * intensity, 0.0, 1.0);

	// Apply icy colour ramp
	vec3 col = frost_palette(storm);

	// Drifting snowflakes — 3 layers, speeds matched to storm turbulence
	float snow1 = snowflake_layer(uv, t, 7.0, 1.6, 0.0);
	float snow2 = snowflake_layer(uv, t, 11.0, 2.2, 37.1);
	float snow3 = snowflake_layer(uv, t, 15.0, 2.8, 83.7);
	float snow = (snow1 + snow2 * 0.8 + snow3 * 0.6) * 0.3;

	// Snow is bright white additive
	col += vec3(0.8, 0.85, 0.9) * snow;
	col *= color_tint.rgb;

	float alpha = (storm + snow * 0.6) * mask * progress * color_tint.a;
	alpha = clamp(alpha, 0.0, 1.0);

	// Cone mask
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col, alpha);
}
