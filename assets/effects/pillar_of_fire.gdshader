shader_type canvas_item;

// ---------------------------------------------------------------------------
// pillar_of_fire.gdshader — Vertical column of fire rising along a line.
//
// Line tool only. UV.y=0 is the draw-start (base), UV.y=1 is the draw-end
// (top). Flames are hottest at the base and taper toward the top.
// Fire rendering shared with rain_of_fire via pillar_fire_common.gdshaderinc.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 color_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform int shape_mode = 0;
uniform int palette_index = 0;

#include "res://assets/effects/pillar_fire_common.gdshaderinc"

void fragment() {
	vec2 uv = UV;
	uv.y = 1.0 - uv.y; // Flip: _apply_line maps UV.y=0 to draw-end; we need 0=base.
	float t = TIME + time_offset;

	// UV.y runs along the line: 0 = base (draw start), 1 = top (draw end).
	// UV.x = perpendicular: 0.5 is the centre of the pillar.

	// Width — taper toward top
	float width_at_y = mix(0.48, 0.28, uv.y);
	float dist_from_centre = abs(uv.x - 0.5);
	float pillar_mask = 1.0 - smoothstep(width_at_y * 0.5, width_at_y, dist_from_centre);

	// Normalize across-pillar position for distortion
	float norm_x = (uv.x - 0.5) / max(width_at_y, 0.001);

	float flame = compute_pillar_flame(norm_x, uv.y, t, 0.0, intensity);

	vec3 col = _pf_fire_palette(flame) * color_tint.rgb;
	float alpha = flame * pillar_mask * progress * color_tint.a;

	COLOR = vec4(col, alpha);
}
