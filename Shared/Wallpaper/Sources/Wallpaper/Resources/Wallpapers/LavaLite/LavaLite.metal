//
//  LavaLite.metal
//  Wallpaper
//
//  Translated from Shadertoy by Hazel Quantock - 2013
//  License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
//
//  Created by Jake Bromberg on 12/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float time;
    float lod;  // 0.0 to 1.0: at low LOD, simplifies blob calculation
};

struct Parameters {
    float brightness;
    float pad1, pad2, pad3, pad4, pad5, pad6, pad7;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Precomputed constants
constant float INV_GAMMA = 0.45454545f;        // 1.0 / 2.2
constant float SQRT3_HALF = 0.86602540378f;    // sqrt(3.0) * 0.5
constant float INV_256 = 0.00390625f;          // 1.0 / 256.0
constant float2 NOISE_OFFSET = float2(37.0f, 17.0f);
constant float2 NOISE_OFFSET2 = float2(-36.5f, -16.5f);  // -37+0.5, -17+0.5

// 3D noise sampling from 2D texture
static inline float2 Noise(float3 x, texture2d<float> noiseTex, sampler s) {
    float3 p = floor(x);
    float3 f = x - p;
    f = f * f * (3.0f - 2.0f * f);  // Smoothstep

    float2 uv = p.xy + NOISE_OFFSET * p.z + f.xy;

    // Sample noise texture at two positions
    float4 rg = noiseTex.sample(s, (uv + 0.5f) * INV_256);
    float4 rg2 = noiseTex.sample(s, (uv + NOISE_OFFSET2) * INV_256);

    return mix(rg2.xz, rg.xz, f.z);
}

fragment float4 lavaLiteFragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    constant Parameters& p [[buffer(1)]],
    texture2d<float> noiseTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    // Centered UV with aspect correction
    float2 uv = (in.uv - 0.5f) * float2(1.0f, u.resolution.y / u.resolution.x);

    // Build noise coordinate
    float3 noiseCoord = float3(uv.x, uv.y * SQRT3_HALF, uv.y * 0.5f) * 4.0f;
    noiseCoord.yz += u.time * float2(-0.1f, 0.1f);

    float2 blob = Noise(noiseCoord, noiseTex, s);

    // Lava lamp ink colors
    const float3 ink1 = float3(0.1f, 0.9f, 0.8f);
    const float3 ink2 = float3(0.9f, 0.1f, 0.6f);

    // Create colored blobs with soft edges
    // Use fast::sqrt and powr (positive base) for performance
    float exp1 = 4.0f * fast::sqrt(max(0.0f, (blob.x - 0.6f) * 2.0f));
    float3 col1 = powr(ink1, float3(exp1));

    float3 color;
    if (u.lod >= 0.5f) {
        // Full quality: both blob colors with gamma correction
        float exp2 = 4.0f * fast::sqrt(max(0.0f, (blob.y - 0.6f) * 2.0f));
        float3 col2 = powr(ink2, float3(exp2));
        color = powr(1.0f - col1 * col2, float3(INV_GAMMA));
    } else {
        // Low LOD: skip second blob, simplified output
        color = powr(1.0f - col1, float3(INV_GAMMA));
    }

    // Apply brightness adjustment
    color *= p.brightness;

    return float4(color, 1.0f);
}
