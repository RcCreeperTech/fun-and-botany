#version 300 es
precision mediump float;

in vec2 v_texCoord;
in vec4 v_color;

uniform sampler2D u_texture;

out vec4 outColor;

// The threshold determines how "thick" the connection is
const float threshold = 0.5;
// The softness helps with anti-aliasing the edges
const float softness = 0.02;

void main() {
    vec4 texColor = texture(u_texture, v_texCoord);
    float alpha = smoothstep(threshold - softness, threshold + softness, texColor.a);
    outColor = vec4((texColor * v_color).rgb, alpha);
}
