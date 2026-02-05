#version 300 es

const bool debug_mode = false;

precision highp float;

// Uniforms
uniform float u_radial_falloff;

flat in vec4 v_slot1;
flat in vec4 v_slot2;
flat in vec4 v_slot3;
in vec2 v_world_pos;
in vec4 v_color;

out vec4 outColor;

int get_tag() {
    return int(v_slot1[0]);
}

float get_radius() {
    return v_slot1[1];
}

// Replicate Odin Structs
struct Circle {
    vec2 center;
};
Circle unpack_circle() {
    return Circle(
        v_slot1.zw // center
    );
}

struct Capsule {
    vec2 start;
    vec2 end;
};
Capsule unpack_capsule() {
    return Capsule(
        v_slot1.zw, // start
        v_slot2.xy // end
    );
}

struct Rhombus {
    vec2 start;
    vec2 end;
    float radius_end;
};
Rhombus unpack_rhombus() {
    return Rhombus(
        v_slot1.zw, // start
        v_slot2.xy, // end
        v_slot2.z // radius_end
    );
}

struct Triangle {
    vec2 a;
    vec2 b;
    vec2 c;
};
Triangle unpack_triangle() {
    return Triangle(
        v_slot1.zw, // a
        v_slot2.xy, // b
        v_slot2.zw // c
    );
}

struct Bezier {
    vec2 a;
    vec2 b;
    vec2 ctrl;
};
Bezier unpack_bezier() {
    return Bezier(
        v_slot1.zw, // a
        v_slot2.xy, // b
        v_slot2.zw // ctrl
    );
}

// --- SDF Math Functions ---
float sdCircle(vec2 p, vec2 center, float r) {
    return length(p - center) - r;
}

float sdCapsule(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

float sdRhombus(vec2 p, vec2 a, vec2 b, float r1, float r2) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    // Linearly interpolate radius along the segment
    float r = mix(r1, r2, h);
    return length(pa - ba * h) - r;
}

float sdTriangle(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 e0 = b - a, e1 = c - b, e2 = a - c;
    vec2 v0 = p - a, v1 = p - b, v2 = p - c;
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
            vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// Approximate Bezier SDF (much cheaper than analytical)
float sdBezier(vec2 pos, vec2 A, vec2 B, vec2 C) {
    const int steps = 8;
    float minDistSq = 1e10;
    vec2 prev = A;
    for (int i = 1; i <= steps; i++) {
        float t = float(i) / float(steps);
        float invT = 1.0 - t;
        vec2 curr = invT * invT * A + 2.0 * invT * t * C + t * t * B;
        // Distance to line segment
        vec2 pa = pos - prev, ba = curr - prev;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        minDistSq = min(minDistSq, dot(pa - ba * h, pa - ba * h));
        prev = curr;
    }
    return sqrt(minDistSq);
}

void main() {
    int tag = get_tag();
    float d = 1e10;

    float radius = get_radius();
    switch (tag) {
        case 0:
        {
            Circle c = unpack_circle();
            d = sdCircle(v_world_pos, c.center, radius);
            break;
        }
        case 1:
        {
            Capsule cap = unpack_capsule();
            d = sdCapsule(v_world_pos, cap.start, cap.end, radius);
            break;
        }
        case 2:
        {
            Rhombus rho = unpack_rhombus();
            d = sdRhombus(v_world_pos, rho.start, rho.end, radius, rho.radius_end);
            break;
        }
        case 3:
        {
            Triangle tri = unpack_triangle();
            d = sdTriangle(v_world_pos, tri.a, tri.b, tri.c) - radius;
            break;
        }
        case 4:
        {
            Bezier bez = unpack_bezier();
            d = sdBezier(v_world_pos, bez.a, bez.b, bez.ctrl) - radius;
            break;
        }
    }

    float margin = 3.0 * u_radial_falloff;
    if (d > margin) {
        if (debug_mode) {
            outColor = vec4(1.0, 0.0, 0.0, 1.0);
            return;
        } else {
            // We only care about the density inside the influence zone
            discard; // Optimization: early out for pixels far from surface
        }
    }

    // d is the signed distance from your SDF
    // sigma controls the spread (smaller = sharper/tighter)
    float pdist = max(0.0, d);
    float density = exp(-(pdist * pdist) / (2.0 * u_radial_falloff * u_radial_falloff));

    // Output weighted color for additive blending
    // Result = SourceColor * Density + DestColor
    outColor = vec4(v_color.rgb * density, v_color.a * density);
}
