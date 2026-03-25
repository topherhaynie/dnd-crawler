shader_type canvas_item;

uniform sampler2D history_tex : filter_linear, repeat_disable;
uniform sampler2D live_lights_tex : filter_linear, repeat_disable;
uniform bool is_dm = false;
uniform float player_alpha_scale = 1.00;
uniform float dm_history_alpha_scale = 0.80;
uniform float live_mask_gain = 6.0;
uniform vec4 fog_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
    // Sample fog textures with a small 5-tap blur for softer edges.
    vec2 texel = vec2(1.0) / vec2(textureSize(history_tex, 0));
    float h0 = texture(history_tex, UV).r;
    float h1 = texture(history_tex, UV + vec2(texel.x, 0.0)).r;
    float h2 = texture(history_tex, UV - vec2(texel.x, 0.0)).r;
    float h3 = texture(history_tex, UV + vec2(0.0, texel.y)).r;
    float h4 = texture(history_tex, UV - vec2(0.0, texel.y)).r;
    float history_mask = (h0 * 2.0 + h1 + h2 + h3 + h4) / 6.0;

    float live_mask = clamp(texture(live_lights_tex, UV).r * live_mask_gain, 0.0, 1.0);

    if (is_dm) {
        // DM view ignores live_lights_tex and only shows persistent history dimming.
        float dm_alpha = clamp(1.0 - history_mask, 0.0, 1.0) * dm_history_alpha_scale;
        COLOR = vec4(fog_color.rgb, dm_alpha);
    } else {
        float player_history_mask = clamp(history_mask * live_mask_gain, 0.0, 1.0);
        float combined_mask = max(player_history_mask, live_mask);
        float alpha = clamp(1.0 - combined_mask, 0.0, 1.0) * player_alpha_scale;
        COLOR = vec4(fog_color.rgb, alpha);
    }
}
