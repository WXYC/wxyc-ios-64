//
//  Spiral.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
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

// Core implementation
static half4 spiralImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);
    float2 fragCoord = position;
    float iTime = time;

    // Normalized coordinates centered at screen middle
    float2 uv = (fragCoord - 0.5f * iResolution) / max(iResolution.y, 1.0f);

    // Polar angle
    float a = atan2(uv.y, uv.x);

    // Animated point
    float2 p = cos(a + iTime) * float2(cos(0.5f * iTime), sin(0.3f * iTime));

    // Distances
    float d1 = length(uv - p);
    float d2 = length(uv);

    // Prevent division by zero
    float denom = max(d1 + d2, 1e-6f);
    float2 ratio = float2(d1, d2) / denom;

    // Prevent log of zero
    float luv = max(length(uv), 1e-6f);
    float2 logRatio = log(max(ratio, float2(1e-6f)));

    // Spiral UV transformation
    float2 uv2 = 2.0f * cos(log(luv) * 0.25f - 0.5f * iTime + logRatio);

    // Grid pattern
    float2 fpos = fract(4.0f * uv2) - 0.5f;
    float d = max(fabs(fpos.x), fabs(fpos.y));
    float k = 5.0f / max(iResolution.y, 1.0f);
    float s = smoothstep(-k, k, 0.25f - d);

    // Base color from grid
    float3 col = float3(s, 0.5f * s, 0.1f - 0.1f * s);

    // Glowing center effect
    float glowArg = -2.5f * (length(uv - p) + length(uv));
    col += (1.0f / cosh(glowArg)) * float3(1.0f, 0.5f, 0.1f);

    // Electric spiral effect
    float c = cos(10.0f * length(uv2) + 4.0f * iTime);
    float field = cos(9.0f * a + iTime) * uv.x
               + sin(9.0f * a + iTime) * uv.y
               + 0.1f * c;
    col += (0.5f + 0.5f * c) * float3(0.5f, 1.0f, 1.0f) * exp(-9.0f * fabs(field));

    return half4(half3(col), 1.0h);
}

[[ stitchable ]]
half4 spiral(float2 position, half4 inColor, float width, float height, float time) {
    return spiralImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 spiralFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return spiralImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
