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

	// ── Inward-spiralling vortex ──────────────────────────────────────────
	// Warp angle by distance → spiral arms. +t rotates inward.
	// Wiggle the spiral coordinate with noise so the arms squirm.
	float wiggle = noise(vec2(dist * 4.0 + t * 0.8, angle * 2.0 + t * 0.3)) * 0.5;
	float spiral = angle + dist * 6.0 + t * 1.5 + wiggle;

	// Seamless polar noise along the spiral coordinate
	float r_noise = 3.5;
	vec2 sp_uv = vec2(cos(spiral) * r_noise, sin(spiral) * r_noise) + dist * 1.5;

	// Primary vortex arms
	float vortex = fbm(sp_uv);
	// Second layer at different scale for chaotic variation
	float vortex2 = fbm(sp_uv * 1.7 + vec2(4.3, -2.1) + t * 0.2);
	vortex = mix(vortex, vortex2, 0.35);

	// Lightning-like crackling variation — high-frequency noise displacement
	float crack1 = noise(sp_uv * 6.0 + t * 0.8) * 0.4;
	float crack2 = noise(sp_uv * 13.0 - t * 0.5) * 0.2;
	vortex += (crack1 + crack2) * smoothstep(1.0, 0.2, dist);

	// Sharpen into narrow arm-like bands — tight range for high contrast
	vortex = smoothstep(0.48, 0.72, vortex);
	// Boost contrast: crush darks and push brights
	vortex = vortex * vortex * (3.0 - 2.0 * vortex);

	// Intensify toward the centre (everything feeds inward)
	float center_pull = smoothstep(1.0, 0.1, dist);
	vortex *= center_pull;

	// Small-scale turbulence for organic feel
	vec2 turb_uv = uv * 5.0 + vec2(t * 0.4, -t * 0.3);
	float turbulence = fbm(turb_uv) * 0.15 * center_pull;

	// Inner core glow — dimmer
	float inner = exp(-dist * dist * 4.0) * 0.35;

	// Outer glow ring — subtler
	float ring_dist = abs(dist - 0.55);
	float ring = exp(-ring_dist * ring_dist * 25.0) * 0.2;

	// Combine — lower vortex contribution for darker gaps
	float total = (inner + ring + vortex * 0.45 + turbulence) * intensity;

	// Colour: dark base with violet/blue layering
	vec3 col = color_tint.rgb * 0.35;
	col = mix(col, color_tint.rgb * 1.5, smoothstep(0.6, 0.0, dist) * vortex);
	// Violet wash in the spiral arms
	vec3 violet = vec3(0.45, 0.15, 0.7);
	col = mix(col, violet, vortex * 0.5);
	// Deep blue accent toward the outer edges
	vec3 deep_blue = vec3(0.05, 0.1, 0.45);
	col = mix(col, deep_blue, smoothstep(0.2, 0.7, dist) * 0.5);
	// Bright cyan-violet crackling at the hottest peaks
	col += vec3(0.35, 0.2, 0.65) * smoothstep(0.5, 1.0, vortex) * center_pull;
	// Electric blue shimmer in the turbulence
	col += vec3(0.05, 0.12, 0.3) * turbulence * 2.0;

	// Pulsing
	float pulse = 0.9 + 0.1 * sin(t * 2.0);
	total *= pulse;

	// Boundary
	float boundary = 1.0 - smoothstep(0.7, 1.0, dist);

	float alpha = clamp(total, 0.0, 1.0) * boundary * progress * color_tint.a;

	// Cone mask: apex at UV (0.5, 0.0), full width at UV.y = 1.0
	if (shape_mode == 1) {
		float cone_half_w = UV.y * 0.5;
		if (abs(UV.x - 0.5) > cone_half_w) { discard; }
	}

	COLOR = vec4(col, alpha);
}
