//
//  GlyphSpinner.metal
//  Wallpaper
//
//  Animated scribble background effect
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

constant float3 BGCOLOR = float3(0.0f, 0.1f, 0.1f);

static inline float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}

static inline float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0f - 2.0f * f);
    return mix(mix(hash(i), hash(i + float2(1.0f, 0.0f)), f.x),
               mix(hash(i + float2(0.0f, 1.0f)), hash(i + float2(1.0f, 1.0f)), f.x), f.y);
}

static inline float scribble(float2 p, float k, float2 resolution) {
    float scl = k / resolution.y;
    float2 c = p * scl;
    float n = noise(c * 3.0f);
    return step(0.5f, n);
}

// Core implementation
static half4 glyphSpinnerImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);

    // Animated scribble background
    float s = scribble(position + 0.45f * time * float2(75.0f, 30.0f), 7.0f, iResolution);

    float3 bgdark = mix(BGCOLOR, float3(0.0f), 0.6f);
    float3 color = mix(BGCOLOR, bgdark, s);

    // Gamma correction
    color = pow(color, float3(1.0f / 2.2f));

    return half4(half3(color), 1.0h);
}

[[ stitchable ]]
half4 glyphSpinner(float2 position,
                   half4 inColor,
                   float width,
                   float height,
                   float time)
{
    return glyphSpinnerImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 glyphSpinnerFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return glyphSpinnerImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
