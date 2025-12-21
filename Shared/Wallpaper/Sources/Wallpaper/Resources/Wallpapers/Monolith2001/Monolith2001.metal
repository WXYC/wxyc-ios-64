//
//  Monolith2001.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//  A Space Odyssey inspired scene with monolith and volumetric clouds
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

constant float PRECI = 0.001f;
constant float tmax = 300.0f;
constant float tmin = 0.0f;

static inline float iqhash(float n) {
    return fract(sin(n) * 43758.5453f);
}

static inline float noise(float3 x) {
    float3 p = floor(x);
    float3 f = fract(x);

    f = f * f * (3.0f - 2.0f * f);
    float n = p.x + p.y * 57.0f + 113.0f * p.z;

    float v = mix(mix(mix(iqhash(n + 0.0f), iqhash(n + 1.0f), f.x),
                      mix(iqhash(n + 57.0f), iqhash(n + 58.0f), f.x), f.y),
                  mix(mix(iqhash(n + 113.0f), iqhash(n + 114.0f), f.x),
                      mix(iqhash(n + 170.0f), iqhash(n + 171.0f), f.x), f.y), f.z);
    return -1.0f + 2.0f * v;
}

static inline float noise11(float x) {
    float p = floor(x);
    float f = fract(x);
    f = f * f * (3.0f - 2.0f * f);
    return mix(iqhash(p), iqhash(p + 1.0f), f);
}

static inline float mapBox(float3 p) {
    float3 b = float3(2.0f, 4.5f, 0.5f);
    float3 d = abs(p - float3(0.0f, 0.5f, 1.7f)) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0f) + length(max(d, 0.0f));
}

static inline float raymarchScene(float3 ro, float3 rd) {
    float t = tmin;
    for (int i = 0; i < 512; ++i) {
        float dist = mapBox(ro + rd * t);

        if (dist <= PRECI) break;
        if (t > tmax) break;

        t = t + dist;
    }
    return t;
}

static inline float3x3 setCamera(float3 ro, float3 ta, float cr) {
    float3 cw = normalize(ta - ro);
    float3 cp = float3(sin(cr), cos(cr), 0.0f);
    float3 cu = normalize(cross(cw, cp));
    float3 cv = normalize(cross(cu, cw));
    return float3x3(cu, cv, cw);
}

static inline float cloudmap(float3 p, float time) {
    float3 q = p - float3(0.0f, 0.0f, 1.0f) * time;
    float f;
    f = 0.50000f * noise(q); q = q * 2.02f;
    f += 0.25000f * noise(q); q = q * 2.03f;
    f += 0.12500f * noise(q); q = q * 2.01f;
    f += 0.06250f * noise(q); q = q * 2.02f;
    f += 0.03125f * noise(q);
    return 2.0f - length(p) + f * 5.0f;
}

static inline float4 integrate(float4 sum, float dif, float den, float3 bgcol, float t) {
    // lighting
    float3 lin = float3(0.65f, 0.7f, 0.75f) * 0.4f + float3(1.0f, 0.5f, 0.2f) * dif * 2.0f;
    float4 col = float4(mix(float3(1.0f, 0.95f, 0.8f), float3(0.4f, 0.3f, 0.35f), den), den);
    col.xyz *= lin;
    col.xyz = mix(col.xyz, bgcol, 1.0f - exp(-0.003f * t * t));
    // front to back blending
    col.a *= 0.4f;
    col.rgb *= col.a;
    return sum + col * (1.0f - sum.a);
}

static inline float4 raymarchCloud(float3 ro, float3 rd, float3 bgcol, float3 sundir, float time) {
    float4 sum = float4(0.0f);
    float t = 0.0f;

    for (int i = 0; i < 50; i++) {
        float3 pos = ro + t * rd - float3(0.7f, 5.0f, 0.0f);
        if (sum.a > 0.99f) break;

        float den = cloudmap(pos, time);
        if (den > 0.01f) {
            float dif = clamp((den - cloudmap(pos + 0.3f * sundir, time)) / 0.6f, 0.0f, 1.0f);
            sum = integrate(sum, dif, den, bgcol, t);
        }

        t += max(0.05f, 0.02f * t);
    }

    return clamp(sum, 0.0f, 1.0f);
}

// Core implementation
static half4 monolith2001Impl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);
    float2 uv = (-iResolution + 2.0f * position) / iResolution.y;

    float3 ro = float3(0.0f, 0.1f, 0.0f);
    float3 ta = float3(0.0f, 10.0f, 1.0f);
    float3x3 ca = setCamera(ro, ta, 0.0f);

    // ray direction
    float3 rd = ca * normalize(float3(uv, 2.0f));
    rd = normalize(rd);

    float3 sundir = normalize(float3(0.0f, 10.0f, 2.9f));
    float sun = clamp(dot(sundir, rd), 0.0f, 1.0f);
    float result = raymarchScene(ro, rd);

    // Sky gradient
    float3 color = mix(float3(84.0f, 69.0f, 56.0f) / 255.0f,
                       float3(134.0f, 106.0f, 65.0f) / 255.0f,
                       smoothstep(0.0f, 1.0f, -uv.y));

    float3 hit = ro + result * rd;

    if (result > tmax) {
        // Draw moon
        float moon = smoothstep(0.0f, 0.01f, 0.18f - length(uv - float2(0.0f, 0.4f)));
        float2 moonpos = uv - float2(0.0f, 0.43f);
        float r = noise11(atan2(moonpos.x, moonpos.y) * 7.0f + 2.0f) * 0.008f;
        float moonshade = smoothstep(0.0f, 0.01f, 0.18f + r - length(moonpos));
        moon = moon - min(moon, moonshade);
        color = mix(color, mix(float3(0.0f), float3(1.0f), 2.5f * length(moonpos)), moon);

        color += 2.0f * float3(1.0f, 0.6f, 0.6f) * pow(sun, 256.0f);

        // Draw clouds
        float4 res = raymarchCloud(ro, rd, color, sundir, time);
        color = color * (1.0f - res.w) + res.xyz;
    } else {
        // Draw Monolith
        color = float3(0.0f);
    }

    color += 0.3f * float3(1.0f, 0.4f, 0.2f) * pow(sun, 128.0f);

    return half4(half3(color), 1.0h);
}

[[ stitchable ]]
half4 monolith2001(float2 position,
                   half4 inColor,
                   float width,
                   float height,
                   float time)
{
    return monolith2001Impl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 monolith2001Frag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return monolith2001Impl(pos, u.resolution.x, u.resolution.y, u.time);
}
