//
//  Fractal66.metal
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
static half4 fractal66Impl(float2 position, float width, float height, float time) {
    float2 C = position;
    float3 r = float3(width, height, height);

    float4 O = float4(0.0f);

    // Ray direction
    float3 d = normalize(float3((C - 0.5f * r.xy) / r.y, 1.0f));

    float g = 0.3f;

    for (float i = 0.0f; i < 90.0f; i += 1.0f) {
        float3 p = g * d;
        p += float3(0.3f, 0.3f, -1.8f);
        p = rotateR(p, float3(0.577f), time * 0.1f);
        p = cos(p * 3.0f + 3.0f * cos(p * 0.3f));

        float s = 3.0f;
        float e = 0.0f;

        for (int j = 0; j < 8; j++) {
            p = clamp(p, -0.5f, 0.5f) * 2.0f - p;
            e = 7.0f * clamp(0.3f / min(dot(p, p), 1.0f), 0.0f, 1.0f);
            s *= e;
            p *= e;
        }

        e = length(p) / s;
        g += e;

        // Accumulate color
        float3 col = mix(float3(1.0f), hueH(log(s) * 0.3f), 0.8f);
        O.xyz += col * 0.03f * exp(-i * i * e);
    }

    return half4(half3(O.xyz), 1.0h);
}

[[ stitchable ]]
half4 fractal66(float2 position, half4 inColor, float width, float height, float time) {
    return fractal66Impl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 fractal66Frag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return fractal66Impl(pos, u.resolution.x, u.resolution.y, u.time);
}
