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

struct Parameters {
    float smfOffset;        // Offset in smf() - higher = less desaturation (default 0.2)
    float smfIterations;    // Number of smf iterations (default 10)
    float minSaturation;    // Post-process minimum saturation floor (default 0.0)
    float saturationBoost;  // Multiplier to spread RGB channels apart (default 1.0)
    float useFastTrig;      // 1.0 = use fast:: trig in rotation (default 0.0)
    float pad5, pad6, pad7; // Padding to 8 floats
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

static inline float3 noise3(float3 x) {
    return float3(
        noise(x + float3(123.456f, 0.567f, 0.37f)),
        noise(x + float3(0.11f, 47.43f, 19.17f)),
        noise(x)
    );
}

static inline float3x3 rotation(float angle, float3 axis, bool useFastTrig) {
    float s, c;
    if (useFastTrig) {
        s = fast::sin(-angle);
        c = fast::cos(-angle);
    } else {
        s = sin(-angle);
        c = cos(-angle);
    }
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

static inline float3 smf(float3 x, float H, float L, float off, int iterations) {
    float3 v = float3(1.0f);
    float f = 1.0f;
    for (int i = 0; i < 10; i++) {
        if (i >= iterations) break;
        v *= off + f * (noise3(x) * 2.0f - 1.0f);
        f *= H;
        x *= L;
    }
    return v;
}

/// Enforces a minimum saturation on the color by spreading RGB channels apart.
static inline float3 enforceSaturation(float3 color, float minSat, float boost) {
    float maxC = max(color.r, max(color.g, color.b));
    float minC = min(color.r, min(color.g, color.b));
    float chroma = maxC - minC;
    float luminance = (maxC + minC) * 0.5f;

    // Calculate current saturation (HSL-style)
    float sat = (maxC > 0.001f && luminance < 0.999f)
        ? chroma / (1.0f - abs(2.0f * luminance - 1.0f))
        : 0.0f;

    // Apply boost to spread channels apart from their mean
    if (boost > 1.0f) {
        float3 mean = float3((color.r + color.g + color.b) / 3.0f);
        color = mean + (color - mean) * boost;
    }

    // If saturation is below minimum, boost it
    if (sat < minSat && sat > 0.001f) {
        float3 mean = float3((color.r + color.g + color.b) / 3.0f);
        float factor = minSat / sat;
        color = mean + (color - mean) * factor;
    }

    return color;
}

fragment float4 opalFragment(
    VertexOut in [[stage_in]],
    constant Uniforms& u [[buffer(0)]],
    constant Parameters& p [[buffer(1)]]
) {
    float2 uv = in.uv;
    uv.x *= u.resolution.x / u.resolution.y;

    bool useFastTrig = p.useFastTrig > 0.5f;

    // LOD-scaled octave counts: 3 at LOD 0.0, full at LOD 1.0
    int octaves8 = int(mix(3.0f, 8.0f, u.lod));
    int octaves7 = int(mix(3.0f, 7.0f, u.lod));

    float time = u.time * 1.276f;

    float slow = time * 0.002f;
    uv *= 1.0f + 0.5f * slow * sin(slow * 10.0f);

    float3 pos = float3(uv * 0.2f, slow);

    float3 axis = 4.0f * fbm(pos, 0.5f, 2.0f, octaves8);

    float3 colorVec = 0.5f * 5.0f * fbm(pos * 0.3f, 0.5f, 2.0f, octaves7);
    pos += colorVec;

    // Use parameterized smf offset and iteration count
    int smfIters = clamp(int(p.smfIterations), 3, 10);
    float mag = 0.85e5f;
    float3 colorMod = mag * smf(pos, 0.7f, 2.0f, p.smfOffset, smfIters);
    colorVec += colorMod;

    colorVec = rotation(3.0f * length(axis) + slow * 10.0f, normalize(axis), useFastTrig) * colorVec;

    colorVec *= 0.1f;

    // Apply saturation enforcement if parameters are set
    if (p.minSaturation > 0.0f || p.saturationBoost > 1.0f) {
        colorVec = enforceSaturation(colorVec, p.minSaturation, p.saturationBoost);
    }

    return float4(colorVec, 1.0f);
}
