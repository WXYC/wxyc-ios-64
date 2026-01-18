//
//  Plasma.metal
//  Wallpaper
//
//  Metal shader implementing the Plasma wallpaper with animated sine wave patterns
//  and oscillating RGB colors. Supports both SwiftUI stitchable and MTKView rendering.
//
//  Created by Jake Bromberg on 12/20/25.
//  Copyright © 2025 WXYC. All rights reserved.
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
    float patternScale;
    float colorAmplitude;
    float colorOffsetR;
    float colorOffsetG;
    float colorOffsetB;
    float waveThreeAmplitude;
    float timeScale;
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Core implementation
static half4 plasmaImpl(float2 position, float width, float height, float time,
                        float patternScale, float colorAmplitude, float3 colorOffset,
                        float waveThreeAmplitude, float timeScale) {
    float2 iResolution = float2(width, height);
    float2 fragCoord = position;
    float iTime = time * timeScale;

    // Normalized pixel coordinates scaled up
    float2 p = patternScale * fragCoord / iResolution;

    // Pattern: combination of sine waves
    float f = sin(p.x + sin(2.0f * p.y + iTime))
            + sin(length(p) + iTime)
            + waveThreeAmplitude * sin(p.x * 2.5f + iTime);

    // Color: oscillating RGB based on pattern
    float3 col = (1.0f - colorAmplitude) + colorAmplitude * cos(f + colorOffset);

    return half4(half3(col), 1.0h);
}

[[ stitchable ]]
half4 plasma(float2 position, half4 inColor, float width, float height, float time,
             float patternScale, float colorAmplitude, float colorOffsetR,
             float colorOffsetG, float colorOffsetB, float waveThreeAmplitude, float timeScale) {
    return plasmaImpl(position, width, height, time, patternScale, colorAmplitude,
                      float3(colorOffsetR, colorOffsetG, colorOffsetB), waveThreeAmplitude, timeScale);
}

// Fragment wrapper for MTKView rendering
fragment half4 plasmaFrag(VertexOut in [[stage_in]],
                          constant Uniforms& u [[buffer(0)]],
                          constant Parameters& p [[buffer(1)]]) {
    float2 pos = in.uv * u.resolution;
    return plasmaImpl(pos, u.resolution.x, u.resolution.y, u.time,
                      p.patternScale, p.colorAmplitude,
                      float3(p.colorOffsetR, p.colorOffsetG, p.colorOffsetB),
                      p.waveThreeAmplitude, p.timeScale);
}
