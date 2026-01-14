//
//  Lamp4D.metal
//  Wallpaper
//
//  Simplex noise based colorful lamp effect
//  Ported from shadertoy https://www.shadertoy.com/view/3lKBD3
//
//  Created by Jake Bromberg on 12/20/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// === Feature Toggles (comment/uncomment to test performance) ===
#define ENABLE_UV_ROTATION        // Main UV space rotation
#define ENABLE_NOISE_OFFSET_ROTATION  // Rotation in noise4 loop
#define ENABLE_CYAN_ROTATION      // Cyan layer rotation
#define ENABLE_MAGENTA_ROTATION   // Magenta layer rotation

// Noise quality (max octaves at LOD 1.0)
#define MAX_NOISE_OCTAVES 4

// === MTKView Support ===
struct Uniforms {
    float2 resolution;
    float time;
    float lod;  // 0.0 to 1.0: scales octave counts for thermal throttling
};

// Parameters passed in buffer 1 (up to 8 floats)
struct Parameters {
    float timeSpeed;
    float colorInterval;
    float baseGray;
    float hueShift;  // in degrees, -180 to 180
    float pad[4];
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

// Rotate color around the gray axis (1,1,1) using Rodrigues' formula
static inline float3 rotateHue(float3 color, float angleRadians) {
    float c = fast::cos(angleRadians);
    float s = fast::sin(angleRadians);
    // Unit vector along gray axis
    const float3 k = float3(0.57735026919f); // 1/sqrt(3)
    return color * c + cross(k, color) * s + k * dot(k, color) * (1.0f - c);
}

static inline float noise4(float2 uv, float time, float2 offset, int octaves) {
    float f = 0.5f;
    float frequency = 1.75f;
    float amplitude = 0.5f;

    for (int i = 0; i < MAX_NOISE_OCTAVES; i++) {
        if (i >= octaves) break;
        f += amplitude * simplexNoise(frequency * uv - offset);
        frequency *= 2.0f;
        amplitude *= 0.5f;
    }
    return f;
}

// Core implementation
static half4 lamp4DImpl(float2 position, float width, float height, float time,
                        float timeSpeed, float colorInterval, float baseGray, float hueShift, float lod) {
    time /= timeSpeed;

    // LOD-scaled octave count: 2 at LOD 0.0, MAX_NOISE_OCTAVES at LOD 1.0
    int octaves = int(mix(2.0f, float(MAX_NOISE_OCTAVES), lod));

    float2 iResolution = float2(width, height);
    float2 p = position / iResolution;
    float2 uv = p * float2(iResolution.x / iResolution.y, 0.8f);

    // Single-octave noise adds continuous variation to prevent log-based
    // calculations from stagnating at large time values (where d/dt log(t) → 0)
    float timeVariation = simplexNoise(float2(time * 0.05f, 0.0f)) * 5.0f;
    float variedTime = time + timeVariation;

    // Precompute all trig and log values (using variedTime for logs)
    float logTime = fast::log(variedTime + 3.0f);
    float logTimePlus1 = fast::log(variedTime + 1.0f);

    // Precompute noise offset (moved out of loop)
#ifdef ENABLE_NOISE_OFFSET_ROTATION
    // Increased rotation speed and use variedTime for continuous motion
    float offsetAngle = variedTime / 99.0f;
    float offsetS = fast::sin(offsetAngle);
    float offsetC = fast::cos(offsetAngle);
    float2 baseOffset = float2(logTime, logTimePlus1 * 0.1f);
    float2 noiseOffset = rotate(baseOffset, offsetS, offsetC);
#else
    float2 noiseOffset = float2(logTime, logTimePlus1 * 0.1f);
#endif

#ifdef ENABLE_UV_ROTATION
    // Use variedTime to maintain animation even at large time values
    // The log provides slow aesthetic rotation, linear term prevents stagnation
    float uvAngle = (fast::log(variedTime + 1.0f) + variedTime * 0.01f) / -7.0f;
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

    // Convert hue shift from degrees to radians
    float hueRadians = hueShift * (M_PI_F / 180.0f);

    // Base color weights with hue rotation applied
    float3 dblue = colorInterval * rotateHue(float3(1.8f, 2.6f, 2.6f), hueRadians);
    float3 cyan = colorInterval * rotateHue(float3(0.0f, 2.1f, 2.0f), hueRadians);
    float3 magenta = colorInterval * rotateHue(float3(1.8f, 1.0f, 1.8f), hueRadians);

    float3 color = float3(baseGray);

    // Cache frequently used noise values
    float noiseUV = noise4(uv, time, noiseOffset, octaves);

    // Blue layer
    float f = noise4(uv + noiseUV * (logTimePlus1 + (time / 60.0f)), time, noiseOffset, octaves);
    color += f * normalize2(dblue);

    // Cyan layer
#ifdef ENABLE_CYAN_ROTATION
    float2 cyanUV = rotate(uv, cyanS, cyanC);
#else
    float2 cyanUV = uv;
#endif
    float noiseFUV = noise4(f * uv, time, noiseOffset, octaves);
    f = noise4(f * cyanUV + f * noiseFUV, time, noiseOffset, octaves);
    color += f * normalize2(cyan);

    // Magenta layer
#ifdef ENABLE_MAGENTA_ROTATION
    float2 magentaUV = rotate(uv, magentaS, magentaC);
#else
    float2 magentaUV = uv;
#endif
    // Reuse cached noiseUV instead of computing noise4(uv, time) twice
    f = noise4(f * magentaUV + f * noiseUV * noiseUV, time, noiseOffset, octaves);
    color += f * normalize2(magenta);

    color = normalize2(color);

    return half4(half3(color), 1.0h);
}

[[ stitchable ]]
half4 lamp4D(float2 position, half4 inColor, float width, float height, float time) {
    return lamp4DImpl(position, width, height, time, 9.0f, 10.0f, 0.75f, 0.0f, 1.0f);  // Full quality for SwiftUI
}

// Fragment wrapper for MTKView rendering
fragment half4 lamp4DFrag(VertexOut in [[stage_in]],
                          constant Uniforms& u [[buffer(0)]],
                          constant Parameters& p [[buffer(1)]]) {
    float2 pos = in.uv * u.resolution;
    return lamp4DImpl(pos, u.resolution.x, u.resolution.y, u.time,
                      p.timeSpeed, p.colorInterval, p.baseGray, p.hueShift, u.lod);
}
