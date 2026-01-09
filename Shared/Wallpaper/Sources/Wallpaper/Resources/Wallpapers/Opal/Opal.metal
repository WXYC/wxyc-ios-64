//
//  Opal.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/31/2025.
//  Translated from https://www.shadertoy.com/view/Mdj3RV
//  License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float time;
    float lod;  // 0.0 to 1.0: scales octave counts for thermal throttling
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// iq noise function
static inline float hash(float n) {
    return fract(sin(n) * 43758.5453f);
}

static inline float noise(float3 x) {
    float3 p = floor(x);
    float3 f = fract(x);

    f = f * f * (3.0f - 2.0f * f);
    float n = p.x + p.y * 57.0f + 113.0f * p.z;

    return mix(
        mix(
            mix(hash(n + 0.0f), hash(n + 1.0f), f.x),
            mix(hash(n + 57.0f), hash(n + 58.0f), f.x),
            f.y
        ),
        mix(
            mix(hash(n + 113.0f), hash(n + 114.0f), f.x),
            mix(hash(n + 170.0f), hash(n + 171.0f), f.x),
            f.y
        ),
        f.z
    );
}

// x3
static inline float3 noise3(float3 x) {
    return float3(
        noise(x + float3(123.456f, 0.567f, 0.37f)),
        noise(x + float3(0.11f, 47.43f, 19.17f)),
        noise(x)
    );
}

// Schlick bias function
static inline float bias(float x, float b) {
    return x / ((1.0f / b - 2.0f) * (1.0f - x) + 1.0f);
}

// Schlick gain function
static inline float gain(float x, float g) {
    float t = (1.0f / g - 2.0f) * (1.0f - 2.0f * x);
    return x < 0.5f ? (x / (t + 1.0f)) : (t - x) / (t - 1.0f);
}

static inline float3x3 rotation(float angle, float3 axis) {
    float s = sin(-angle);
    float c = cos(-angle);
    float oc = 1.0f - c;
    float3 sa = axis * s;
    float3 oca = axis * oc;

    return float3x3(
        oca.x * axis + float3(c, -sa.z, sa.y),
        oca.y * axis + float3(sa.z, c, -sa.x),
        oca.z * axis + float3(-sa.y, sa.x, c)
    );
}

static inline float3 fbm(float3 x, float H, float L, int oc) {
    float3 v = float3(0.0f);
    float f = 1.0f;
    for (int i = 0; i < 10; i++) {
        if (i >= oc) break;
        float w = pow(f, -H);
        v += noise3(x) * w;
        x *= L;
        f *= L;
    }
    return v;
}

static inline float3 smf(float3 x, float H, float L, int oc, float off) {
    float3 v = float3(1.0f);
    float f = 1.0f;
    for (int i = 0; i < 10; i++) {
//        if (i >= oc) break;
        v *= off + f * (noise3(x) * 2.0f - 1.0f);
        f *= H;
        x *= L;
    }
    return v;
}

fragment float4 opalFragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]]
) {
    float2 uv = in.uv;
    uv.x *= u.resolution.x / u.resolution.y;

    // LOD-scaled octave counts: 3 at LOD 0.0, full at LOD 1.0
    int octaves8 = int(mix(3.0f, 8.0f, u.lod));
    int octaves7 = int(mix(3.0f, 7.0f, u.lod));

    float time = u.time * 1.276f;

    float slow = time * 0.002f;
    uv *= 1.0f + 0.5f * slow * sin(slow * 10.0f);

    float ts = time * 0.37f;
    float change = gain(fract(ts), 0.0008f) + floor(ts);

    float3 p = float3(uv * 0.2f, slow);

    float3 axis = 4.0f * fbm(p, 0.5f, 2.0f, octaves8);

    float3 colorVec = 0.5f * 5.0f * fbm(p * 0.3f, 0.5f, 2.0f, octaves7);
    p += colorVec;

    float mag = 0.85e5f;
    float3 colorMod = mag * smf(p, 0.7f, 2.0f, octaves8, 0.2f);
    colorVec += colorMod;

    colorVec = rotation(3.0f * length(axis) + slow * 10.0f, normalize(axis)) * colorVec;

    colorVec *= 0.1f;

    return float4(colorVec, 1.0f);
}
