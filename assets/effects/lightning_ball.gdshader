shader_type canvas_item;

// ---------------------------------------------------------------------------
// lightning_ball.gdshader — Chaotic electric sphere effect.
//
// Multiple sharp lightning arcs crawl around a pulsating energy core.
// Bright spark pops, high-contrast tendrils, and vivid blue/purple plasma.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform int shape_mode = 0; // 0 = full quad (circle/line), 1 = cone mask

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float hash1(float n) {
	return fract(sin(n) * 43758.5453123);
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

float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		value += amp * noise(p);
		p *= 2.1;
		amp *= 0.5;
	}
	return value;
}

// Sharp lightning arc radiating outward from centre at a given angle.
// Uses the same 4-octave aggressive noise displacement as lightning_bolt_wild.
float arc_shape(vec2 uv, float t, float arc_angle, float speed, float seed) {
	// Rotate UV so the arc points along +X
	vec2 arc_dir = vec2(cos(arc_angle), sin(arc_angle));
	vec2 arc_perp = vec2(-arc_dir.y, arc_dir.x);
	float along = dot(uv, arc_dir);
	float perp = dot(uv, arc_perp);

	// Only draw arcs radiating outward from centre
	if (along < 0.04) return 0.0;

	// 4-octave aggressive noise displacement (matching lightning_bolt_wild)
	float displacement = 0.0;
	displacement += noise(vec2(along * 3.0 + seed, t * speed * 0.8)) * 0.30;
	displacement += noise(vec2(along * 7.0 + seed * 1.3, t * speed * 1.4)) * 0.18;
	displacement += noise(vec2(along * 14.0 + seed * 2.1, t * speed * 2.2)) * 0.10;
	displacement += noise(vec2(along * 28.0 + seed * 3.0, t * speed * 3.0)) * 0.05;
	displacement -= 0.27; // re-centre (matching wild bolt offset)

	// Scale displacement outward (wider wobble further from centre)
	displacement *= (0.6 + along * 1.4);

	float dist_from_arc = abs(perp - displacement);

	// Sharp core + wider glow (matching wild bolt rendering)
	float core = exp(-dist_from_arc * 50.0);
	float glow = exp(-dist_from_arc * 10.0) * 0.4;

	// Fade out at the tip
	float tip_fade = smoothstep(0.85, 0.5, along);
	// Slight fade near centre so arcs emerge from core
	float base_fade = smoothstep(0.04, 0.12, along);
	return (core + glow) * tip_fade * base_fade;
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0; // [-1, 1]
	float dist = length(uv);
	float angle = atan(uv.y, uv.x);
	float t = TIME + time_offset;

	// --- Pulsating core ---
	float core_pulse = 0.9 + 0.1 * sin(t * 8.0) + 0.05 * sin(t * 19.0);
	float core_noise = fbm(vec2(angle * 2.0 + t * 3.0, dist * 4.0), 3);
	float core_radius = 0.22 * core_pulse + core_noise * 0.06;
	float core = smoothstep(core_radius + 0.08, core_radius - 0.02, dist);

	// Inner glow halo
	float inner_glow = exp(-dist * dist * 6.0) * 0.4;

	// --- Crawling lightning arcs (6 arcs at varying angles) ---
	float arcs = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		// Each arc rotates at a different speed and offset
		float arc_angle = fi * 1.047 + t * (0.8 + fi * 0.3) + hash1(fi * 73.1) * 6.28;
		float arc_speed = 5.0 + fi * 1.5;
		float a = arc_shape(uv, t, arc_angle, arc_speed, fi * 31.7);
		arcs += a;
	}
	arcs = min(arcs, 2.5); // clamp accumulation

	// --- Outer plasma tendrils (noisy radial energy) ---
	float tendril_noise = fbm(vec2(angle * 6.0 + t * 5.0, dist * 5.0 - t * 2.0), 5);
	float tendril_noise2 = fbm(vec2(angle * 4.0 - t * 7.0, dist * 3.0 + t * 1.0), 4);
	float plasma = tendril_noise * tendril_noise2;
	// Sharpen — turn smooth noise into bright streaks
	plasma = smoothstep(0.15, 0.35, plasma);
	// Mask to outer region, fading from mid to edge
	float plasma_mask = smoothstep(0.15, 0.4, dist) * smoothstep(1.0, 0.6, dist);
	plasma *= plasma_mask * 0.7;

	// --- Bright spark pops (hash-based, appear/disappear quickly) ---
	float sparks = 0.0;
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		float spark_time = floor(t * (3.0 + fi * 0.7));
		float spark_angle = hash1(spark_time * 17.3 + fi * 91.0) * 6.2832;
		float spark_r = 0.2 + hash1(spark_time * 41.7 + fi * 13.0) * 0.45;
		vec2 spark_pos = vec2(cos(spark_angle), sin(spark_angle)) * spark_r;
		float spark_dist = length(uv - spark_pos);
		float spark_life = fract(t * (3.0 + fi * 0.7));
		float spark_bright = smoothstep(0.4, 0.0, spark_life) * smoothstep(0.0, 0.05, spark_life);
		sparks += exp(-spark_dist * spark_dist * 800.0) * spark_bright;
	}
	sparks = min(sparks, 1.5);

	// --- Surface crackle (high-freq noise band near the sphere edge) ---
	float crackle_noise = fbm(vec2(angle * 10.0 + t * 12.0, dist * 8.0), 3);
	float crackle = smoothstep(0.55, 0.7, crackle_noise);
	float crackle_mask = smoothstep(0.25, 0.5, dist) * smoothstep(0.9, 0.65, dist);
	crackle *= crackle_mask * 0.5;

	// --- Combine ---
	float total = (core + inner_glow + arcs * 0.9 + plasma + sparks * 1.2 + crackle) * intensity;

	// Multi-channel flicker
	float flicker = 0.85 + 0.15 * sin(t * 31.0) * sin(t * 47.0);
	float flicker2 = 0.9 + 0.1 * sin(t * 19.0 + 2.0);
	total *= flicker * flicker2;

	// --- Colour ---
	// Deep purple edges → vivid electric blue mid → white-hot core
	vec3 col_deep = vec3(0.35, 0.1, 0.7);   // deep purple
	vec3 col_blue = vec3(0.3, 0.5, 1.0);     // electric blue
	vec3 col_cyan = vec3(0.5, 0.8, 1.0);     // cyan tinge
	vec3 col_white = vec3(1.0, 1.0, 1.0);    // white-hot

	vec3 col = col_deep;
	col = mix(col, col_blue, smoothstep(0.7, 0.45, dist));
	col = mix(col, col_cyan, smoothstep(0.45, 0.25, dist));
	col = mix(col, col_white, smoothstep(0.25, 0.05, dist));

	// Arcs and sparks get a blue-white boost
	float arc_bright = clamp(arcs + sparks * 1.2, 0.0, 1.0);
	col = mix(col, vec3(0.6, 0.8, 1.0), arc_bright * 0.5);

	col *= color_tint.rgb;

	// Circular boundary fade
	float boundary = 1.0 - smoothstep(0.75, 1.0, dist);
	float alpha = clamp(total, 0.0, 1.0) * boundary * progress * color_tint.a;

	// Cone mask
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col * clamp(total, 0.0, 2.5), alpha);
}
