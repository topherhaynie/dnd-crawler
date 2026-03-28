shader_type canvas_item;
render_mode unshaded;

// ---------------------------------------------------------------------------
// chrome_ui.gdshader — Static procedural metallic background for The Vault UI.
//
// All modes produce fine, crisp metallic textures — no animation.
// base_color / highlight_color driven per-theme from GDScript.
//
// Modes:
//   1 — Brushed Steel    (fine diagonal grain, single highlight band)
//   2 — Polished Chrome  (fine horizontal grain, curved reflection bands)
//   3 — Hammered Iron    (fine grain + subtle cellular dimples)
//   4 — Arcane Metal     (angled grain with subtle cool-purple gradient)
// ---------------------------------------------------------------------------

uniform int theme_mode : hint_range(1, 4) = 1;
uniform vec3 base_color = vec3(0.06, 0.07, 0.09);
uniform vec3 highlight_color = vec3(0.28, 0.32, 0.38);
uniform vec3 edge_glow_color = vec3(0.28, 0.42, 0.65);

// ---------------------------------------------------------------------------
// Noise
// ---------------------------------------------------------------------------

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)),
	                      dot(p, vec2(269.5, 183.3)))) * 43758.5453);
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

// Anisotropic brushed grain — fine directional scratches.
// High frequency along grain direction, very low across it.
float brush_grain(vec2 uv, float angle, float fineness) {
	float cs = cos(angle);
	float sn = sin(angle);
	vec2 ruv = vec2(uv.x * cs - uv.y * sn, uv.x * sn + uv.y * cs);
	float n1 = noise(vec2(ruv.x * fineness,        ruv.y * 3.0));
	float n2 = noise(vec2(ruv.x * fineness * 0.48,  ruv.y * 5.0));
	float n3 = noise(vec2(ruv.x * fineness * 0.23,  ruv.y * 9.0));
	return n1 * 0.50 + n2 * 0.33 + n3 * 0.17;
}

float voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 pt = hash2(i + neighbor);
			pt = 0.5 + 0.5 * sin(6.2831 * pt);
			float d = length(neighbor + pt - f);
			min_dist = min(min_dist, d);
		}
	}
	return min_dist;
}

float edge_dist(vec2 uv) {
	float dx = min(uv.x, 1.0 - uv.x);
	float dy = min(uv.y, 1.0 - uv.y);
	return min(dx, dy);
}

// ---------------------------------------------------------------------------
// fragment
// ---------------------------------------------------------------------------

void fragment() {
	vec2 uv = UV;
	vec3 diff = highlight_color - base_color;
	vec3 col = vec3(0.0);

	// ── Mode 1: Brushed Steel ───────────────────────────────────────────
	if (theme_mode == 1) {
		float grain = brush_grain(uv, 0.26, 500.0);
		col = base_color + diff * grain * 0.10;
		// Broad sheen across centre
		float sheen = smoothstep(0.0, 0.45, uv.y) * smoothstep(1.0, 0.55, uv.y);
		col += diff * sheen * 0.35;
		// Tight specular highlight band
		float spec = smoothstep(0.22, 0.40, uv.y) * smoothstep(0.58, 0.40, uv.y);
		col += diff * spec * 0.50;
	}

	// ── Mode 2: Polished Chrome ─────────────────────────────────────────
	else if (theme_mode == 2) {
		float grain = brush_grain(uv, 0.0, 600.0);
		col = base_color + diff * grain * 0.06;
		// Curved reflection bands
		float r1 = sin(uv.y * 8.0 + uv.x * 2.0) * 0.5 + 0.5;
		float r2 = sin(uv.y * 4.5 - uv.x * 1.5) * 0.5 + 0.5;
		float refl = r1 * 0.6 + r2 * 0.4;
		float spec = smoothstep(0.38, 0.65, refl);
		col += diff * spec * 0.65;
		// Broad sheen
		float sheen = smoothstep(0.0, 0.40, uv.y) * smoothstep(1.0, 0.60, uv.y);
		col += diff * sheen * 0.25;
		// Edge vignette
		float vig = smoothstep(0.0, 0.20, edge_dist(uv));
		col *= mix(0.70, 1.0, vig);
	}

	// ── Mode 3: Forged Iron ─────────────────────────────────────────────
	else if (theme_mode == 3) {
		float grain = brush_grain(uv, -0.15, 400.0);
		col = base_color + diff * grain * 0.08;
		// Broad sheen
		float sheen = smoothstep(0.0, 0.42, uv.y) * smoothstep(1.0, 0.58, uv.y);
		col += diff * sheen * 0.30;
		// Glossy highlight from top-left
		float dx = uv.x - 0.28;
		float dy = uv.y - 0.32;
		float spot = exp(-(dx * dx * 2.5 + dy * dy * 4.0));
		col += diff * spot * 0.55;
	}

	// ── Mode 4: Arcane Metal ────────────────────────────────────────────
	else {
		float grain = brush_grain(uv, 0.38, 480.0);
		col = base_color + diff * grain * 0.08;
		// Very faint colour shift
		float grad = uv.x * 0.35 + uv.y * 0.65;
		col += vec3(-0.004, -0.006, 0.010) * grad;
		// Broad sheen
		float sheen = smoothstep(0.0, 0.42, uv.y) * smoothstep(1.0, 0.58, uv.y);
		col += diff * sheen * 0.30;
		// Specular band
		float spec = smoothstep(0.18, 0.38, uv.y) * smoothstep(0.62, 0.38, uv.y);
		col += diff * spec * 0.45;
	}

	// ── Edge glow (all modes) ───────────────────────────────────────────
	float ed = edge_dist(uv);
	float glow = smoothstep(0.035, 0.0, ed) * 0.28;
	col += edge_glow_color * glow;

	COLOR = vec4(col, 1.0);
}
