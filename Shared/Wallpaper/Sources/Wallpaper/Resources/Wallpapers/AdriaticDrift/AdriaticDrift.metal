//
//  AdriaticDrift.metal
//  Wallpaper
//
//  Animated wallpaper shader using layered simplex noise and rotating UV coordinates
//  to create a flowing, multi-colored drift effect in deep blue, cyan, and magenta tones.
//
//  Created by Jake Bromberg on 1/16/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// === MTKView Support ===
struct Uniforms {
    float2 resolution;
    float time;
    float lod;
};

// Parameters passed in buffer 1 (up to 8 floats)
struct Parameters {
    float timeScale;
    float pad1;
    float pad2;
    float pad3;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// ---------------- Hash ----------------

// Trig-free hash
static float2 hash(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031f);
    p3 += dot(p3, p3.yzx + 33.33f);
    return -1.0f + 2.0f * fract(float2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}

// ---------------- Simplex noise 2D ----------------

static float noise(float2 p) {
    const float K1 = 0.366025404f; // (sqrt(3)-1)/2
    const float K2 = 0.211324865f; // (3-sqrt(3))/6

    float2 i = floor(p + (p.x + p.y) * K1);
    float2 a = p - i + (i.x + i.y) * K2;
    float m = step(a.y, a.x);
    float2 o = float2(m, 1.0f - m);
    float2 b = a - o + K2;
    float2 c = a - 1.0f + 2.0f * K2;

    float3 h = max(0.5f - float3(dot(a, a), dot(b, b), dot(c, c)), 0.0f);
    float3 n = h * h * h * h * float3(
        dot(a, hash(i + 0.0f)),
        dot(b, hash(i + o)),
        dot(c, hash(i + 1.0f))
    );
    return dot(n, float3(70.0f));
}

// ---------------- Helpers ----------------

static float vmax3(float3 v) { return max(v.x, max(v.y, v.z)); }
static float vmin3(float3 v) { return min(v.x, min(v.y, v.z)); }

static float3 normalize2(float3 c) {
    c = c * c * c;
    float mx = vmax3(c);
    float mn = vmin3(c);
    return c / (mx + mn);
}

// Fast rotate
static float2 rotate(float2 p, float a) {
    float s = sin(a);
    float cs = cos(a);
    return float2(cs * p.x - s * p.y, s * p.x + cs * p.y);
}

// ---------------- fbm (noise4) ----------------

static float noise4(float2 uv, float time) {
    float f = 0.5f;
    float frequency = 1.75f;
    float amplitude = 0.5f;

    // Precompute time-dependent shift once per noise4 call
    float lt3 = log(time + 3.0f);
    float2 shift = rotate(float2(lt3, lt3 / 999.0f), time / 9999.0f);

    // Reduced octave count = 5
    for (int i = 0; i < 5; i++) {
        float2 p = frequency * uv - shift;
        f += amplitude * noise(p);
        frequency *= 2.0f;
        amplitude *= 0.5f;
    }
    return f;
}

// -----------------------------------------------

static half4 adriaticDriftImpl(float2 position, float width, float height, float time, float timeScale) {
    float iTime = time * timeScale;
    float2 iResolution = float2(width, height);
    float2 fragCoord = position;

    float2 p = fragCoord / iResolution;

    float2 uv = p * float2(iResolution.x / iResolution.y, 0.8f);
    uv = rotate(uv, log(iTime) / -7.0f);

    float interval = 10.0f;
    float3 dblue   = interval * float3(1.8f, 2.6f, 2.6f);
    float3 cyan    = interval * float3(0.0f, 2.1f, 2.0f);
    float3 magenta = interval * float3(1.8f, 1.0f, 1.8f);

    // Precompute normalized palette
    float3 ndblue   = normalize2(dblue);
    float3 ncyan    = normalize2(cyan);
    float3 nmagenta = normalize2(magenta);

    float3 color = float3(0.75f);

    // Original structure, with caching enabled
    float f = 0.0f;

    float n_uv = noise4(uv, iTime);
    float lt1 = log(iTime + 1.0f);

    // 1st layer
    f = noise4(uv + n_uv * (lt1 + iTime / 60.0f), iTime);
    color += f * ndblue;

    // 2nd layer
    float2 uv_r2 = rotate(uv, sin(iTime / 11.0f));
    float n_fuv = noise4(f * uv, iTime);
    f = noise4(f * uv_r2 + f * n_fuv, iTime);
    color += f * ncyan;

    // 3rd layer
    float2 uv_r3 = rotate(uv, iTime / 7.0f);
    float n_uv2 = n_uv * n_uv;
    f = noise4(f * uv_r3 + f * n_uv2, iTime);
    color += f * nmagenta;

    color = normalize2(color);
    return half4(half3(color), 1.0h);
}

[[ stitchable ]]
half4 adriaticDrift(float2 position, half4 inColor, float width, float height, float time, float timeScale) {
    return adriaticDriftImpl(position, width, height, time, timeScale);
}

// Fragment wrapper for MTKView rendering
fragment half4 adriaticDriftFrag(VertexOut in [[stage_in]],
                                  constant Uniforms& u [[buffer(0)]],
                                  constant Parameters& p [[buffer(1)]]) {
    float2 pos = in.uv * u.resolution;
    return adriaticDriftImpl(pos, u.resolution.x, u.resolution.y, u.time, p.timeScale);
}
