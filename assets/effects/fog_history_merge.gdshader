shader_type canvas_item;

uniform sampler2D prev_history_tex : filter_nearest, repeat_disable;
uniform sampler2D live_lights_tex : filter_nearest, repeat_disable;
uniform sampler2D seed_tex : filter_nearest, repeat_disable;
uniform sampler2D paint_tex : filter_nearest, repeat_disable;
uniform bool seed_mode = false;
uniform bool has_paint_tex = false;
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

    // GPU paint strokes: paint_tex alpha=1 means "this pixel was explicitly painted".
    // paint_tex.r=1.0 reveals, paint_tex.r=0.0 hides.
    if (has_paint_tex) {
        vec4 paint_sample = texture(paint_tex, UV);
        out_mask = mix(out_mask, paint_sample.r, paint_sample.a);
    }

    COLOR = vec4(out_mask, 0.0, 0.0, 1.0);
}
