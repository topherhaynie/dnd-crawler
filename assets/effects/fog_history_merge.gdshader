shader_type canvas_item;

uniform sampler2D prev_history_tex : filter_linear, repeat_disable;
uniform sampler2D live_lights_tex : filter_linear, repeat_disable;
uniform sampler2D seed_tex : filter_linear, repeat_disable;
uniform bool seed_mode = false;
uniform float los_bake_gain = 4.0;
uniform int edit_mode = 0; // 0:none, 1:circle, 2:rect
uniform bool edit_reveal = true;
uniform vec2 edit_center_px = vec2(0.0, 0.0);
uniform float edit_radius_px = 0.0;
uniform vec2 edit_rect_min_px = vec2(0.0, 0.0);
uniform vec2 edit_rect_max_px = vec2(0.0, 0.0);
uniform vec2 tex_size_px = vec2(1.0, 1.0);

void fragment() {
    float out_mask;
    if (seed_mode) {
        out_mask = texture(seed_tex, UV).r;
    } else {
        float prev_mask = texture(prev_history_tex, UV).r;
        float live_mask = clamp(texture(live_lights_tex, UV).r * los_bake_gain, 0.0, 1.0);
        out_mask = max(prev_mask, live_mask);
    }

    if (edit_mode != 0) {
        vec2 pixel_pos = UV * tex_size_px;
        bool in_edit_region = false;
        if (edit_mode == 1) {
            in_edit_region = distance(pixel_pos, edit_center_px) <= edit_radius_px;
        } else if (edit_mode == 2) {
            in_edit_region = (
                pixel_pos.x >= edit_rect_min_px.x &&
                pixel_pos.y >= edit_rect_min_px.y &&
                pixel_pos.x <= edit_rect_max_px.x &&
                pixel_pos.y <= edit_rect_max_px.y
            );
        }
        if (in_edit_region) {
            out_mask = edit_reveal ? 1.0 : 0.0;
        }
    }

    COLOR = vec4(out_mask, 0.0, 0.0, 1.0);
}
