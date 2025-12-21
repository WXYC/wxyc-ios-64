//
//  TorusRings.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// === MTKView Support ===
struct Uniforms {
    float2 resolution;
    float time;
    float displayScale;
    float audioLevel;
    float audioBass;
    float audioMid;
    float audioHigh;
    float audioBeat;
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Rotation helper
static inline float3 rotateR(float3 p, float3 a, float r) {
    return mix(a * dot(p, a), p, cos(r)) + sin(r) * cross(p, a);
}

// Hue to RGB
static inline float3 hueH(float h) {
    return cos(h * 6.3f + float3(0.0f, 23.0f, 21.0f)) * 0.5f + 0.5f;
}

// Core implementation
static half4 torusRingsImpl(float2 position, float width, float height, float time) {
    float2 C = position;
    float3 r = float3(width, height, height);
    float t = time;

    float4 O = float4(0.0f);

    // Ray direction
    float3 d = normalize(float3(C - 0.5f * r.xy, r.y));

    float g = 0.0f;
    float e = 0.0f;
    float z = 0.0f;
    float f = 0.0f;

    for (float i = 0.0f; i < 80.0f; i += 1.0f) {
        float3 p = d * g;
        p.z -= 1.5f;

        // Rotate with animated hue-based axis
        float3 axis = normalize(hueH(t * 0.02f) - 0.5f);
        p = rotateR(p, axis, t * 0.1f);

        z = p.z + t;

        // Cell hash
        float3 u = floor((p - 2.0f) / 4.0f);
        u = sin(9.0f * (2.6f * u + 3.0f * float3(u.y, u.z, u.x) + 1e-3f));
        f = dot(u, float3(u.y, u.x, u.z));

        // Repeat space
        p = fmod(p - 2.0f + 4000.0f, 4.0f) - 2.0f;

        // Twisted torus
        float angle = atan2(p.y, p.x) / 3.14159265f * 0.2f;
        p.z = fmod(p.z + angle + 0.4f + 4000.0f, 0.4f) - 0.2f;

        // Torus SDF
        float torusDist = length(float2(length(p.xy) - 0.4f, p.z)) - 0.04f;
        e = abs(torusDist) + 0.01f * (sin(z + f + t) * 0.5f + 0.5f);

        g += e;

        // Accumulate glow
        float3 col = mix(float3(1.0f), hueH(z), 0.6f);
        O.xyz += col * 0.05f / exp(0.3f * i * i * e);
    }

    return half4(half3(O.xyz), 1.0h);
}

[[ stitchable ]]
half4 torusRings(float2 position, half4 inColor, float width, float height, float time) {
    return torusRingsImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 torusRingsFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return torusRingsImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
