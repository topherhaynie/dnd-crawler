shader_type canvas_item;

// ---------------------------------------------------------------------------
// fire_wall.gdshader — Procedural wall-of-fire effect.
//
// Renders a tall curtain of flames rising from a line.
// Flames are hottest at the base and taper upward.
// Uses the same multi-palette system as fire.gdshader.
// Line shape only.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform int shape_mode = 0; // unused — line shape handled by EffectNode geometry
uniform int palette_index = 0; // 0=orange,1=red,2=green,3=blue,4=violet,5=yellow,6=black

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

vec3 fire_palette(float t) {
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
		col = mix(col, vec3(0.15, 0.08, 0.05), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.25, 0.12, 0.08), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(0.35, 0.15, 0.1), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(0.2, 0.1, 0.08), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(0.5, 0.2, 0.1), smoothstep(0.8, 1.0, t));
	} else {
		col = mix(col, vec3(0.5, 0.0, 0.0), smoothstep(0.0, 0.2, t));
		col = mix(col, vec3(0.9, 0.15, 0.0), smoothstep(0.2, 0.4, t));
		col = mix(col, vec3(1.0, 0.5, 0.0), smoothstep(0.4, 0.6, t));
		col = mix(col, vec3(1.0, 0.9, 0.2), smoothstep(0.6, 0.8, t));
		col = mix(col, vec3(1.0, 1.0, 0.9), smoothstep(0.8, 1.0, t));
	}
	return col;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME + time_offset;

	// Line geometry: UV.y runs along the line, UV.x is perpendicular.
	// Flames are one-sided: base at UV.x=1.0 (the line), tips at UV.x=0.0.
	// Draw direction determines which screen-side the flames face:
	//   left→right = flames up, right→left = flames down, etc.

	// Soft mask at line endpoints
	float edge_mask = smoothstep(0.0, 0.08, uv.y) * smoothstep(0.0, 0.08, 1.0 - uv.y);

	// One-sided height taper — hottest at the line (uv.x=1), fading toward tips (uv.x=0)
	float flame_height = 1.0 - uv.x; // 0 at line, 1 at far tip
	float height_mask = 1.0 - smoothstep(0.2, 1.0, flame_height);

	// Noise: tile along wall (Y), scroll outward from line toward tips (-X)
	vec2 noise_uv = vec2(uv.y * 6.0, flame_height * 4.0);
	noise_uv.y -= t * 3.0;
	noise_uv.x += sin(t * 1.2 + uv.x * 3.0) * 0.18;

	// Second turbulence layer at different scale for richer detail
	float n1 = fbm(noise_uv);
	float n2 = fbm(noise_uv * 1.8 + vec2(5.3, -t * 1.5));
	float n = mix(n1, n2, 0.35);

	float flame = n * height_mask;
	flame = clamp(flame * 2.5 * intensity, 0.0, 1.0);

	vec3 col = fire_palette(flame) * color_tint.rgb;
	float alpha = flame * edge_mask * progress * color_tint.a;

	COLOR = vec4(col, alpha);
}
