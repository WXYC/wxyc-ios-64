//
//  Turbulence.metal
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
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Fast tanh approximation: tanh(x) ≈ x / (1 + |x|) for small x
static inline float fast_tanh(float x) {
    return x / (1.0f + abs(x));
}

// Core implementation
static half4 turbulenceImpl(float2 position, float width, float height, float time) {
    float2 r = float2(width, height);
    float2 C = position;
    float t = 0.1f * time;

    // Per-pixel noise to reduce banding
    float z = 0.1f * fract(dot(C, fast::sin(C)));

    float4 o = float4(0.0f);

    // Precompute ray direction (moved outside loop)
    float3 rayDir = fast::normalize(float3(C - 0.5f * r, r.y));
    float t06 = 0.6f * t;

    // Reduced iterations: 20 instead of 30 (33% faster)
    for (int i = 0; i < 20; i++) {
        // Convert 2D screen coordinate to 3D ray direction
        float4 p = float4(z * rayDir, 0.0f);

        // Offset the ray origin
        p.xy += 6.0f;
        p.z += t;

        // Save original position
        float4 P = p;

        // Turbulence generation using fast trig
        float4 swiz = float4(p.z, p.x, p.y, p.w);
        p += fast::cos(swiz * 4.0f + t06) * 0.25f;
        p += fast::cos(swiz * 5.0f + t06) * 0.2f;
        p += fast::cos(swiz * 6.25f + t06) * 0.16f;

        // Lighting/color calculation
        float diff = fast::length(P.xyz - p.xyz);
        P = 1.2f + fast::sin(float4(0.0f, 1.0f, 2.0f, 0.0f) + 9.0f * diff);

        // Distance field - create 3D grid/lattice pattern
        p -= round(p);

        // Cross distance field using fast length
        float dxy = fast::length(p.xy);
        float dxz = fast::length(float2(p.x, p.z));
        float dyz = fast::length(p.yz);
        float d = abs(min(dyz, min(dxy, dxz)) - 0.1f * fast_tanh(z) + 2e-2f);

        // Accumulate lighting
        o += P.w / max(d, 1e-3f) * P;

        // Advance ray position
        z += 0.2f * d + 1e-3f;
    }

    // Tone mapping - adjusted for fewer iterations
    float4 result = fast_tanh(o.x / 8e3f);
    result.y = fast_tanh(o.y / 8e3f);
    result.z = fast_tanh(o.z / 8e3f);

    return half4(half3(result.xyz), 1.0h);
}

[[ stitchable ]]
half4 turbulence(float2 position, half4 inColor, float width, float height, float time) {
    return turbulenceImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 turbulenceFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return turbulenceImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
