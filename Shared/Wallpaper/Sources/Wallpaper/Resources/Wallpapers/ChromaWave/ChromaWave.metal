//
//  ChromaWave.metal
//  Wallpaper
//
//  Translated from https://www.shadertoy.com/view/clVGDc
//
//  Created by Jake Bromberg on 12/20/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// 1D gradient noise for time variation
static float hash(float n) {
    return fract(sin(n) * 43758.5453f);
}

static float noise1D(float x) {
    float i = floor(x);
    float f = fract(x);
    float u = f * f * (3.0f - 2.0f * f);  // smoothstep
    return mix(hash(i), hash(i + 1.0f), u);
}

// 2-octave noise for organic time variation
static float noise2Octave(float x) {
    return noise1D(x) * 0.667f + noise1D(x * 2.0f) * 0.333f;
}

// === MTKView Support ===
struct Uniforms {
    float2 resolution;
    float time;
    float lod;  // 0.0 to 1.0: scales iteration count for thermal throttling
};

// Parameters passed in buffer 1 (up to 8 floats)
struct Parameters {
    float highlightCompression;
    float waveScale;
    float iterationDivisor;
    float colorEnhancement;
    float timeSpeed;
    float pad[3];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Core implementation (called by both stitchable and fragment versions)
static half4 chromaWaveImpl(float2 position, float width, float height, float time,
                            float highlightCompression, float waveScale, float iterationDivisor,
                            float colorEnhancement, float timeSpeed, float lod) {
    float2 iResolution = float2(width, height);

    // Wrap time to prevent floating-point precision loss over extended runtime.
    // Using a large period (65536 * 2π ≈ 411775 seconds ≈ 4.7 days) ensures
    // seamless looping while keeping values in a precision-safe range.
    constexpr float timePeriod = 65536.0f * 2.0f * M_PI_F;
    float wrappedTime = fmod(time, timePeriod);

    // 2-octave noise oscillates time for organic variation in animation pace
    float timeVariation = (noise2Octave(wrappedTime * 0.03f) - 0.5f) * 8.0f;
    float t = (wrappedTime + timeVariation) / timeSpeed;

    float3 col = float3(0.0f);

    // LOD-scaled iteration count: 3 at LOD 0.0, 7 at LOD 1.0
    int maxIter = int(mix(3.0f, 7.0f, lod));

    // Process each color channel separately
    for (int c = 0; c < 3; c++) {
        float2 uv = (position * waveScale - iResolution) / iResolution.y;

        // Iterative wave distortion
        for (int i = 1; i < 7; i++) {
            if (i >= maxIter) break;
            uv /= iterationDivisor;
            uv += ceil(col.yx);
            uv += float(i) + (cos(uv.x) * cos(uv.y) + sin(uv.y) * cos(t) + cos(t) * cos(uv.x));
        }

        col[c] = fract(uv.x + uv.y + t);
    }

    // Apply slight color enhancement
    col += colorEnhancement * clamp(col, 0.0f, 0.5f);
    // Compress highlights using Reinhard tone curve: x / (1 + x * k)
    // At k=0: no compression (linear). Higher k rolls off highlights more.
    col = col / (1.0f + col * highlightCompression);
    // Gamma correction
    col = pow(col, float3(1.0f / 2.2f));

    return half4(half3(col), 1.0h);
}

[[ stitchable ]]
half4 chromaWave(float2 position,
                 half4 inColor,
                 float width,
                 float height,
                 float time,
                 float highlightCompression,
                 float waveScale,
                 float iterationDivisor,
                 float colorEnhancement,
                 float timeSpeed)
{
    return chromaWaveImpl(position, width, height, time, highlightCompression,
                          waveScale, iterationDivisor, colorEnhancement, timeSpeed, 1.0f);  // Full quality for SwiftUI
}

// Fragment wrapper for MTKView rendering
fragment half4 chromaWaveFrag(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    constant Parameters& p [[buffer(1)]]
) {
    float2 pos = in.uv * u.resolution;
    return chromaWaveImpl(pos, u.resolution.x, u.resolution.y, u.time,
                          p.highlightCompression, p.waveScale, p.iterationDivisor,
                          p.colorEnhancement, p.timeSpeed, u.lod);
}
