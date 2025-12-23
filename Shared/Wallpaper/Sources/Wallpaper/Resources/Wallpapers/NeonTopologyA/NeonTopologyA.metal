//
//  NeonTopologyA.metal
//  Wallpaper
//
//  Option A: Algorithmic optimizations
//  - Reduced octaves (3 -> 2)
//  - Reduced edge samples (4 -> 2 diagonal)
//  - Reused center noise for background blend
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

// Fast quantize helper
static inline float quantize10(float v) {
    return floor((v + 1.0f) * 5.0f) * 0.1f;
}

// Core implementation - optimized for performance
static half4 neonTopologyAImpl(float2 position, float width, float height, float time) {
    float aspect = width / height;
    float invWidth = 1.0f / width;
    float invHeight = 1.0f / height;

    // Precompute scaled position
    float2 pos = float2(position.x * invWidth * aspect, position.y * invHeight);

    // Neighbor offsets (scaled)
    float dx = invWidth * aspect;
    float dy = invHeight;

    uint seed = 0x578437adU;
    float z = time * 0.01f;
    int freq = 5;
    int octave = 2;  // Reduced from 3 to 2
    float persistence = 0.5f;
    float lacunarity = 2.0f;

    // Center noise - compute once, reuse for background blend and edge detection
    float rawValue = perlinNoiseOctaves(float3(pos, z), freq, octave, persistence, lacunarity, seed);
    float valueback = (rawValue + 1.0f) * 0.5f;
    float value = floor(valueback * 10.0f) * 0.1f;

    // Edge detection with 2-sample diagonal (cheaper than 4-sample Laplacian)
    float2 posTR = pos + float2(dx, -dy);
    float2 posBL = pos + float2(-dx, dy);

    float valueTR = quantize10(perlinNoiseOctaves(float3(posTR, z), freq, octave, persistence, lacunarity, seed));
    float valueBL = quantize10(perlinNoiseOctaves(float3(posBL, z), freq, octave, persistence, lacunarity, seed));

    // Simple edge detection: difference from neighbors
    float edge = abs(value - valueTR) + abs(value - valueBL);
    edge = step(0.01f, edge);  // Binary threshold

    // Color blending with half precision
    half3 purple = half3(1.0h, 0.0h, 1.0h);
    half3 cyan = half3(0.0h, 1.0h, 1.0h);
    half blend = half(valueback);

    half3 edgeColor = mix(cyan, purple, blend) * half(edge);
    half3 baseColor = half3(0.0h, 0.0h, half(value) * 0.2h);

    return half4(edgeColor + baseColor, 1.0h);
}

[[ stitchable ]]
half4 neonTopologyA(float2 position, half4 inColor, float width, float height, float time) {
    return neonTopologyAImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 neonTopologyAFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return neonTopologyAImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
