//
//  Lamp4D.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//  Simplex noise based colorful lamp effect
//  Ported from shadertoy https://www.shadertoy.com/view/3lKBD3
//  Copyright © 2013 Inigo Quilez
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// === Feature Toggles (comment/uncomment to test performance) ===
#define ENABLE_UV_ROTATION        // Main UV space rotation
#define ENABLE_NOISE_OFFSET_ROTATION  // Rotation in noise4 loop
#define ENABLE_CYAN_ROTATION      // Cyan layer rotation
#define ENABLE_MAGENTA_ROTATION   // Magenta layer rotation

// Noise quality (reduce for performance)
#define NOISE_OCTAVES 4  // Original: 7, try 3-4 for better perf

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

static inline float2 hash2D(float2 p) {
    p = float2(dot(p, float2(127.1f, 311.7f)), dot(p, float2(269.5f, 183.3f)));
    return -1.0f + 2.0f * fract(fast::sin(p) * 43758.5453123f);
}

static inline float simplexNoise(float2 p) {
    const float K1 = 0.366025404f; // (sqrt(3)-1)/2
    const float K2 = 0.211324865f; // (3-sqrt(3))/6

    float2 i = floor(p + (p.x + p.y) * K1);
    float2 a = p - i + (i.x + i.y) * K2;
    float m = step(a.y, a.x);
    float2 o = float2(m, 1.0f - m);
    float2 b = a - o + K2;
    float2 c = a - 1.0f + 2.0f * K2;
    float3 h = max(0.5f - float3(dot(a, a), dot(b, b), dot(c, c)), 0.0f);
    float3 n = h * h * h * h * float3(dot(a, hash2D(i + 0.0f)),
                                       dot(b, hash2D(i + o)),
                                       dot(c, hash2D(i + 1.0f)));
    return dot(n, float3(70.0f));
}

static inline float maximum(float3 p) {
    return max(max(p.x, p.y), p.z);
}

static inline float minimum(float3 p) {
    return min(min(p.x, p.y), p.z);
}

static inline float3 normalize2(float3 grosscolor) {
    grosscolor = grosscolor * grosscolor * grosscolor;
    float maxVal = maximum(grosscolor);
    float minVal = minimum(grosscolor);
    return grosscolor / (maxVal + minVal);
}

static inline float2 rotate(float2 oldpoint, float s, float c) {
    float left = c * oldpoint.x - s * oldpoint.y;
    float right = s * oldpoint.x + c * oldpoint.y;
    return float2(left, right);
}

static inline float noise4(float2 uv, float time, float2 offset) {
    float f = 0.5f;
    float frequency = 1.75f;
    float amplitude = 0.5f;

    for (int i = 0; i < NOISE_OCTAVES; i++) {
        f += amplitude * simplexNoise(frequency * uv - offset);
        frequency *= 2.0f;
        amplitude *= 0.5f;
    }
    return f;
}

// Core implementation
static half4 lamp4DImpl(float2 position, float width, float height, float time) {
    time /= 9.0;
    float2 iResolution = float2(width, height);
    float2 p = position / iResolution;
    float2 uv = p * float2(iResolution.x / iResolution.y, 0.8f);

    // Precompute all trig and log values
    float logTime = fast::log(time + 3.0f);
    float logTimePlus1 = fast::log(time + 1.0f);

    // Precompute noise offset (moved out of loop)
#ifdef ENABLE_NOISE_OFFSET_ROTATION
    float offsetAngle = time / 9999.0f;
    float offsetS = fast::sin(offsetAngle);
    float offsetC = fast::cos(offsetAngle);
    float2 baseOffset = float2(logTime, logTime / 999.0f);
    float2 noiseOffset = rotate(baseOffset, offsetS, offsetC);
#else
    float2 noiseOffset = float2(logTime, logTime / 999.0f);
#endif

#ifdef ENABLE_UV_ROTATION
    float uvAngle = fast::log(time) / -7.0f;
    float uvS = fast::sin(uvAngle);
    float uvC = fast::cos(uvAngle);
    uv = rotate(uv, uvS, uvC);
#endif

    // Precompute rotation values for cyan and magenta
#ifdef ENABLE_CYAN_ROTATION
    float cyanAngle = fast::sin(time / 11.0f);
    float cyanS = fast::sin(cyanAngle);
    float cyanC = fast::cos(cyanAngle);
#endif

#ifdef ENABLE_MAGENTA_ROTATION
    float magentaAngle = time / 7.0f;
    float magentaS = fast::sin(magentaAngle);
    float magentaC = fast::cos(magentaAngle);
#endif

    float interval = 10.0f;
    float3 dblue = interval * float3(1.8f, 2.6f, 2.6f);
    float3 cyan = interval * float3(0.0f, 2.1f, 2.0f);
    float3 magenta = interval * float3(1.8f, 1.0f, 1.8f);

    float3 color = float3(0.75f);

    // Cache frequently used noise values
    float noiseUV = noise4(uv, time, noiseOffset);

    // Blue layer
    float f = noise4(uv + noiseUV * (logTimePlus1 + (time / 60.0f)), time, noiseOffset);
    color += f * normalize2(dblue);

    // Cyan layer
#ifdef ENABLE_CYAN_ROTATION
    float2 cyanUV = rotate(uv, cyanS, cyanC);
#else
    float2 cyanUV = uv;
#endif
    float noiseFUV = noise4(f * uv, time, noiseOffset);
    f = noise4(f * cyanUV + f * noiseFUV, time, noiseOffset);
    color += f * normalize2(cyan);

    // Magenta layer
#ifdef ENABLE_MAGENTA_ROTATION
    float2 magentaUV = rotate(uv, magentaS, magentaC);
#else
    float2 magentaUV = uv;
#endif
    // Reuse cached noiseUV instead of computing noise4(uv, time) twice
    f = noise4(f * magentaUV + f * noiseUV * noiseUV, time, noiseOffset);
    color += f * normalize2(magenta);

    color = normalize2(color);

    return half4(half3(color), 1.0h);
}

[[ stitchable ]]
half4 lamp4D(float2 position, half4 inColor, float width, float height, float time) {
    return lamp4DImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 lamp4DFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return lamp4DImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
