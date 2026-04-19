// ---------------------------------------------------------------------------
// pillar_fire_common.gdshaderinc — Shared fire pillar rendering.
//
// Provides noise functions, multi-palette colour ramp, and the core
// pillar-flame computation used by pillar_of_fire and rain_of_fire.
//
// Requires the including shader to declare:
//   uniform int palette_index;
// ---------------------------------------------------------------------------

float _pf_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float _pf_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = _pf_hash(i);
	float b = _pf_hash(i + vec2(1.0, 0.0));
	float c = _pf_hash(i + vec2(0.0, 1.0));
	float d = _pf_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float _pf_fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amp * _pf_noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return value;
}

vec3 _pf_fire_palette(float t) {
	vec3 col = vec3(0.0);
	if (palette_index == 1) {
		col = mix(col, vec3(0.3, 0.0, 0.0), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.7, 0.05, 0.05), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(1.0, 0.15, 0.1), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(1.0, 0.5, 0.4), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(1.0, 0.9, 0.85), smoothstep(0.8, 1.0, t));
	} else if (palette_index == 2) {
		col = mix(col, vec3(0.0, 0.3, 0.0), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.0, 0.65, 0.1), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(0.2, 0.9, 0.1), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(0.6, 1.0, 0.3), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(0.9, 1.0, 0.85), smoothstep(0.8, 1.0, t));
	} else if (palette_index == 3) {
		col = mix(col, vec3(0.0, 0.0, 0.4), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.0, 0.15, 0.8), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(0.1, 0.4, 1.0), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(0.4, 0.7, 1.0), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(0.85, 0.95, 1.0), smoothstep(0.8, 1.0, t));
	} else if (palette_index == 4) {
		col = mix(col, vec3(0.25, 0.0, 0.3), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.5, 0.0, 0.6), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(0.7, 0.15, 0.85), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(0.9, 0.4, 1.0), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(1.0, 0.85, 1.0), smoothstep(0.8, 1.0, t));
	} else if (palette_index == 5) {
		col = mix(col, vec3(0.4, 0.25, 0.0), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.7, 0.5, 0.0), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(1.0, 0.85, 0.0), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(1.0, 1.0, 0.4), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(1.0, 1.0, 0.9), smoothstep(0.8, 1.0, t));
	} else if (palette_index == 6) {
		col = mix(col, vec3(0.02, 0.02, 0.03), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.05, 0.05, 0.06), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(0.10, 0.10, 0.12), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(0.25, 0.25, 0.28), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(0.40, 0.38, 0.44), smoothstep(0.8, 1.0, t));
	} else {
		col = mix(col, vec3(0.5, 0.0, 0.0), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.9, 0.15, 0.0), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(1.0, 0.5, 0.0), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(1.0, 0.9, 0.2), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(1.0, 1.0, 0.9), smoothstep(0.8, 1.0, t));
	}
	return col;
}

// Compute pillar flame intensity at a point.
//   px_norm  — normalized across-pillar position (-1..1, 0 = centre)
//   py       — along-pillar position (0 = base, 1 = top)
//   t        — time
//   seed     — per-pillar seed offset (use 0.0 for the main pillar)
//   inten    — intensity multiplier (the uniform)
// Returns flame intensity [0, 1] after contrast curves.
float compute_pillar_flame(float px_norm, float py, float t, float seed, float inten) {
	float height_fade = 1.0 - py * 0.55;

	// Spiral warp: twist noise coordinates around the pillar axis
	float angle = px_norm * 3.14159;
	float spiral  = angle + py * 24.0 + t * 7.0 + seed * 5.0;
	float spiral2 = angle - py * 18.0 + t * 5.0 + seed * 3.0;
	float warp1 = sin(spiral)  * 0.75;
	float warp2 = sin(spiral2) * 0.55;

	float flicker = sin(t * 2.3 + py * 5.0 + seed) * 0.1;

	// Primary noise — large scale, spiral-warped, scrolling upward
	vec2 nuv1 = vec2(px_norm * 3.0 + warp1 + flicker, py * 6.0 - t * 3.5 - seed * 3.0);
	float n1 = _pf_fbm(nuv1);

	// Secondary noise — finer detail, counter-spiral warp, faster scroll
	vec2 nuv2 = vec2(px_norm * 5.0 + warp2 - flicker * 0.5, py * 8.0 - t * 4.8 - seed * 2.0);
	float n2 = _pf_fbm(nuv2 + vec2(7.3, 2.9));

	// Tertiary — slow large-scale swirl for organic variation
	vec2 nuv3 = vec2(px_norm * 2.0 + sin(t * 1.1 + seed) * 0.3, py * 4.0 - t * 2.0);
	float n3 = _pf_fbm(nuv3 + vec2(3.1, 5.7));

	float n = n1 * 0.5 + n2 * 0.3 + n3 * 0.2;

	// Hot-core boost toward the centre
	float core_boost = exp(-px_norm * px_norm * 4.0);
	n = n * (0.6 + 0.4 * core_boost);

	float flame = n * height_fade;
	flame = clamp(flame * 2.2 * inten, 0.0, 1.0);
	// Triple S-curve for contrast
	flame = flame * flame * (3.0 - 2.0 * flame);
	flame = flame * flame * (3.0 - 2.0 * flame);
	flame = flame * flame * (3.0 - 2.0 * flame);
	flame *= 0.95;

	return flame;
}
