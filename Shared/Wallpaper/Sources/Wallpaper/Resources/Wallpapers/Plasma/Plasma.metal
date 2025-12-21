//
//  Plasma.metal
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
static half4 plasmaImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);
    float2 fragCoord = position;
    float iTime = time;

    // Normalized pixel coordinates scaled up
    float2 p = 6.0f * fragCoord / iResolution;

    // Pattern: combination of sine waves
    float f = sin(p.x + sin(2.0f * p.y + iTime))
            + sin(length(p) + iTime)
            + 0.5f * sin(p.x * 2.5f + iTime);

    // Color: oscillating RGB based on pattern
    float3 col = 0.7f + 0.3f * cos(f + float3(0.0f, 2.1f, 4.2f));

    return half4(half3(col), 1.0h);
}

[[ stitchable ]]
half4 plasma(float2 position, half4 inColor, float width, float height, float time) {
    return plasmaImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 plasmaFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return plasmaImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
