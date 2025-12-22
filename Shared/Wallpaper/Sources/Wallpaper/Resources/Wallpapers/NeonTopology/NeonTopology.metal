//
//  NeonTopology.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//  Perlin noise based topology with neon edge detection
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

static inline float lum(float3 c) {
    return c.x * 0.3f + c.y * 0.59f + c.z * 0.11f;
}

// Core implementation
static half4 neonTopologyImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);

    float2 pos = position / iResolution;
    float2 post = float2(position.x, position.y - 1.0f) / iResolution;
    float2 posb = float2(position.x, position.y + 1.0f) / iResolution;
    float2 posl = float2(position.x - 1.0f, position.y) / iResolution;
    float2 posr = float2(position.x + 1.0f, position.y) / iResolution;

    float aspect = iResolution.x / iResolution.y;
    pos.x *= aspect;
    post.x *= aspect;
    posb.x *= aspect;
    posl.x *= aspect;
    posr.x *= aspect;

    uint seed = 0x578437adU;
    float z = time * 0.01f;
    int freq = 5;
    int octave = 3;
    float persistence = 0.5f;
    float lacunarity = 2.0f;

    // Background value (continuous)
    float valueback = perlinNoiseOctaves(float3(pos + float2(100.0f, 100.0f), z),
                                          freq, octave, persistence, lacunarity, seed);
    valueback = (valueback + 1.0f) * 0.5f;

    // Quantized values for edge detection
    float value = perlinNoiseOctaves(float3(pos, z), freq, octave, persistence, lacunarity, seed);
    value = (value + 1.0f) * 0.5f;
    value = floor(value * 10.0f) / 10.0f;

    float valuet = perlinNoiseOctaves(float3(post, z), freq, octave, persistence, lacunarity, seed);
    valuet = floor((valuet + 1.0f) * 0.5f * 10.0f) / 10.0f;

    float valueb = perlinNoiseOctaves(float3(posb, z), freq, octave, persistence, lacunarity, seed);
    valueb = floor((valueb + 1.0f) * 0.5f * 10.0f) / 10.0f;

    float valuel = perlinNoiseOctaves(float3(posl, z), freq, octave, persistence, lacunarity, seed);
    valuel = floor((valuel + 1.0f) * 0.5f * 10.0f) / 10.0f;

    float valuer = perlinNoiseOctaves(float3(posr, z), freq, octave, persistence, lacunarity, seed);
    valuer = floor((valuer + 1.0f) * 0.5f * 10.0f) / 10.0f;

    float lumc = lum(float3(value));
    float lumt = lum(float3(valuet));
    float lumb = lum(float3(valueb));
    float luml = lum(float3(valuel));
    float lumr = lum(float3(valuer));

    float3 purple = float3(1.0f, 0.0f, 1.0f);
    float3 cyan = float3(0.0f, 1.0f, 1.0f);

    // Laplacian edge detection
    float lap = lumt + lumb + lumr + luml - (4.0f * lumc);
    if (lap > 0.01f) lap = 1.0f;

    float3 res = ((purple * valueback) * lap) + ((cyan * (1.0f - valueback)) * lap);
    res = res + (value * float3(0.0f, 0.0f, 0.2f));

    return half4(half3(res), 1.0h);
}

[[ stitchable ]]
half4 neonTopology(float2 position, half4 inColor, float width, float height, float time) {
    return neonTopologyImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 neonTopologyFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return neonTopologyImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
