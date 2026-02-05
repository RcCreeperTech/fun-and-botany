#version 300 es

precision highp float;

// The static unit quad [-0.5, 0.5]
layout(location = 0) in vec2 a_unit_pos;
// 16 bytes each, totaling 64 bytes
layout(location = 1) in vec4 a_color; // xyzw: color
layout(location = 2) in vec4 a_slot1; // x: tag, yzw: data[0-2]
layout(location = 3) in vec4 a_slot2; // xyzw: data[3-6]
layout(location = 4) in vec4 a_slot3; // xyzw: data[7-10]

// Uniforms
uniform mat4 u_projection;
uniform float u_radial_falloff;

// Outputs to fragment shader
out vec2 v_world_pos;
out vec4 v_color;
flat out vec4 v_slot1;
flat out vec4 v_slot2;
flat out vec4 v_slot3;

// Utility to get the tag
int get_tag() {
    return int(a_slot1[0]);
}

float get_radius() {
    return a_slot1[1];
}

// Replicate Odin Structs
struct Circle {
    vec2 center;
};
Circle unpack_circle() {
    return Circle(
        a_slot1.zw // center
    );
}

struct Capsule {
    vec2 start;
    vec2 end;
};
Capsule unpack_capsule() {
    return Capsule(
        a_slot1.zw, // start
        a_slot2.xy // end
    );
}

struct Rhombus {
    vec2 start;
    vec2 end;
    float radius_end;
};
Rhombus unpack_rhombus() {
    return Rhombus(
        a_slot1.zw, // start
        a_slot2.xy, // end
        a_slot2.z // radius_end
    );
}

struct Triangle {
    vec2 a;
    vec2 b;
    vec2 c;
};
Triangle unpack_triangle() {
    return Triangle(
        a_slot1.zw, // a
        a_slot2.xy, // b
        a_slot2.zw // c
    );
}

struct Bezier {
    vec2 a;
    vec2 b;
    vec2 ctrl;
};
Bezier unpack_bezier() {
    return Bezier(
        a_slot1.zw, // a
        a_slot2.xy, // b
        a_slot2.zw // ctrl
    );
}

void main() {
    int tag = get_tag();
    vec2 world_pos = vec2(0.0);

    float radius = get_radius();

    // --- BOUNDING BOX EXPANSION LOGIC ---
    // We transform the [-0.5, 0.5] quad into a box covering the primitive + radius
    float MARGIN = 3.0 * u_radial_falloff;

    v_color = a_color;
    switch (tag) {
        case 0:
        { // CIRCLE
            Circle c = unpack_circle();
            // Scale quad to diameter + small buffer for falloff
            float size = (radius + MARGIN) * 2.0;
            world_pos = c.center + (a_unit_pos * size);
            break;
        }
        case 1:
        { // CAPSULE
            Capsule cap = unpack_capsule();
            vec2 dir = cap.end - cap.start;
            float len = length(dir);
            vec2 unit_dir = (len > 0.0) ? dir / len : vec2(1.0, 0.0);
            vec2 norm = vec2(-unit_dir.y, unit_dir.x);
            vec2 segment_center = (cap.start + cap.end) * 0.5;
            // Total radius including the soft falloff tail
            float total_r = radius + MARGIN;
            // Total dimensions of the box
            float half_length = (len * 0.5) + total_r;
            float half_width = total_r;
            world_pos = segment_center +
                    (norm * a_unit_pos.x * 2.0 * half_width) +
                    (unit_dir * a_unit_pos.y * 2.0 * half_length);

            break;
        }
        case 2:
        { // RHOMBUS (Tapered Capsule)
            Rhombus rho = unpack_rhombus();
            vec2 dir = rho.end - rho.start;
            float len = length(dir);
            vec2 unit_dir = (len > 0.0) ? dir / len : vec2(1.0, 0.0);
            vec2 norm = vec2(-unit_dir.y, unit_dir.x);
            vec2 segment_center = (rho.start + rho.end) * 0.5;
            // Total radius including the soft falloff tail
            float total_r = max(radius, rho.radius_end) + MARGIN;
            // Total dimensions of the box
            float half_length = (len * 0.5) + total_r;
            float half_width = total_r;
            world_pos = segment_center +
                    (norm * a_unit_pos.x * 2.0 * half_width) +
                    (unit_dir * a_unit_pos.y * 2.0 * half_length);
            break;
        }
        case 3:
        { // TRIANGLE
            Triangle tri = unpack_triangle();
            // Axis Aligned Bounding Box for the triangle vertices
            float total_padding = radius + MARGIN;
            vec2 min_p = min(tri.a, min(tri.b, tri.c)) - total_padding;
            vec2 max_p = max(tri.a, max(tri.b, tri.c)) + total_padding;

            vec2 center = (min_p + max_p) * 0.5;
            vec2 size = max_p - min_p;
            world_pos = center + (a_unit_pos * size);
            break;
        }
        case 4:
        { // BEZIER
            Bezier bez = unpack_bezier();
            // AABB containing start, end, and control point
            float total_padding = radius + MARGIN;
            vec2 min_p = min(bez.a, min(bez.b, bez.ctrl)) - total_padding;
            vec2 max_p = max(bez.a, max(bez.b, bez.ctrl)) + total_padding;

            vec2 center = (min_p + max_p) * 0.5;
            vec2 size = max_p - min_p;
            world_pos = center + (a_unit_pos * size);
            break;
        }
    }

    v_slot1 = a_slot1;
    v_slot2 = a_slot2;
    v_slot3 = a_slot3;
    v_world_pos = world_pos;
    gl_Position = u_projection * vec4(world_pos, 0.0, 1.0);
}
