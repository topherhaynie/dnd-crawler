shader_type canvas_item;

uniform sampler2D prev_history_tex : filter_nearest, repeat_disable;
uniform sampler2D live_lights_tex : filter_nearest, repeat_disable;
uniform sampler2D seed_tex : filter_nearest, repeat_disable;
uniform bool seed_mode = false;
uniform float los_bake_gain = 4.0;

void fragment() {
    float out_mask;
    if (seed_mode) {
        out_mask = texture(seed_tex, UV).r;
    } else {
        float prev_mask = texture(prev_history_tex, UV).r;
        float live_mask = clamp(texture(live_lights_tex, UV).r * los_bake_gain, 0.0, 1.0);
        out_mask = max(prev_mask, live_mask);
    }

    COLOR = vec4(out_mask, 0.0, 0.0, 1.0);
}
