shader_type canvas_item;

// ---------------------------------------------------------------------------
// holy_radiance.gdshader — Procedural holy/radiance glow effect.
//
// Radial god-rays from centre with angular noise modulation.
// Golden-white colour with pulsing brightness. Soft circular vignette.
// Warm glow halo.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0, 0.95, 0.7, 1.0);
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

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	// Cone mode: pie-slice — radiance center at the apex (vertex).
	// No *2 so mouth center lands at dist≈1.0, matching circle-mode edge.
	if (shape_mode == 1) {
		uv = UV - vec2(0.5, 0.0);
	}
	float dist = length(uv);
	float angle = atan(uv.y, uv.x);

	float t = TIME + time_offset;
	// God-rays: angular noise creates varying brightness along radial directions
	float ray_noise = noise(vec2(angle * 4.0 + t * 0.5, 0.0));
	float ray_noise2 = noise(vec2(angle * 8.0 - t * 0.3, 1.0));
	float rays = (ray_noise * 0.7 + ray_noise2 * 0.3);

	// Radial falloff — brighter at centre
	float radial = exp(-dist * dist * 2.0);

	// Ray structure — modulate radial glow with angular noise
	float ray_mask = smoothstep(0.3, 0.8, rays);
	float god_rays = radial * (0.5 + ray_mask * 0.5);

	// Central bright core
	float core = exp(-dist * dist * 8.0);

	// Pulsing brightness
	float pulse = 0.85 + 0.15 * sin(t * 1.5);

	float total = (god_rays + core * 0.6) * pulse * intensity;

	// Colour: warm golden-white
	vec3 gold = vec3(1.0, 0.85, 0.4);
	vec3 white = vec3(1.0, 1.0, 0.95);
	vec3 col = mix(gold, white, smoothstep(0.3, 0.0, dist));
	col *= color_tint.rgb;

	// Outer halo ring
	float halo_dist = abs(dist - 0.6);
	float halo = exp(-halo_dist * halo_dist * 30.0) * 0.3;
	col += vec3(1.0, 0.9, 0.6) * halo;

	// Boundary fade
	float boundary = 1.0 - smoothstep(0.7, 1.0, dist);

	float alpha = clamp(total + halo, 0.0, 1.0) * boundary * progress * color_tint.a;

	// Cone mask: apex at UV (0.5, 0.0), full width at UV.y = 1.0
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col, alpha);
}
