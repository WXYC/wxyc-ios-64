//
//  LavaLite.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/21/25.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float time;
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Precomputed constants
constant float INV_GAMMA = 1.0 / 2.2;
constant float SQRT3_HALF = 0.86602540378;  // sqrt(3.0) * 0.5
constant float INV_256 = 1.0 / 256.0;

// Convert to gamma space (values are positive, so use powr)
static inline float3 ToGamma(float3 col) {
    return powr(col, float3(INV_GAMMA));
}

// 3D noise sampling from 2D texture
static inline float2 Noise(float3 x, texture2d<float> noiseTex, sampler s) {
    float3 p = floor(x);
    float3 f = x - p;
    f = f * f * (3.0 - 2.0 * f);

    float2 uv = p.xy + float2(37.0, 17.0) * p.z + f.xy;

    // Sample noise texture (256x256) - use precomputed inverse
    float4 rg = noiseTex.sample(s, (uv + 0.5) * INV_256);
    float4 rg2 = noiseTex.sample(s, (uv - float2(36.5, 16.5)) * INV_256);  // Combined -37+0.5, -17+0.5

    return mix(float2(rg2.x, rg2.z), float2(rg.x, rg.z), f.z);
}

fragment float4 lavaLiteFragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    texture2d<float> noiseTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    // Normalized coordinates centered at screen middle
    float2 uv = (in.uv - 0.5) * float2(1.0, u.resolution.y / u.resolution.x);

    // Sample noise for blob shapes - use precomputed sqrt(3)/2
    float3 noiseCoord = float3(uv.x, uv.y * SQRT3_HALF, uv.y * 0.5) * 4.0;
    noiseCoord += u.time * float3(0.0, -0.1, 0.1);
    float2 blob = Noise(noiseCoord, noiseTex, s);

    // Lava lamp ink colors (cyan-ish and magenta-ish)
    constant float3 ink1 = float3(0.1, 0.9, 0.8);
    constant float3 ink2 = float3(0.9, 0.1, 0.6);

    // Create colored blobs with soft edges - use fast::sqrt, powr for positive values
    float exp1 = 4.0 * fast::sqrt(max(0.0, (blob.x - 0.6) * 2.0));
    float exp2 = 4.0 * fast::sqrt(max(0.0, (blob.y - 0.6) * 2.0));
    float3 col1 = powr(ink1, float3(exp1));
    float3 col2 = powr(ink2, float3(exp2));

    // Combine and apply gamma correction
    return float4(ToGamma(col1 * col2), 1.0);
}
