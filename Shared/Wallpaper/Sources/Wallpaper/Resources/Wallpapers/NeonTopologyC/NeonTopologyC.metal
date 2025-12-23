//
//  NeonTopologyC.metal
//  Wallpaper
//
//  Option C: Texture-based noise for maximum performance
//  Uses precomputed 256x256 noise texture instead of procedural Perlin
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
constant float INV_256 = 0.00390625f;  // 1.0 / 256.0
constant float2 NOISE_OFFSET = float2(37.0f, 17.0f);

// 3D noise sampling from 2D texture (adapted from LavaLite)
static inline float2 sampleNoise3D(float3 x, texture2d<float> noiseTex, sampler s) {
    float3 p = floor(x);
    float3 f = x - p;
    f = f * f * (3.0f - 2.0f * f);  // Smoothstep

    float2 uv = p.xy + NOISE_OFFSET * p.z + f.xy;

    // Sample noise texture at two positions for z-interpolation
    float4 rg = noiseTex.sample(s, (uv + 0.5f) * INV_256);
    float4 rg2 = noiseTex.sample(s, (uv + float2(-36.5f, -16.5f)) * INV_256);

    return mix(rg2.xz, rg.xz, f.z);
}

// Single-sample noise for faster edge detection
static inline float sampleNoise2D(float2 uv, float z, texture2d<float> noiseTex, sampler s) {
    float2 noise = sampleNoise3D(float3(uv, z), noiseTex, s);
    return noise.x;  // Use just one channel
}

fragment half4 neonTopologyCFrag(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    texture2d<float> noiseTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float aspect = u.resolution.x / u.resolution.y;

    // UV with aspect correction
    float2 uv = in.uv;
    uv.x *= aspect;

    // Scale for noise sampling (similar visual scale to original)
    float noiseScale = 5.0f;
    float z = u.time * 0.05f;  // Slightly faster since texture noise is smoother

    // Sample center noise
    float2 noiseCoord = uv * noiseScale;
    float rawNoise = sampleNoise2D(noiseCoord, z, noiseTex, s);

    // Background value (continuous) - reuse center sample
    float valueback = rawNoise;

    // Quantized value for edge detection
    float value = floor(rawNoise * 10.0f) * 0.1f;

    // Edge detection with diagonal samples
    float dx = 1.0f / u.resolution.x * aspect * noiseScale;
    float dy = 1.0f / u.resolution.y * noiseScale;

    float2 uvTR = noiseCoord + float2(dx, -dy);
    float2 uvBL = noiseCoord + float2(-dx, dy);

    float valueTR = floor(sampleNoise2D(uvTR, z, noiseTex, s) * 10.0f) * 0.1f;
    float valueBL = floor(sampleNoise2D(uvBL, z, noiseTex, s) * 10.0f) * 0.1f;

    // Edge detection
    float edge = abs(value - valueTR) + abs(value - valueBL);
    edge = step(0.01f, edge);

    // Color blending
    half3 purple = half3(1.0h, 0.0h, 1.0h);
    half3 cyan = half3(0.0h, 1.0h, 1.0h);
    half blend = half(valueback);

    half3 edgeColor = mix(cyan, purple, blend) * half(edge);
    half3 baseColor = half3(0.0h, 0.0h, half(value) * 0.2h);

    return half4(edgeColor + baseColor, 1.0h);
}
