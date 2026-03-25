shader_type canvas_item;

uniform sampler2D history_tex : filter_linear, repeat_disable;
uniform sampler2D live_lights_tex : filter_linear, repeat_disable;
uniform sampler2D fog_overlay_tex : filter_linear, repeat_enable;
uniform bool is_dm = false;
uniform bool flashlights_only = false;
uniform bool fog_overlay_enabled = false;
uniform float player_alpha_scale = 1.00;
uniform float dm_history_alpha_scale = 0.80;
uniform float live_mask_gain = 6.0;
uniform vec4 fog_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float fog_overlay_scale = 3.0;
uniform vec2 fog_overlay_speed = vec2(0.04, 0.03);
uniform float fog_overlay_strength = 0.15;

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

    float fog_alpha;
    vec3 base_color = fog_color.rgb;

    if (is_dm) {
        if (flashlights_only) {
            float dm_combined = max(history_mask, live_mask);
            fog_alpha = clamp(1.0 - dm_combined, 0.0, 1.0) * dm_history_alpha_scale;
        } else {
            fog_alpha = clamp(1.0 - history_mask, 0.0, 1.0) * dm_history_alpha_scale;
        }
    } else {
        if (flashlights_only) {
            float player_combined = max(history_mask, live_mask);
            fog_alpha = clamp(1.0 - player_combined, 0.0, 1.0) * player_alpha_scale;
        } else {
            float player_history_mask = clamp(history_mask * live_mask_gain, 0.0, 1.0);
            float combined_mask = max(player_history_mask, live_mask);
            fog_alpha = clamp(1.0 - combined_mask, 0.0, 1.0) * player_alpha_scale;
        }
    }

    if (fog_overlay_enabled && fog_alpha > 0.001) {
        // Two scrolling noise layers at different speeds for parallax depth.
        vec2 uv_scaled = UV * fog_overlay_scale;
        vec2 scroll1 = uv_scaled + fog_overlay_speed * TIME;
        vec2 scroll2 = uv_scaled * 1.3 - fog_overlay_speed * 0.6 * TIME + vec2(0.5, 0.3);
        float n1 = texture(fog_overlay_tex, scroll1).r;
        float n2 = texture(fog_overlay_tex, scroll2).r;
        // Blend two layers into 0..1 wisp brightness.
        float wisp = mix(n1, n2, 0.5);
        // Shift fog colour from black toward gray — fog stays fully opaque.
        base_color = vec3(wisp * fog_overlay_strength);
    }

    COLOR = vec4(base_color, fog_alpha);
}
