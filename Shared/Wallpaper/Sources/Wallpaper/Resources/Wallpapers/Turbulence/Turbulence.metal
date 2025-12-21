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

// Core implementation
static half4 turbulenceImpl(float2 position, float width, float height, float time) {
    float2 r = float2(width, height);
    float2 C = position;
    float t = 0.1f * time;

    // Per-pixel noise to reduce banding
    float z = 0.1f * fract(dot(C, sin(C)));

    float4 o = float4(0.0f);

    // Precompute ray direction (moved outside loop)
    float3 rayDir = normalize(float3(C - 0.5f * r, r.y));
    float t06 = 0.6f * t;

    for (int i = 0; i < 30; i++) {
        // Convert 2D screen coordinate to 3D ray direction
        float4 p = float4(z * rayDir, 0.0f);

        // Offset the ray origin
        p.xy += 6.0f;
        p.z += t;

        // Save original position
        float4 P = p;

        // Turbulence generation - unrolled loop (was while d < 7.0)
        // d = 4.0, 5.0, 6.25 (3 iterations)
        p += cos(float4(p.z, p.x, p.y, p.w) * 4.0f + t06) * 0.25f;
        p += cos(float4(p.z, p.x, p.y, p.w) * 5.0f + t06) * 0.2f;
        p += cos(float4(p.z, p.x, p.y, p.w) * 6.25f + t06) * 0.16f;

        // Lighting/color calculation
        P = 1.2f + sin(float4(0.0f, 1.0f, 2.0f, 0.0f) + 9.0f * length(P - p));

        // Distance field - create 3D grid/lattice pattern
        p -= round(p);

        // Cross distance field - use single min chain
        float d = abs(min(length(p.yz), min(length(p.xy), length(p.xz))) - 0.1f * tanh(z) + 2e-2f);

        // Accumulate lighting
        o += P.w / max(d, 1e-3f) * P;

        // Advance ray position
        z += 0.2f * d + 1e-3f;
    }

    // Tone mapping - adjusted for fewer iterations
    float4 result = tanh(o / 1.2e4f);

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
