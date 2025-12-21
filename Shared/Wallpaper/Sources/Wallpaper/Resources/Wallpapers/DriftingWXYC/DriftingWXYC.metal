//
//  DriftingWXYC.metal
//  Wallpaper
//
//  A shader that renders drifting WXYC letters using procedural SDFs.
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

// ============================================================================
// WXYC Glyph SDF Functions (auto-generated from WXYCLogoShape.swift)
// ============================================================================

// Signed distance to a quadratic bezier curve
// Based on Inigo Quilez's implementation
static inline float sdBezier(float2 pos, float2 A, float2 B, float2 C) {
    float2 a = B - A;
    float2 b = A - 2.0f * B + C;
    float2 c = a * 2.0f;
    float2 d = A - pos;

    float kk = 1.0f / dot(b, b);
    float kx = kk * dot(a, b);
    float ky = kk * (2.0f * dot(a, a) + dot(d, b)) / 3.0f;
    float kz = kk * dot(d, a);

    float res = 0.0f;
    float sgn = 0.0f;

    float p = ky - kx * kx;
    float p3 = p * p * p;
    float q = kx * (2.0f * kx * kx - 3.0f * ky) + kz;
    float h = q * q + 4.0f * p3;

    if (h >= 0.0f) {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0f;
        float2 uv = sign(x) * pow(abs(x), float2(1.0f / 3.0f));
        float t = clamp(uv.x + uv.y - kx, 0.0f, 1.0f);
        float2 q2 = d + (c + b * t) * t;
        res = dot(q2, q2);
        sgn = cross(float3(c + 2.0f * b * t, 0.0f), float3(q2, 0.0f)).z;
    } else {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0f)) / 3.0f;
        float m = cos(v);
        float n = sin(v) * 1.732050808f;
        float3 t3 = clamp(float3(m + m, -n - m, n - m) * z - kx, 0.0f, 1.0f);
        float2 qx = d + (c + b * t3.x) * t3.x;
        float2 qy = d + (c + b * t3.y) * t3.y;
        float dx = dot(qx, qx);
        float dy = dot(qy, qy);
        float sx = cross(float3(c + 2.0f * b * t3.x, 0.0f), float3(qx, 0.0f)).z;
        float sy = cross(float3(c + 2.0f * b * t3.y, 0.0f), float3(qy, 0.0f)).z;
        res = (dx < dy) ? dx : dy;
        sgn = (dx < dy) ? sx : sy;
    }

    return sqrt(res) * sign(sgn);
}

// SDF for letter W (simplified - using fewer bezier segments for performance)
static inline float sdLetterW(float2 p) {
    float d = 1e10f;
    // Key bezier segments for W outline
    d = min(d, abs(sdBezier(p, float2(0.32842f, 0.03917f), float2(0.31987f, 0.11573f), float2(0.31213f, 0.19333f))));
    d = min(d, abs(sdBezier(p, float2(0.31213f, 0.19333f), float2(0.30291f, 0.25917f), float2(0.29847f, 0.32923f))));
    d = min(d, abs(sdBezier(p, float2(0.29847f, 0.32923f), float2(0.29660f, 0.39122f), float2(0.29400f, 0.45323f))));
    d = min(d, abs(sdBezier(p, float2(0.29400f, 0.45323f), float2(0.27843f, 0.40210f), float2(0.26248f, 0.35097f))));
    d = min(d, abs(sdBezier(p, float2(0.26248f, 0.35097f), float2(0.25275f, 0.29960f), float2(0.24303f, 0.24939f))));
    d = min(d, abs(sdBezier(p, float2(0.24303f, 0.24939f), float2(0.22786f, 0.18542f), float2(0.20439f, 0.14142f))));
    d = min(d, abs(sdBezier(p, float2(0.20439f, 0.14142f), float2(0.20039f, 0.14138f), float2(0.19632f, 0.14090f))));
    d = min(d, abs(sdBezier(p, float2(0.19632f, 0.14090f), float2(0.18580f, 0.13869f), float2(0.17577f, 0.14355f))));
    d = min(d, abs(sdBezier(p, float2(0.17577f, 0.14355f), float2(0.17124f, 0.18408f), float2(0.16631f, 0.22344f))));
    d = min(d, abs(sdBezier(p, float2(0.16631f, 0.22344f), float2(0.16007f, 0.25722f), float2(0.15659f, 0.29418f))));
    d = min(d, abs(sdBezier(p, float2(0.15659f, 0.29418f), float2(0.15416f, 0.35468f), float2(0.14817f, 0.41401f))));
    d = min(d, abs(sdBezier(p, float2(0.14817f, 0.41401f), float2(0.14082f, 0.48037f), float2(0.14214f, 0.55205f))));
    d = min(d, abs(sdBezier(p, float2(0.14214f, 0.55205f), float2(0.13432f, 0.53979f), float2(0.13006f, 0.51491f))));
    d = min(d, abs(sdBezier(p, float2(0.13006f, 0.51491f), float2(0.10929f, 0.42559f), float2(0.09012f, 0.33417f))));
    d = min(d, abs(sdBezier(p, float2(0.09012f, 0.33417f), float2(0.07672f, 0.26341f), float2(0.05937f, 0.19889f))));
    d = min(d, abs(sdBezier(p, float2(0.05937f, 0.19889f), float2(0.05406f, 0.17106f), float2(0.04755f, 0.14636f))));
    d = min(d, abs(sdBezier(p, float2(0.04755f, 0.14636f), float2(0.03554f, 0.11556f), float2(0.02232f, 0.14147f))));
    d = min(d, abs(sdBezier(p, float2(0.02232f, 0.14147f), float2(0.02286f, 0.15653f), float2(0.02338f, 0.17159f))));
    d = min(d, abs(sdBezier(p, float2(0.02338f, 0.17159f), float2(0.02096f, 0.17486f), float2(0.01848f, 0.17122f))));
    d = min(d, abs(sdBezier(p, float2(0.01848f, 0.17122f), float2(0.01568f, 0.16673f), float2(0.01313f, 0.17227f))));
    d = min(d, abs(sdBezier(p, float2(0.01313f, 0.17227f), float2(-0.00099f, 0.31353f), float2(0.00761f, 0.32367f))));
    d = min(d, abs(sdBezier(p, float2(0.00761f, 0.32367f), float2(0.01633f, 0.37438f), float2(0.02863f, 0.42103f))));
    d = min(d, abs(sdBezier(p, float2(0.02863f, 0.42103f), float2(0.04302f, 0.48077f), float2(0.05308f, 0.54575f))));
    d = min(d, abs(sdBezier(p, float2(0.05308f, 0.54575f), float2(0.05786f, 0.58376f), float2(0.06463f, 0.61857f))));
    d = min(d, abs(sdBezier(p, float2(0.06463f, 0.61857f), float2(0.07462f, 0.68291f), float2(0.08539f, 0.74610f))));
    d = min(d, abs(sdBezier(p, float2(0.08539f, 0.74610f), float2(0.09596f, 0.78818f), float2(0.10535f, 0.83228f))));
    d = min(d, abs(sdBezier(p, float2(0.10535f, 0.83228f), float2(0.11954f, 0.90359f), float2(0.14397f, 0.94644f))));
    d = min(d, abs(sdBezier(p, float2(0.14397f, 0.94644f), float2(0.15579f, 0.95175f), float2(0.16763f, 0.95487f))));
    d = min(d, abs(sdBezier(p, float2(0.16763f, 0.95487f), float2(0.17445f, 0.97488f), float2(0.18287f, 0.96116f))));
    d = min(d, abs(sdBezier(p, float2(0.18287f, 0.96116f), float2(0.19335f, 0.91914f), float2(0.19442f, 0.86665f))));
    d = min(d, abs(sdBezier(p, float2(0.19442f, 0.86665f), float2(0.20119f, 0.84478f), float2(0.20599f, 0.81969f))));
    d = min(d, abs(sdBezier(p, float2(0.20599f, 0.81969f), float2(0.21490f, 0.77239f), float2(0.21203f, 0.71666f))));
    d = min(d, abs(sdBezier(p, float2(0.21203f, 0.71666f), float2(0.21531f, 0.65328f), float2(0.21464f, 0.58991f))));
    d = min(d, abs(sdBezier(p, float2(0.21464f, 0.58991f), float2(0.21544f, 0.58688f), float2(0.21624f, 0.58284f))));
    d = min(d, abs(sdBezier(p, float2(0.21624f, 0.58284f), float2(0.23088f, 0.62266f), float2(0.24040f, 0.67599f))));
    d = min(d, abs(sdBezier(p, float2(0.24040f, 0.67599f), float2(0.25562f, 0.74949f), float2(0.27562f, 0.81339f))));
    d = min(d, abs(sdBezier(p, float2(0.27562f, 0.81339f), float2(0.28788f, 0.84363f), float2(0.30293f, 0.86036f))));
    d = min(d, abs(sdBezier(p, float2(0.30293f, 0.86036f), float2(0.30898f, 0.85482f), float2(0.31501f, 0.85465f))));
    d = min(d, abs(sdBezier(p, float2(0.31501f, 0.85465f), float2(0.31776f, 0.88040f), float2(0.32606f, 0.89047f))));
    d = min(d, abs(sdBezier(p, float2(0.32606f, 0.89047f), float2(0.33177f, 0.87568f), float2(0.33472f, 0.85465f))));
    d = min(d, abs(sdBezier(p, float2(0.33472f, 0.85465f), float2(0.33919f, 0.83841f), float2(0.34366f, 0.82318f))));
    d = min(d, abs(sdBezier(p, float2(0.34366f, 0.82318f), float2(0.35580f, 0.81369f), float2(0.35732f, 0.78328f))));
    d = min(d, abs(sdBezier(p, float2(0.35732f, 0.78328f), float2(0.35936f, 0.69918f), float2(0.36099f, 0.61508f))));
    d = min(d, abs(sdBezier(p, float2(0.36099f, 0.61508f), float2(0.36324f, 0.48969f), float2(0.36152f, 0.36429f))));
    d = min(d, abs(sdBezier(p, float2(0.36152f, 0.36429f), float2(0.36506f, 0.31506f), float2(0.36546f, 0.26474f))));
    d = min(d, abs(sdBezier(p, float2(0.36546f, 0.26474f), float2(0.36691f, 0.18469f), float2(0.36676f, 0.10361f))));
    d = min(d, abs(sdBezier(p, float2(0.36676f, 0.10361f), float2(0.35508f, 0.05216f), float2(0.34733f, 0.04057f))));
    d = min(d, abs(sdBezier(p, float2(0.34733f, 0.04057f), float2(0.32802f, 0.00211f), float2(0.32842f, 0.03917f))));
    return d;
}

// SDF for letter X
static inline float sdLetterX(float2 p) {
    float d = 1e10f;
    d = min(d, abs(sdBezier(p, float2(0.56488f, 0.02518f), float2(0.54673f, 0.07491f), float2(0.52784f, 0.12254f))));
    d = min(d, abs(sdBezier(p, float2(0.52784f, 0.12254f), float2(0.51462f, 0.16085f), float2(0.50103f, 0.19821f))));
    d = min(d, abs(sdBezier(p, float2(0.50103f, 0.19821f), float2(0.49592f, 0.22500f), float2(0.48921f, 0.24867f))));
    d = min(d, abs(sdBezier(p, float2(0.48921f, 0.24867f), float2(0.48767f, 0.26256f), float2(0.48080f, 0.28721f))));
    d = min(d, abs(sdBezier(p, float2(0.48080f, 0.28721f), float2(0.47751f, 0.29306f), float2(0.47590f, 0.29128f))));
    d = min(d, abs(sdBezier(p, float2(0.47590f, 0.29128f), float2(0.47499f, 0.29085f), float2(0.47397f, 0.29142f))));
    d = min(d, abs(sdBezier(p, float2(0.47397f, 0.29142f), float2(0.46642f, 0.27582f), float2(0.46242f, 0.25288f))));
    d = min(d, abs(sdBezier(p, float2(0.46242f, 0.25288f), float2(0.44466f, 0.18160f), float2(0.42536f, 0.11344f))));
    d = min(d, abs(sdBezier(p, float2(0.42536f, 0.11344f), float2(0.41638f, 0.06613f), float2(0.39593f, 0.06507f))));
    d = min(d, abs(sdBezier(p, float2(0.39593f, 0.06507f), float2(0.38857f, 0.04426f), float2(0.38044f, 0.05810f))));
    d = min(d, abs(sdBezier(p, float2(0.38044f, 0.05810f), float2(0.37058f, 0.08612f), float2(0.37650f, 0.12467f))));
    d = min(d, abs(sdBezier(p, float2(0.37650f, 0.12467f), float2(0.37945f, 0.16213f), float2(0.38595f, 0.19753f))));
    d = min(d, abs(sdBezier(p, float2(0.38595f, 0.19753f), float2(0.40545f, 0.31818f), float2(0.42694f, 0.43788f))));
    d = min(d, abs(sdBezier(p, float2(0.42694f, 0.43788f), float2(0.43109f, 0.45481f), float2(0.42851f, 0.47284f))));
    d = min(d, abs(sdBezier(p, float2(0.42851f, 0.47284f), float2(0.40448f, 0.58950f), float2(0.38279f, 0.71037f))));
    d = min(d, abs(sdBezier(p, float2(0.38279f, 0.71037f), float2(0.37151f, 0.73748f), float2(0.37045f, 0.77621f))));
    d = min(d, abs(sdBezier(p, float2(0.37045f, 0.77621f), float2(0.36817f, 0.81475f), float2(0.36387f, 0.85329f))));
    d = min(d, abs(sdBezier(p, float2(0.36387f, 0.85329f), float2(0.36047f, 0.91055f), float2(0.37203f, 0.95632f))));
    d = min(d, abs(sdBezier(p, float2(0.37203f, 0.95632f), float2(0.37839f, 0.96002f), float2(0.38279f, 0.94790f))));
    d = min(d, abs(sdBezier(p, float2(0.38279f, 0.94790f), float2(0.41093f, 0.93879f), float2(0.43035f, 0.88554f))));
    d = min(d, abs(sdBezier(p, float2(0.43035f, 0.88554f), float2(0.44297f, 0.84405f), float2(0.45400f, 0.80139f))));
    d = min(d, abs(sdBezier(p, float2(0.45400f, 0.80139f), float2(0.46298f, 0.73862f), float2(0.48106f, 0.69981f))));
    d = min(d, abs(sdBezier(p, float2(0.48106f, 0.69981f), float2(0.49603f, 0.76052f), float2(0.51259f, 0.81891f))));
    d = min(d, abs(sdBezier(p, float2(0.51259f, 0.81891f), float2(0.52443f, 0.85808f), float2(0.54175f, 0.87285f))));
    d = min(d, abs(sdBezier(p, float2(0.54175f, 0.87285f), float2(0.55312f, 0.86155f), float2(0.56488f, 0.85126f))));
    d = min(d, abs(sdBezier(p, float2(0.56488f, 0.85126f), float2(0.57860f, 0.83715f), float2(0.57933f, 0.79791f))));
    d = min(d, abs(sdBezier(p, float2(0.57933f, 0.79791f), float2(0.57120f, 0.73823f), float2(0.55594f, 0.69003f))));
    d = min(d, abs(sdBezier(p, float2(0.55594f, 0.69003f), float2(0.55659f, 0.63346f), float2(0.54227f, 0.58632f))));
    d = min(d, abs(sdBezier(p, float2(0.54227f, 0.58632f), float2(0.53096f, 0.54263f), float2(0.51968f, 0.49879f))));
    d = min(d, abs(sdBezier(p, float2(0.51968f, 0.49879f), float2(0.51685f, 0.47092f), float2(0.52546f, 0.44625f))));
    d = min(d, abs(sdBezier(p, float2(0.52546f, 0.44625f), float2(0.53426f, 0.40994f), float2(0.54387f, 0.37479f))));
    d = min(d, abs(sdBezier(p, float2(0.54387f, 0.37479f), float2(0.55503f, 0.30580f), float2(0.56462f, 0.23463f))));
    d = min(d, abs(sdBezier(p, float2(0.56462f, 0.23463f), float2(0.57868f, 0.16792f), float2(0.58879f, 0.09591f))));
    d = min(d, abs(sdBezier(p, float2(0.58879f, 0.09591f), float2(0.58666f, 0.05443f), float2(0.57905f, 0.01816f))));
    d = min(d, abs(sdBezier(p, float2(0.57905f, 0.01816f), float2(0.57644f, 0.01416f), float2(0.57338f, 0.01415f))));
    d = min(d, abs(sdBezier(p, float2(0.57338f, 0.01415f), float2(0.56815f, 0.01412f), float2(0.56488f, 0.02518f))));
    return d;
}

// SDF for letter Y
static inline float sdLetterY(float2 p) {
    float d = 1e10f;
    d = min(d, abs(sdBezier(p, float2(0.80290f, 0.05737f), float2(0.79647f, 0.08312f), float2(0.78847f, 0.10574f))));
    d = min(d, abs(sdBezier(p, float2(0.78847f, 0.10574f), float2(0.78263f, 0.09259f), float2(0.77558f, 0.08894f))));
    d = min(d, abs(sdBezier(p, float2(0.77558f, 0.08894f), float2(0.76561f, 0.09155f), float2(0.75718f, 0.10361f))));
    d = min(d, abs(sdBezier(p, float2(0.75718f, 0.10361f), float2(0.72857f, 0.18282f), float2(0.70700f, 0.27670f))));
    d = min(d, abs(sdBezier(p, float2(0.70700f, 0.27670f), float2(0.70116f, 0.26637f), float2(0.69651f, 0.25075f))));
    d = min(d, abs(sdBezier(p, float2(0.69651f, 0.25075f), float2(0.67734f, 0.20473f), float2(0.65972f, 0.15333f))));
    d = min(d, abs(sdBezier(p, float2(0.65972f, 0.15333f), float2(0.64462f, 0.10766f), float2(0.62479f, 0.07979f))));
    d = min(d, abs(sdBezier(p, float2(0.62479f, 0.07979f), float2(0.60933f, 0.06633f), float2(0.59745f, 0.09804f))));
    d = min(d, abs(sdBezier(p, float2(0.59745f, 0.09804f), float2(0.60088f, 0.16003f), float2(0.61295f, 0.21570f))));
    d = min(d, abs(sdBezier(p, float2(0.61295f, 0.21570f), float2(0.63732f, 0.32535f), float2(0.67234f, 0.41193f))));
    d = min(d, abs(sdBezier(p, float2(0.67234f, 0.41193f), float2(0.65074f, 0.51543f), float2(0.63107f, 0.62205f))));
    d = min(d, abs(sdBezier(p, float2(0.63107f, 0.62205f), float2(0.61616f, 0.71049f), float2(0.60010f, 0.79791f))));
    d = min(d, abs(sdBezier(p, float2(0.60010f, 0.79791f), float2(0.59311f, 0.82804f), float2(0.58853f, 0.86036f))));
    d = min(d, abs(sdBezier(p, float2(0.58853f, 0.86036f), float2(0.58660f, 0.89512f), float2(0.58984f, 0.92902f))));
    d = min(d, abs(sdBezier(p, float2(0.58984f, 0.92902f), float2(0.59706f, 0.93028f), float2(0.60429f, 0.92543f))));
    d = min(d, abs(sdBezier(p, float2(0.60429f, 0.92543f), float2(0.60437f, 0.96830f), float2(0.61559f, 0.99970f))));
    d = min(d, abs(sdBezier(p, float2(0.61559f, 0.99970f), float2(0.62291f, 0.98734f), float2(0.63107f, 0.98004f))));
    d = min(d, abs(sdBezier(p, float2(0.63107f, 0.98004f), float2(0.65920f, 0.97358f), float2(0.66920f, 0.90510f))));
    d = min(d, abs(sdBezier(p, float2(0.66920f, 0.90510f), float2(0.68446f, 0.84851f), float2(0.69389f, 0.78251f))));
    d = min(d, abs(sdBezier(p, float2(0.69389f, 0.78251f), float2(0.70215f, 0.73784f), float2(0.71043f, 0.69216f))));
    d = min(d, abs(sdBezier(p, float2(0.71043f, 0.69216f), float2(0.72396f, 0.62230f), float2(0.73513f, 0.54924f))));
    d = min(d, abs(sdBezier(p, float2(0.73513f, 0.54924f), float2(0.76351f, 0.43489f), float2(0.77690f, 0.30260f))));
    d = min(d, abs(sdBezier(p, float2(0.77690f, 0.30260f), float2(0.79102f, 0.20172f), float2(0.80790f, 0.10293f))));
    d = min(d, abs(sdBezier(p, float2(0.80790f, 0.10293f), float2(0.81093f, 0.07009f), float2(0.80442f, 0.05692f))));
    d = min(d, abs(sdBezier(p, float2(0.80442f, 0.05692f), float2(0.80374f, 0.05692f), float2(0.80290f, 0.05737f))));
    return d;
}

// SDF for letter C
static inline float sdLetterC(float2 p) {
    float d = 1e10f;
    d = min(d, abs(sdBezier(p, float2(0.95866f, 0.04327f), float2(0.92036f, 0.07244f), float2(0.88536f, 0.12631f))));
    d = min(d, abs(sdBezier(p, float2(0.88536f, 0.12631f), float2(0.85332f, 0.18646f), float2(0.82372f, 0.25717f))));
    d = min(d, abs(sdBezier(p, float2(0.82372f, 0.25717f), float2(0.80112f, 0.31809f), float2(0.78310f, 0.39192f))));
    d = min(d, abs(sdBezier(p, float2(0.78310f, 0.39192f), float2(0.75252f, 0.51651f), float2(0.76179f, 0.65986f))));
    d = min(d, abs(sdBezier(p, float2(0.76179f, 0.65986f), float2(0.77857f, 0.76630f), float2(0.81405f, 0.82433f))));
    d = min(d, abs(sdBezier(p, float2(0.81405f, 0.82433f), float2(0.82002f, 0.84103f), float2(0.82758f, 0.84945f))));
    d = min(d, abs(sdBezier(p, float2(0.82758f, 0.84945f), float2(0.84489f, 0.87509f), float2(0.86383f, 0.87847f))));
    d = min(d, abs(sdBezier(p, float2(0.86383f, 0.87847f), float2(0.87792f, 0.87545f), float2(0.88703f, 0.84317f))));
    d = min(d, abs(sdBezier(p, float2(0.88703f, 0.84317f), float2(0.91324f, 0.82217f), float2(0.93073f, 0.76251f))));
    d = min(d, abs(sdBezier(p, float2(0.93073f, 0.76251f), float2(0.94420f, 0.72268f), float2(0.95979f, 0.68887f))));
    d = min(d, abs(sdBezier(p, float2(0.95979f, 0.68887f), float2(0.96635f, 0.66078f), float2(0.97250f, 0.63170f))));
    d = min(d, abs(sdBezier(p, float2(0.97250f, 0.63170f), float2(0.97570f, 0.57918f), float2(0.98713f, 0.53842f))));
    d = min(d, abs(sdBezier(p, float2(0.98713f, 0.53842f), float2(0.98828f, 0.51534f), float2(0.99184f, 0.49689f))));
    d = min(d, abs(sdBezier(p, float2(0.99184f, 0.49689f), float2(1.00195f, 0.46866f), float2(0.99933f, 0.47107f))));
    d = min(d, abs(sdBezier(p, float2(0.99933f, 0.47107f), float2(0.98992f, 0.46962f), float2(0.98065f, 0.48055f))));
    d = min(d, abs(sdBezier(p, float2(0.98065f, 0.48055f), float2(0.97116f, 0.49183f), float2(0.96115f, 0.48986f))));
    d = min(d, abs(sdBezier(p, float2(0.96115f, 0.48986f), float2(0.91318f, 0.55215f), float2(0.86106f, 0.55331f))));
    d = min(d, abs(sdBezier(p, float2(0.86106f, 0.55331f), float2(0.85748f, 0.55222f), float2(0.85341f, 0.55318f))));
    d = min(d, abs(sdBezier(p, float2(0.85341f, 0.55318f), float2(0.84330f, 0.55879f), float2(0.83756f, 0.53918f))));
    d = min(d, abs(sdBezier(p, float2(0.83756f, 0.53918f), float2(0.83416f, 0.51042f), float2(0.83700f, 0.48044f))));
    d = min(d, abs(sdBezier(p, float2(0.83700f, 0.48044f), float2(0.85029f, 0.40484f), float2(0.87017f, 0.34092f))));
    d = min(d, abs(sdBezier(p, float2(0.87017f, 0.34092f), float2(0.88159f, 0.30730f), float2(0.89423f, 0.27596f))));
    d = min(d, abs(sdBezier(p, float2(0.89423f, 0.27596f), float2(0.92627f, 0.21076f), float2(0.96197f, 0.16313f))));
    d = min(d, abs(sdBezier(p, float2(0.96197f, 0.16313f), float2(0.97640f, 0.14536f), float2(0.98825f, 0.11695f))));
    d = min(d, abs(sdBezier(p, float2(0.98825f, 0.11695f), float2(0.98985f, 0.08854f), float2(0.99017f, 0.05891f))));
    d = min(d, abs(sdBezier(p, float2(0.99017f, 0.05891f), float2(0.98312f, 0.03609f), float2(0.97251f, 0.03749f))));
    d = min(d, abs(sdBezier(p, float2(0.97251f, 0.03749f), float2(0.96529f, 0.03796f), float2(0.95866f, 0.04327f))));
    return d;
}

// ============================================================================
// Shader Helper Functions
// ============================================================================

static inline float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}

static inline float2 hash2(float2 p) {
    return float2(
        fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f),
        fract(sin(dot(p, float2(269.5f, 183.3f))) * 43758.5453f)
    );
}

// Get SDF for a specific letter index (0=W, 1=X, 2=Y, 3=C)
static inline float getLetterSDF(float2 p, int letterIndex) {
    switch (letterIndex) {
        case 0: return sdLetterW(p);
        case 1: return sdLetterX(p);
        case 2: return sdLetterY(p);
        case 3: return sdLetterC(p);
        default: return 1e10f;
    }
}

// Letter bounding boxes (approximate, in normalized coordinates)
constant float2 letterOffsets[4] = {
    float2(0.0f, 0.0f),      // W starts at x ≈ 0
    float2(0.37f, 0.0f),     // X starts at x ≈ 0.37
    float2(0.59f, 0.0f),     // Y starts at x ≈ 0.59
    float2(0.76f, 0.0f)      // C starts at x ≈ 0.76
};

constant float letterWidths[4] = {
    0.37f,   // W width
    0.22f,   // X width
    0.22f,   // Y width
    0.24f    // C width
};

// ============================================================================
// Main Shader
// ============================================================================

// Core implementation - single layer, no neighbor checking for performance
static half4 driftingWXYCImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);
    float2 uv = position / iResolution;

    // Aspect ratio correction
    float aspect = iResolution.x / iResolution.y;
    uv.x *= aspect;

    float t = time * 0.15f;  // Slow drift

    float3 col = float3(0.02f, 0.02f, 0.05f);  // Dark background

    // Single layer grid of drifting letters
    float gridSize = 0.35f;

    // Offset for drift animation
    float2 offset = float2(t * 0.05f, -t * 0.025f);
    float2 gridUV = (uv + offset) / gridSize;

    float2 cellID = floor(gridUV);
    float2 cellUV = fract(gridUV);

    // Random values for this cell
    float2 randVals = hash2(cellID);

    // Pick a random letter (0-3)
    int letterIdx = int(randVals.x * 4.0f) % 4;

    // Random rotation
    float rotation = randVals.y * 6.28318f + t * (randVals.x - 0.5f) * 0.5f;

    // Transform UV to letter space
    float2 letterUV = cellUV - 0.5f;

    // Apply rotation
    float c = cos(rotation);
    float s = sin(rotation);
    letterUV = float2(c * letterUV.x - s * letterUV.y,
                      s * letterUV.x + c * letterUV.y);

    // Scale and center the letter
    float letterScale = 2.2f;
    letterUV = letterUV * letterScale;

    // Offset to letter's actual position in the logo
    letterUV.x += letterOffsets[letterIdx].x + letterWidths[letterIdx] * 0.5f;
    letterUV.y += 0.5f;  // Center vertically

    // Get SDF distance
    float d = getLetterSDF(letterUV, letterIdx);

    // Convert to visual
    float strokeWidth = 0.012f;
    float glow = 0.04f;

    // Stroke
    float stroke = smoothstep(strokeWidth + glow, strokeWidth, abs(d));

    // Inner glow
    float innerGlow = smoothstep(0.08f, 0.0f, abs(d)) * 0.3f;

    // Color based on letter
    float hue = float(letterIdx) * 0.25f + t * 0.1f;
    hue = fract(hue);

    // HSV to RGB (simplified)
    float3 rgb = clamp(abs(fract(hue + float3(0.0f, 0.333f, 0.667f)) * 6.0f - 3.0f) - 1.0f, 0.0f, 1.0f);
    float3 letterColor = mix(float3(1.0f), rgb, 0.7f);

    // Accumulate color
    col += letterColor * (stroke + innerGlow) * 0.8f;

    // Tone mapping
    col = col / (1.0f + col);

    // Slight vignette
    float2 vignetteUV = position / iResolution - 0.5f;
    float vignette = 1.0f - dot(vignetteUV, vignetteUV) * 0.5f;
    col *= vignette;

    return half4(half3(col), 1.0h);
}

[[ stitchable ]]
half4 driftingWXYC(float2 position,
                   half4 inColor,
                   float width,
                   float height,
                   float time)
{
    return driftingWXYCImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 driftingWXYCFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return driftingWXYCImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
