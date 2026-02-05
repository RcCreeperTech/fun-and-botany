#version 300 es

precision highp float;

layout(location = 0) in vec2 a_position;
layout(location = 1) in vec2 a_texCoord;
layout(location = 2) in vec4 a_color;

uniform mat4 u_projection;

out vec2 v_texCoord;
out vec4 v_color;

void main() {
    v_texCoord = a_texCoord;
    v_color = a_color;

    // Convert 2D position to 3D clip space
    gl_Position = u_projection * vec4(a_position, 0.0, 1.0);
}
