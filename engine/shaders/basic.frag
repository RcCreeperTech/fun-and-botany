#version 300 es

precision highp float;

in vec2 v_texCoord;
in vec4 v_color;

uniform sampler2D u_texture;

out vec4 outColor;

void main() {
    // Sample the texture and multiply by the per-vertex color
    vec4 texColor = texture(u_texture, v_texCoord);
    outColor = texColor * v_color;

    // Discard fully transparent pixels (useful for UI icons/textures)
    if (outColor.a < 0.1) {
        discard;
    }
}
