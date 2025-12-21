//
//  SelfReconfiguringCircuit.metal
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

constant float PI = 3.14159f;
constant float TIME_DIV = 2.25f;  // Slowed by 1/3

static inline float2 random2(float2 p) {
    return fract(sin(float2(dot(p, float2(127.1f, 311.7f)),
                            dot(p, float2(269.5f, 183.3f)))) * 43758.5453f);
}

static inline float2x2 rot(float a) {
    float c = cos(a);
    float s = sin(a);
    return float2x2(c, -s, s, c);
}

static inline float voronoi(float2 uv, float time) {
    float2 cell = floor(uv);
    float2 frac = fract(uv);
    float ret = 100.0f;

    float t = time / TIME_DIV;
    float change = t;  // Continuous animation (removed pausing)

    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float2 neighbor = float2(float(i), float(j));
            float2 randVal = random2(cell + neighbor);
            randVal = 0.5f + 0.5f * sin(change * 4.0f + 2.0f * PI * randVal);
            float2 toCenter = neighbor + randVal - frac;
            ret = min(ret, max(abs(toCenter.x), abs(toCenter.y)));
        }
    }

    return ret;
}

static inline float2 gradient(float2 x, float thickness, float time) {
    float2 h = float2(thickness, 0.0f);
    return float2(voronoi(x + h.xy, time) - voronoi(x - h.xy, time),
                  voronoi(x + h.yx, time) - voronoi(x - h.yx, time)) / (2.0f * h.x);
}

// Core implementation
static half4 selfReconfiguringCircuitImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);
    float2 uv = position / iResolution;
    uv.x *= iResolution.x / iResolution.y;

    float t = time / TIME_DIV;
    float change = t;  // Continuous animation (removed pausing)
    float colSwitch = sin(change * PI / 2.0f);

    uv -= 0.5f;
    uv = rot(change * PI / 2.0f) * uv;
    uv += 0.5f;

    uv *= 2.85f;

    float val = voronoi(uv, time) / length(gradient(uv, 0.02f, time));
    float colVal = pow(val, 1.1f) * 1.05f;

    float3 col1 = mix(float3(0.0f, colVal, 0.0f),
                      mix(float3(0.0f, 0.0f, colVal), float3(colVal, 0.0f, 0.0f), clamp(colSwitch, 0.0f, 1.0f)),
                      clamp(colSwitch + 1.0f, 0.0f, 1.0f));

    float3 col2 = mix(float3(0.45f, 0.0f, 0.8f),
                      mix(float3(0.85f, 0.2f, 0.2f), float3(0.5f, 0.85f, 0.55f), clamp(colSwitch, 0.0f, 1.0f)),
                      clamp(colSwitch + 1.0f, 0.0f, 1.0f));

    float3 result = mix(col2, col1, colVal);

    return half4(half3(result), 1.0h);
}

[[ stitchable ]]
half4 selfReconfiguringCircuit(float2 position, half4 inColor, float width, float height, float time) {
    return selfReconfiguringCircuitImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 selfReconfiguringCircuitFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return selfReconfiguringCircuitImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
