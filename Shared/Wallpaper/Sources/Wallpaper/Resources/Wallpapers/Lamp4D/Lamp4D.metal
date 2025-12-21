//
//  Lamp4D.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//  Simplex noise based colorful lamp effect
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// === MTKView Support ===
struct Uniforms {
    float2 resolution;
    float time;
    float displayScale;
    float audioLevel;
    float audioBass;
    float audioMid;
    float audioHigh;
    float audioBeat;
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

static inline float2 hash2D(float2 p) {
    p = float2(dot(p, float2(127.1f, 311.7f)), dot(p, float2(269.5f, 183.3f)));
    return -1.0f + 2.0f * fract(sin(p) * 43758.5453123f);
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

static inline float2 rotate(float2 oldpoint, float angle) {
    float left = cos(angle) * oldpoint.x - sin(angle) * oldpoint.y;
    float right = sin(angle) * oldpoint.x + cos(angle) * oldpoint.y;
    return float2(left, right);
}

static inline float noise4(float2 uv, float time) {
    float f = 0.5f;
    float frequency = 1.75f;
    float amplitude = 0.5f;

    for (int i = 0; i < 7; i++) {
        float2 offset = rotate(float2(log(time + 3.0f), log(time + 3.0f) / 999.0f), time / 9999.0f);
        f += amplitude * simplexNoise(frequency * uv - offset);
        frequency *= 2.0f;
        amplitude *= 0.5f;
    }
    return f;
}

// Core implementation
static half4 lamp4DImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);
    float2 p = position / iResolution;
    float2 uv = p * float2(iResolution.x / iResolution.y, 0.8f);
    uv = rotate(uv, log(time) / -7.0f);

    float interval = 10.0f;
    float3 dblue = interval * float3(1.8f, 2.6f, 2.6f);
    float3 cyan = interval * float3(0.0f, 2.1f, 2.0f);
    float3 magenta = interval * float3(1.8f, 1.0f, 1.8f);

    float3 color = float3(0.75f);

    float f = noise4(uv + noise4(uv, time) * (log(time + 1.0f) + (time / 60.0f)), time);
    color += f * normalize2(dblue);

    f = noise4(f * rotate(uv, sin(time / 11.0f)) + f * noise4(f * uv, time), time);
    color += f * normalize2(cyan);

    f = noise4(f * rotate(uv, time / 7.0f) + f * noise4(uv, time) * noise4(uv, time), time);
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
