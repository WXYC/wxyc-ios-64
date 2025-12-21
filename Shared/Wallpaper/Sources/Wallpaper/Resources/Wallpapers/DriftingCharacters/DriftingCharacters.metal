//
//  DriftingCharacters.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//  Procedural WXYC glyph SDFs
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
// WXYC Glyph SDF Functions
// ============================================================================

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

// Simplified W glyph SDF
static inline float sdLetterW(float2 p) {
    float d = 1e10f;
    d = min(d, abs(sdBezier(p, float2(0.32842f, 0.03917f), float2(0.31987f, 0.11573f), float2(0.31213f, 0.19333f))));
    d = min(d, abs(sdBezier(p, float2(0.31213f, 0.19333f), float2(0.30291f, 0.25917f), float2(0.29847f, 0.32923f))));
    d = min(d, abs(sdBezier(p, float2(0.29847f, 0.32923f), float2(0.29660f, 0.39122f), float2(0.29400f, 0.45323f))));
    d = min(d, abs(sdBezier(p, float2(0.29400f, 0.45323f), float2(0.27843f, 0.40210f), float2(0.26248f, 0.35097f))));
    d = min(d, abs(sdBezier(p, float2(0.26248f, 0.35097f), float2(0.25275f, 0.29960f), float2(0.24303f, 0.24939f))));
    d = min(d, abs(sdBezier(p, float2(0.24303f, 0.24939f), float2(0.22786f, 0.18542f), float2(0.20439f, 0.14142f))));
    d = min(d, abs(sdBezier(p, float2(0.17577f, 0.14355f), float2(0.17124f, 0.18408f), float2(0.16631f, 0.22344f))));
    d = min(d, abs(sdBezier(p, float2(0.16631f, 0.22344f), float2(0.16007f, 0.25722f), float2(0.15659f, 0.29418f))));
    d = min(d, abs(sdBezier(p, float2(0.15659f, 0.29418f), float2(0.15416f, 0.35468f), float2(0.14817f, 0.41401f))));
    d = min(d, abs(sdBezier(p, float2(0.14817f, 0.41401f), float2(0.14082f, 0.48037f), float2(0.14214f, 0.55205f))));
    d = min(d, abs(sdBezier(p, float2(0.08539f, 0.74610f), float2(0.09596f, 0.78818f), float2(0.10535f, 0.83228f))));
    d = min(d, abs(sdBezier(p, float2(0.10535f, 0.83228f), float2(0.11954f, 0.90359f), float2(0.14397f, 0.94644f))));
    d = min(d, abs(sdBezier(p, float2(0.21203f, 0.71666f), float2(0.21531f, 0.65328f), float2(0.21464f, 0.58991f))));
    d = min(d, abs(sdBezier(p, float2(0.24040f, 0.67599f), float2(0.25562f, 0.74949f), float2(0.27562f, 0.81339f))));
    d = min(d, abs(sdBezier(p, float2(0.27562f, 0.81339f), float2(0.28788f, 0.84363f), float2(0.30293f, 0.86036f))));
    d = min(d, abs(sdBezier(p, float2(0.35732f, 0.78328f), float2(0.35936f, 0.69918f), float2(0.36099f, 0.61508f))));
    d = min(d, abs(sdBezier(p, float2(0.36099f, 0.61508f), float2(0.36324f, 0.48969f), float2(0.36152f, 0.36429f))));
    d = min(d, abs(sdBezier(p, float2(0.36676f, 0.10361f), float2(0.35508f, 0.05216f), float2(0.34733f, 0.04057f))));
    return d;
}

// Simplified X glyph SDF
static inline float sdLetterX(float2 p) {
    float d = 1e10f;
    d = min(d, abs(sdBezier(p, float2(0.56488f, 0.02518f), float2(0.54673f, 0.07491f), float2(0.52784f, 0.12254f))));
    d = min(d, abs(sdBezier(p, float2(0.52784f, 0.12254f), float2(0.51462f, 0.16085f), float2(0.50103f, 0.19821f))));
    d = min(d, abs(sdBezier(p, float2(0.50103f, 0.19821f), float2(0.49592f, 0.22500f), float2(0.48921f, 0.24867f))));
    d = min(d, abs(sdBezier(p, float2(0.46242f, 0.25288f), float2(0.44466f, 0.18160f), float2(0.42536f, 0.11344f))));
    d = min(d, abs(sdBezier(p, float2(0.37650f, 0.12467f), float2(0.37945f, 0.16213f), float2(0.38595f, 0.19753f))));
    d = min(d, abs(sdBezier(p, float2(0.38595f, 0.19753f), float2(0.40545f, 0.31818f), float2(0.42694f, 0.43788f))));
    d = min(d, abs(sdBezier(p, float2(0.42851f, 0.47284f), float2(0.40448f, 0.58950f), float2(0.38279f, 0.71037f))));
    d = min(d, abs(sdBezier(p, float2(0.38279f, 0.71037f), float2(0.37151f, 0.73748f), float2(0.37045f, 0.77621f))));
    d = min(d, abs(sdBezier(p, float2(0.36387f, 0.85329f), float2(0.36047f, 0.91055f), float2(0.37203f, 0.95632f))));
    d = min(d, abs(sdBezier(p, float2(0.43035f, 0.88554f), float2(0.44297f, 0.84405f), float2(0.45400f, 0.80139f))));
    d = min(d, abs(sdBezier(p, float2(0.48106f, 0.69981f), float2(0.49603f, 0.76052f), float2(0.51259f, 0.81891f))));
    d = min(d, abs(sdBezier(p, float2(0.51259f, 0.81891f), float2(0.52443f, 0.85808f), float2(0.54175f, 0.87285f))));
    d = min(d, abs(sdBezier(p, float2(0.57933f, 0.79791f), float2(0.57120f, 0.73823f), float2(0.55594f, 0.69003f))));
    d = min(d, abs(sdBezier(p, float2(0.54227f, 0.58632f), float2(0.53096f, 0.54263f), float2(0.51968f, 0.49879f))));
    d = min(d, abs(sdBezier(p, float2(0.52546f, 0.44625f), float2(0.53426f, 0.40994f), float2(0.54387f, 0.37479f))));
    d = min(d, abs(sdBezier(p, float2(0.54387f, 0.37479f), float2(0.55503f, 0.30580f), float2(0.56462f, 0.23463f))));
    return d;
}

// Simplified Y glyph SDF
static inline float sdLetterY(float2 p) {
    float d = 1e10f;
    d = min(d, abs(sdBezier(p, float2(0.80290f, 0.05737f), float2(0.79647f, 0.08312f), float2(0.78847f, 0.10574f))));
    d = min(d, abs(sdBezier(p, float2(0.75718f, 0.10361f), float2(0.72857f, 0.18282f), float2(0.70700f, 0.27670f))));
    d = min(d, abs(sdBezier(p, float2(0.69651f, 0.25075f), float2(0.67734f, 0.20473f), float2(0.65972f, 0.15333f))));
    d = min(d, abs(sdBezier(p, float2(0.65972f, 0.15333f), float2(0.64462f, 0.10766f), float2(0.62479f, 0.07979f))));
    d = min(d, abs(sdBezier(p, float2(0.59745f, 0.09804f), float2(0.60088f, 0.16003f), float2(0.61295f, 0.21570f))));
    d = min(d, abs(sdBezier(p, float2(0.61295f, 0.21570f), float2(0.63732f, 0.32535f), float2(0.67234f, 0.41193f))));
    d = min(d, abs(sdBezier(p, float2(0.67234f, 0.41193f), float2(0.65074f, 0.51543f), float2(0.63107f, 0.62205f))));
    d = min(d, abs(sdBezier(p, float2(0.63107f, 0.62205f), float2(0.61616f, 0.71049f), float2(0.60010f, 0.79791f))));
    d = min(d, abs(sdBezier(p, float2(0.60010f, 0.79791f), float2(0.59311f, 0.82804f), float2(0.58853f, 0.86036f))));
    d = min(d, abs(sdBezier(p, float2(0.58984f, 0.92902f), float2(0.59706f, 0.93028f), float2(0.60429f, 0.92543f))));
    d = min(d, abs(sdBezier(p, float2(0.66920f, 0.90510f), float2(0.68446f, 0.84851f), float2(0.69389f, 0.78251f))));
    d = min(d, abs(sdBezier(p, float2(0.69389f, 0.78251f), float2(0.70215f, 0.73784f), float2(0.71043f, 0.69216f))));
    d = min(d, abs(sdBezier(p, float2(0.71043f, 0.69216f), float2(0.72396f, 0.62230f), float2(0.73513f, 0.54924f))));
    d = min(d, abs(sdBezier(p, float2(0.73513f, 0.54924f), float2(0.76351f, 0.43489f), float2(0.77690f, 0.30260f))));
    d = min(d, abs(sdBezier(p, float2(0.77690f, 0.30260f), float2(0.79102f, 0.20172f), float2(0.80790f, 0.10293f))));
    return d;
}

// Simplified C glyph SDF
static inline float sdLetterC(float2 p) {
    float d = 1e10f;
    d = min(d, abs(sdBezier(p, float2(0.95866f, 0.04327f), float2(0.92036f, 0.07244f), float2(0.88536f, 0.12631f))));
    d = min(d, abs(sdBezier(p, float2(0.88536f, 0.12631f), float2(0.85332f, 0.18646f), float2(0.82372f, 0.25717f))));
    d = min(d, abs(sdBezier(p, float2(0.82372f, 0.25717f), float2(0.80112f, 0.31809f), float2(0.78310f, 0.39192f))));
    d = min(d, abs(sdBezier(p, float2(0.78310f, 0.39192f), float2(0.75252f, 0.51651f), float2(0.76179f, 0.65986f))));
    d = min(d, abs(sdBezier(p, float2(0.76179f, 0.65986f), float2(0.77857f, 0.76630f), float2(0.81405f, 0.82433f))));
    d = min(d, abs(sdBezier(p, float2(0.81405f, 0.82433f), float2(0.82002f, 0.84103f), float2(0.82758f, 0.84945f))));
    d = min(d, abs(sdBezier(p, float2(0.82758f, 0.84945f), float2(0.84489f, 0.87509f), float2(0.86383f, 0.87847f))));
    d = min(d, abs(sdBezier(p, float2(0.88703f, 0.84317f), float2(0.91324f, 0.82217f), float2(0.93073f, 0.76251f))));
    d = min(d, abs(sdBezier(p, float2(0.93073f, 0.76251f), float2(0.94420f, 0.72268f), float2(0.95979f, 0.68887f))));
    d = min(d, abs(sdBezier(p, float2(0.95979f, 0.68887f), float2(0.96635f, 0.66078f), float2(0.97250f, 0.63170f))));
    d = min(d, abs(sdBezier(p, float2(0.83700f, 0.48044f), float2(0.85029f, 0.40484f), float2(0.87017f, 0.34092f))));
    d = min(d, abs(sdBezier(p, float2(0.87017f, 0.34092f), float2(0.88159f, 0.30730f), float2(0.89423f, 0.27596f))));
    d = min(d, abs(sdBezier(p, float2(0.89423f, 0.27596f), float2(0.92627f, 0.21076f), float2(0.96197f, 0.16313f))));
    d = min(d, abs(sdBezier(p, float2(0.96197f, 0.16313f), float2(0.97640f, 0.14536f), float2(0.98825f, 0.11695f))));
    return d;
}

// Get glyph SDF by index (0=W, 1=X, 2=Y, 3=C)
static inline float getGlyphDist2D(float2 p, int idx) {
    // Center and scale the glyph
    p = p * 2.5f + float2(0.5f, 0.5f);
    switch (idx % 4) {
        case 0: return sdLetterW(p);
        case 1: return sdLetterX(p);
        case 2: return sdLetterY(p);
        case 3: return sdLetterC(p);
        default: return 1e10f;
    }
}

// ============================================================================
// Shader Helper Functions
// ============================================================================

static inline float3x3 rotateAxis(float3 axis, float theta) {
    axis = normalize(axis);
    float x = axis.x, y = axis.y, z = axis.z;
    float s = sin(theta), c = cos(theta), o = 1.0f - c;
    return float3x3(
        float3(o*x*x+c, o*x*y+z*s, o*z*x-y*s),
        float3(o*x*y-z*s, o*y*y+c, o*y*z+x*s),
        float3(o*z*x+y*s, o*y*z-x*s, o*z*z+c)
    );
}

static inline float3x3 lookat(float3 eye, float3 target) {
    float3 w = normalize(target - eye);
    float3 u = normalize(cross(w, float3(0.0f, 1.0f, 0.0f)));
    return float3x3(u, cross(u, w), w);
}

static inline float hash13(float3 p3) {
    p3 = fract(p3 * 443.8975f);
    p3 += dot(p3, p3.yzx + 19.19f);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float3 hash33(float3 p3) {
    p3 = fract(p3 * float3(0.1031f, 0.1030f, 0.0973f));
    p3 += dot(p3, p3.yxz + 19.19f);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 3D character distance field using procedural SDF
static inline float deChar(float3 p, int charIdx) {
    float w = getGlyphDist2D(p.xy * 0.13f, charIdx);
    w = smoothstep(0.03f, 0.0f, w) * 2.0f - 1.0f;
    w *= 0.3f;

    float2 d = float2(w, abs(p.z) - 0.2f);
    return length(max(d, 0.0f)) - 0.02f;
}

static inline float mapA(float3 p, float time) {
    p = rotateAxis(float3(1.0f, 2.0f, 3.0f), 0.7f) * p;
    float3 seed = floor(p / 10.0f);
    p = fmod(p + 1000.0f, 10.0f) - 5.0f;
    if (hash13(seed + float3(188.0f, 345.0f, 277.0f)) < 0.8f) return 1.0f;
    p = rotateAxis(hash33(seed + float3(324.0f, 154.0f, 997.0f)) - 0.5f, time * 1.2f) * p;
    int charIdx = int(hash13(seed + float3(124.0f, 458.0f, 206.0f)) * 4.0f);
    return deChar(p, charIdx);
}

static inline float mapB(float3 p, float time) {
    p = rotateAxis(float3(1.0f), 1.0f) * p;
    float3 seed = floor(p / 8.0f);
    p = fmod(p + 1000.0f, 8.0f) - 4.0f;
    if (hash13(seed + float3(102.0f, 345.0f, 582.0f)) < 0.8f) return 1.0f;
    p = rotateAxis(hash33(seed + float3(253.0f, 155.0f, 787.0f)) - 0.5f, time * 0.8f + 1.2f) * p;
    int charIdx = int(hash13(seed + float3(158.0f, 344.0f, 266.0f)) * 4.0f);
    return deChar(p, charIdx);
}

static inline float mapC(float3 p, float time) {
    p += 3.5f;
    p = rotateAxis(float3(3.0f, 2.0f, 1.0f), 1.5f) * p;
    float3 seed = floor(p / 8.0f);
    p = fmod(p + 1000.0f, 8.0f) - 4.0f;
    if (hash13(seed + float3(129.0f, 457.0f, 628.0f)) < 0.8f) return 1.0f;
    p = rotateAxis(hash33(seed + float3(262.0f, 456.0f, 776.0f)) - 0.5f, time + 0.5f) * p;
    int charIdx = int(hash13(seed + float3(142.0f, 245.0f, 590.0f)) * 4.0f);
    return deChar(p, charIdx);
}

static inline float map(float3 p, float time) {
    return min(min(mapA(p, time), mapB(p, time)), mapC(p, time));
}

static inline float3 calcNormal(float3 p, float time) {
    float3 n = float3(0.0f);
    for (int i = 0; i < 4; i++) {
        float3 e = float3(float(((i + 3) >> 1) & 1), float((i >> 1) & 1), float(i & 1)) * 2.0f - 1.0f;
        n += e * map(p + 0.001f * e, time);
    }
    return normalize(n);
}

static inline float3 doColor(float3 p, float time) {
    const float precis = 0.001f;
    if (mapA(p, time) < precis) return float3(0.3f, 0.7f, 0.2f);  // Green
    if (mapB(p, time) < precis) return float3(0.7f, 0.3f, 0.2f);  // Red-orange
    if (mapC(p, time) < precis) return float3(0.3f, 0.7f, 0.5f);  // Cyan
    return float3(1.0f, 0.2f, 0.2f);
}

// Core implementation
static half4 driftingCharactersImpl(float2 position, float width, float height, float time) {
    float2 iResolution = float2(width, height);
    float2 p = (position * 2.0f - iResolution) / iResolution.y;

    float3 ro = float3(0.0f, 0.0f, 10.0f);
    float3 rd = normalize(float3(p, -2.0f));

    // Camera sequence
    float tmpTime = fmod(time, 30.0f);
    int phaseNumber = 0;
    float phaseTime = tmpTime;

    if (tmpTime < 5.0f) {
        phaseNumber = 0;
        phaseTime = tmpTime;
    } else if (tmpTime < 12.0f) {
        phaseNumber = 3;
        phaseTime = tmpTime - 5.0f;
    } else if (tmpTime < 17.0f) {
        phaseNumber = 1;
        phaseTime = tmpTime - 12.0f;
    } else if (tmpTime < 25.0f) {
        phaseNumber = 2;
        phaseTime = tmpTime - 17.0f;
    } else {
        phaseNumber = 3;
        phaseTime = tmpTime - 25.0f;
    }

    float offset = floor(time / 30.0f) * 80.0f;

    if (phaseNumber == 0) {
        ro.x += phaseTime * 5.0f + offset;
    } else if (phaseNumber == 1) {
        ro.y += -phaseTime * 5.0f + offset;
    } else if (phaseNumber == 2) {
        ro.z += phaseTime * 7.0f + offset;
    } else {
        float3 ta = float3(0.0f);
        ro = rotateAxis(float3(1.0f), -fmod(phaseTime * 0.3f + offset, 6.283f)) * float3(0.0f, 0.0f, 30.0f);
        rd = lookat(ro, ta) * rd;
    }

    // Background gradient
    float3 col = mix(float3(0.5f, 0.3f, 0.0f), float3(0.8f), smoothstep(1.5f, 3.5f, length(p * float2(1.0f, 2.0f))));

    const float maxd = 80.0f;
    const float precis = 0.001f;
    float t = 0.0f;
    float d = 0.0f;

    // Ray marching
    for (int i = 0; i < 80; i++) {  // Reduced iterations for mobile
        t += d = map(ro + rd * t, time);
        if (d < precis || t > maxd) break;
    }

    if (d < precis) {
        float3 hitPos = ro + rd * t;
        float3 nor = calcNormal(hitPos, time);
        float3 li = normalize(float3(1.0f));
        float3 bg = col;
        col = doColor(hitPos, time);
        float dif = clamp(dot(nor, li), 0.3f, 1.0f);
        float amb = max(0.5f + 0.5f * nor.y, 0.0f);
        float spc = pow(clamp(dot(reflect(normalize(hitPos - ro), nor), li), 0.0f, 1.0f), 30.0f);
        col *= dif * amb;
        col += spc;
        col = clamp(col, 0.0f, 1.0f);
        col = mix(bg, col, exp(-t * t * 0.0001f));
        col = pow(col, float3(0.8f));
    }

    return half4(half3(col), 1.0h);
}

[[ stitchable ]]
half4 driftingCharacters(float2 position,
                         half4 inColor,
                         float width,
                         float height,
                         float time)
{
    return driftingCharactersImpl(position, width, height, time);
}

// Fragment wrapper for MTKView rendering
fragment half4 driftingCharactersFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return driftingCharactersImpl(pos, u.resolution.x, u.resolution.y, u.time);
}
