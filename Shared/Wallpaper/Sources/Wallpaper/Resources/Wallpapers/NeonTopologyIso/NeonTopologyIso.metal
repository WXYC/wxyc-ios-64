//
//  NeonTopologyIso.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/22/2025
//  Translated from https://www.shadertoy.com/view/dtccWB
//
//  Strategy: single-sample isolines (no neighbor-based edge detection)
//  - 1 noise eval per pixel (perlinNoiseOctaves at center)
//  - Derivative-based AA width for stable, even strokes
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// === MTKView Support ===
struct Uniforms {
    float2 resolution;
    float time;
    float displayScale;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// MurmurHash based hashing
static inline uint hashUint(uint x, uint seed) {
    const uint m = 0x5bd1e995U;
    uint hash = seed;
    uint k = x;
    k *= m;
    k ^= k >> 24;
    k *= m;
    hash *= m;
    hash ^= k;
    hash ^= hash >> 13;
    hash *= m;
    hash ^= hash >> 15;
    return hash;
}

static inline uint hashUint3(uint3 x, uint seed) {
    const uint m = 0x5bd1e995U;
    uint hash = seed;
    // Process x
    uint k = x.x;
    k *= m;
    k ^= k >> 24;
    k *= m;
    hash *= m;
    hash ^= k;
    // Process y
    k = x.y;
    k *= m;
    k ^= k >> 24;
    k *= m;
    hash *= m;
    hash ^= k;
    // Process z
    k = x.z;
    k *= m;
    k ^= k >> 24;
    k *= m;
    hash *= m;
    hash ^= k;
    // Final mixing
    hash ^= hash >> 13;
    hash *= m;
    hash ^= hash >> 15;
    return hash;
}

static inline float3 gradientDirection(uint hash) {
    switch (int(hash) & 15) {
        case 0: return float3(1, 1, 0);
        case 1: return float3(-1, 1, 0);
        case 2: return float3(1, -1, 0);
        case 3: return float3(-1, -1, 0);
        case 4: return float3(1, 0, 1);
        case 5: return float3(-1, 0, 1);
        case 6: return float3(1, 0, -1);
        case 7: return float3(-1, 0, -1);
        case 8: return float3(0, 1, 1);
        case 9: return float3(0, -1, 1);
        case 10: return float3(0, 1, -1);
        case 11: return float3(0, -1, -1);
        case 12: return float3(1, 1, 0);
        case 13: return float3(-1, 1, 0);
        case 14: return float3(0, -1, 1);
        default: return float3(0, -1, -1);
    }
}

static inline float interpolate8(float v1, float v2, float v3, float v4,
                                  float v5, float v6, float v7, float v8, float3 t) {
    return mix(
        mix(mix(v1, v2, t.x), mix(v3, v4, t.x), t.y),
        mix(mix(v5, v6, t.x), mix(v7, v8, t.x), t.y),
        t.z
    );
}

static inline float3 fade(float3 t) {
    return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
}

static inline float perlinNoise(float3 position, uint seed) {
    float3 floorPos = floor(position);
    float3 fractPos = position - floorPos;
    uint3 cell = uint3(floorPos);

    float v1 = dot(gradientDirection(hashUint3(cell, seed)), fractPos);
    float v2 = dot(gradientDirection(hashUint3(cell + uint3(1, 0, 0), seed)), fractPos - float3(1, 0, 0));
    float v3 = dot(gradientDirection(hashUint3(cell + uint3(0, 1, 0), seed)), fractPos - float3(0, 1, 0));
    float v4 = dot(gradientDirection(hashUint3(cell + uint3(1, 1, 0), seed)), fractPos - float3(1, 1, 0));
    float v5 = dot(gradientDirection(hashUint3(cell + uint3(0, 0, 1), seed)), fractPos - float3(0, 0, 1));
    float v6 = dot(gradientDirection(hashUint3(cell + uint3(1, 0, 1), seed)), fractPos - float3(1, 0, 1));
    float v7 = dot(gradientDirection(hashUint3(cell + uint3(0, 1, 1), seed)), fractPos - float3(0, 1, 1));
    float v8 = dot(gradientDirection(hashUint3(cell + uint3(1, 1, 1), seed)), fractPos - float3(1, 1, 1));

    return interpolate8(v1, v2, v3, v4, v5, v6, v7, v8, fade(fractPos));
}

static inline float perlinNoiseOctaves(float3 position, int freq, int octaves,
                                        float persistence, float lacunarity, uint seed) {
    float value = 0.0f;
    float amplitude = 1.0f;
    float currentFreq = float(freq);
    uint currentSeed = seed;

    for (int i = 0; i < octaves; i++) {
        currentSeed = hashUint(currentSeed, 0x0U);
        value += perlinNoise(position * currentFreq, currentSeed) * amplitude;
        amplitude *= persistence;
        currentFreq *= lacunarity;
    }
    return value;
}

// Core implementation - isoline-based "topology" strokes (no neighbor samples)
static half4 neonTopologyIsoImpl(float2 position, float width, float height, float time) {
    float aspect = width / height;
    float invWidth = 1.0f / width;
    float invHeight = 1.0f / height;

    float2 pos = float2(position.x * invWidth * aspect, position.y * invHeight);

    uint seed = 0x578437adU;
    float z = time * 0.01f;
    int freq = 5;
    int octave = 2;
    float persistence = 0.5f;
    float lacunarity = 2.0f;

    float raw = perlinNoiseOctaves(float3(pos, z), freq, octave, persistence, lacunarity, seed);
    float valueback = (raw + 1.0f) * 0.5f; // [0,1]

    // 10 bands -> draw strokes along band boundaries.
    float t = valueback * 10.0f;
    float ft = fract(t);
    float d = min(ft, 1.0f - ft); // distance to nearest boundary in "t-space"

    // Derivative-based AA / thickness in t-space.
    // (use abs(dfdx)+abs(dfdy) for compatibility; fwidth(t) would also work)
    float w = abs(dfdx(t)) + abs(dfdy(t));
    w = clamp(w * 1.25f, 0.0025f, 0.05f);

    float edge = 1.0f - smoothstep(0.0f, w, d);

    half3 purple = half3(1.0h, 0.0h, 1.0h);
    half3 cyan = half3(0.0h, 1.0h, 1.0h);
    half blend = half(valueback);

    half3 edgeColor = mix(cyan, purple, blend) * half(edge);

    float q = floor(valueback * 10.0f) * 0.1f;
    half3 baseColor = half3(0.0h, 0.0h, half(q) * 0.2h);

    return half4(edgeColor + baseColor, 1.0h);
}

[[ stitchable ]]
half4 neonTopologyIso(float2 position, half4 inColor, float width, float height, float time) {
    return neonTopologyIsoImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 neonTopologyIsoFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return neonTopologyIsoImpl(pos, u.resolution.x, u.resolution.y, u.time);
}

