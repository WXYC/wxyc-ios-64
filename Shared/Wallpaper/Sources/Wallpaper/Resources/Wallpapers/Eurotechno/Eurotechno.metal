//
//  Eurotechno.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//  Audio-reactive 4D raymarching with reflections
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

static inline float comp(float3 p) {
    p = asin(sin(p) * 0.9f);
    return length(p) - 1.0f;
}

static inline float3 erot(float3 p, float3 ax, float ro) {
    return mix(dot(p, ax) * ax, p, cos(ro)) + sin(ro) * cross(ax, p);
}

static inline float smin(float a, float b, float k) {
    float h = max(0.0f, k - abs(b - a)) / k;
    return min(a, b) - h * h * h * k / 6.0f;
}

static inline float4 wrot(float4 p) {
    return float4(dot(p, float4(1.0f)), p.yzw + p.zwy - p.wyz - p.xxx) / 2.0f;
}

struct SceneResult {
    float dist;
    float d1, d2, d3;
    float lazors, doodad;
    float3 p2;
};

static inline SceneResult scene(float3 p, float t, float bass, float beat) {
    SceneResult r;

    r.p2 = erot(p, float3(0.0f, 1.0f, 0.0f), t);
    r.p2 = erot(r.p2, float3(0.0f, 0.0f, 1.0f), t / 3.0f);
    r.p2 = erot(r.p2, float3(1.0f, 0.0f, 0.0f), t / 5.0f);

    // Use beat and bass to modulate the 4D transformations
    float4 p4 = float4(r.p2, 0.0f);
    p4 = mix(p4, wrot(p4), smoothstep(-0.5f, 0.5f, sin(t / 4.0f) + bass * 0.5f));
    p4 = abs(p4);
    p4 = mix(p4, wrot(p4), smoothstep(-0.5f, 0.5f, sin(t) + beat * 0.3f));

    // Bass affects the size pulsing
    float fctr = smoothstep(-0.5f, 0.5f, sin(t / 2.0f)) + bass * 0.3f;
    float fctr2 = smoothstep(0.9f, 1.0f, sin(t / 16.0f)) + beat * 0.5f;
    r.doodad = length(max(abs(p4) - mix(0.05f, 0.07f + beat * 0.02f, fctr), 0.0f) + mix(-0.1f, 0.2f, fctr))
               - mix(0.15f, 0.55f + bass * 0.1f, fctr * fctr) + fctr2;

    p.x += asin(sin(t / 80.0f) * 0.99f) * 80.0f;

    // Lazors pulse with beat
    r.lazors = length(asin(sin(erot(p, float3(1.0f, 0.0f, 0.0f), t * 0.2f).yz * 0.5f + 1.0f)) / 0.5f) - 0.1f - beat * 0.05f;
    r.d1 = comp(p);
    r.d2 = comp(erot(p + 5.0f, normalize(float3(1.0f, 3.0f, 4.0f)), 0.4f));
    r.d3 = comp(erot(p + 10.0f, normalize(float3(3.0f, 2.0f, 1.0f)), 1.0f));

    r.dist = min(r.doodad, min(r.lazors, 0.3f - smin(smin(r.d1, r.d2, 0.05f), r.d3, 0.05f)));

    return r;
}

static inline float sceneDistOnly(float3 p, float t, float bass, float beat) {
    float3 p2 = erot(p, float3(0.0f, 1.0f, 0.0f), t);
    p2 = erot(p2, float3(0.0f, 0.0f, 1.0f), t / 3.0f);
    p2 = erot(p2, float3(1.0f, 0.0f, 0.0f), t / 5.0f);

    float4 p4 = float4(p2, 0.0f);
    p4 = mix(p4, wrot(p4), smoothstep(-0.5f, 0.5f, sin(t / 4.0f) + bass * 0.5f));
    p4 = abs(p4);
    p4 = mix(p4, wrot(p4), smoothstep(-0.5f, 0.5f, sin(t) + beat * 0.3f));

    float fctr = smoothstep(-0.5f, 0.5f, sin(t / 2.0f)) + bass * 0.3f;
    float fctr2 = smoothstep(0.9f, 1.0f, sin(t / 16.0f)) + beat * 0.5f;
    float doodad = length(max(abs(p4) - mix(0.05f, 0.07f + beat * 0.02f, fctr), 0.0f) + mix(-0.1f, 0.2f, fctr))
                   - mix(0.15f, 0.55f + bass * 0.1f, fctr * fctr) + fctr2;

    p.x += asin(sin(t / 80.0f) * 0.99f) * 80.0f;

    float lazors = length(asin(sin(erot(p, float3(1.0f, 0.0f, 0.0f), t * 0.2f).yz * 0.5f + 1.0f)) / 0.5f) - 0.1f - beat * 0.05f;
    float d1 = comp(p);
    float d2 = comp(erot(p + 5.0f, normalize(float3(1.0f, 3.0f, 4.0f)), 0.4f));
    float d3 = comp(erot(p + 10.0f, normalize(float3(3.0f, 2.0f, 1.0f)), 1.0f));

    return min(doodad, min(lazors, 0.3f - smin(smin(d1, d2, 0.05f), d3, 0.05f)));
}

static inline float3 norm(float3 p, float t, float bass, float beat) {
    float precis = length(p) < 1.0f ? 0.005f : 0.01f;
    float3x3 k = float3x3(p, p, p) - float3x3(float3(precis, 0.0f, 0.0f),
                                               float3(0.0f, precis, 0.0f),
                                               float3(0.0f, 0.0f, precis));
    float base = sceneDistOnly(p, t, bass, beat);
    return normalize(float3(base - sceneDistOnly(k[0], t, bass, beat),
                            base - sceneDistOnly(k[1], t, bass, beat),
                            base - sceneDistOnly(k[2], t, bass, beat)));
}

// Core implementation
static half4 eurotechnoImpl(float2 position, float width, float height, float time,
                            float audioLevel, float audioBass, float audioMid,
                            float audioHigh, float audioBeat) {
    float2 iResolution = float2(width, height);
    float2 uv = (position - 0.5f * iResolution) / iResolution.y;

    // Use audio to modulate animation speed
    float speedMod = 1.0f + audioBass * 0.5f;
    float t = time * speedMod;

    // Camera movement affected by audio
    float3 cam = normalize(float3(0.8f + sin(t * 3.14f / 4.0f) * 0.3f + audioMid * 0.1f, uv));
    float3 init = float3(-1.5f + sin(t * 3.14f) * 0.2f, 0.0f, 0.0f) + cam * 0.2f;

    init = erot(init, float3(0.0f, 1.0f, 0.0f), sin(t * 0.2f) * 0.4f);
    init = erot(init, float3(0.0f, 0.0f, 1.0f), cos(t * 0.2f) * 0.4f);
    cam = erot(cam, float3(0.0f, 1.0f, 0.0f), sin(t * 0.2f) * 0.4f);
    cam = erot(cam, float3(0.0f, 0.0f, 1.0f), cos(t * 0.2f) * 0.4f);

    float3 p = init;
    bool hit = false;
    float atten = 1.0f;
    float glo = 0.0f;
    float dist;
    float fog = 0.0f;
    float dlglo = 0.0f;
    bool trg = false;

    SceneResult sr;

    for (int i = 0; i < 80 && !hit; i++) {
        sr = scene(p, t, audioBass, audioBeat);
        dist = sr.dist;
        hit = dist * dist < 1e-6f;

        // Glow intensity affected by audio
        float glowMod = 1.0f + audioLevel * 2.0f;
        glo += 0.2f / (1.0f + sr.lazors * sr.lazors * 20.0f) * atten * glowMod;
        dlglo += 0.2f / (1.0f + sr.doodad * sr.doodad * 20.0f) * atten * glowMod;

        if (hit && ((sin(sr.d3 * 45.0f) < -0.4f && (dist != sr.doodad)) ||
                    (dist == sr.doodad && sin(pow(length(sr.p2 * sr.p2 * sr.p2), 0.3f) * 120.0f) > 0.4f)) &&
            dist != sr.lazors) {
            trg = trg || (dist == sr.doodad);
            hit = false;
            float3 n = norm(p, t, audioBass, audioBeat);
            atten *= 1.0f - abs(dot(cam, n)) * 0.98f;
            cam = reflect(cam, n);
            dist = 0.1f;
        }

        p += cam * dist;
        fog += dist * atten / 30.0f;
    }

    fog = smoothstep(0.0f, 1.0f, fog);
    bool lz = (sr.lazors == dist);
    bool dl = (sr.doodad == dist);

    // Fog color shifts with audio
    float3 fogcol = mix(float3(0.5f + audioHigh * 0.2f, 0.8f, 1.2f),
                        float3(0.4f, 0.6f + audioBass * 0.2f, 0.9f), length(uv));

    float3 n = norm(p, t, audioBass, audioBeat);
    float3 r = reflect(cam, n);
    float ss = smoothstep(-0.3f, 0.3f, sceneDistOnly(p + float3(0.3f), t, audioBass, audioBeat)) + 0.5f;
    float fact = length(sin(r * (dl ? 4.0f : 3.0f)) * 0.5f + 0.5f) / sqrt(3.0f) * 0.7f + 0.3f;

    // Material color modulated by audio
    float3 matcol = mix(float3(0.9f + audioBeat * 0.2f, 0.4f, 0.3f),
                        float3(0.3f, 0.4f + audioMid * 0.3f, 0.8f),
                        smoothstep(-1.0f, 1.0f, sin(sr.d1 * 5.0f + time * 2.0f)));
    matcol = mix(matcol, float3(0.5f + audioHigh * 0.2f, 0.4f, 1.0f),
                 smoothstep(0.0f, 1.0f, sin(sr.d2 * 5.0f + time * 2.0f)));

    if (dl) matcol = mix(float3(1.0f), matcol, 0.1f) * 0.2f + 0.1f;

    float3 col = matcol * fact * ss + pow(fact, 10.0f);

    // Lazors brightness boosted by beat
    if (lz) col = float3(4.0f + audioBeat * 2.0f);

    col = col * atten + glo * glo + fogcol * glo;
    col = mix(col, fogcol, fog);

    if (!dl) col = abs(erot(col, normalize(sin(p * 2.0f)), 0.2f * (1.0f - fog)));
    if (!trg && !dl) col += dlglo * dlglo * 0.1f * float3(0.4f + audioBass * 0.2f, 0.6f, 0.9f);

    col = sqrt(col);
    col = smoothstep(float3(0.0f), float3(1.2f), col);

    return half4(half3(col), 1.0h);
}

[[ stitchable ]]
half4 eurotechno(float2 position,
                 half4 inColor,
                 float width,
                 float height,
                 float time,
                 float audioLevel,
                 float audioBass,
                 float audioMid,
                 float audioHigh,
                 float audioBeat)
{
    return eurotechnoImpl(position, width, height, time,
                          audioLevel, audioBass, audioMid, audioHigh, audioBeat);
}

// Fragment wrapper for MTKView rendering (with audio support)
fragment half4 eurotechnoFrag(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pos = in.uv * u.resolution;
    return eurotechnoImpl(pos, u.resolution.x, u.resolution.y, u.time,
                          u.audioLevel, u.audioBass, u.audioMid, u.audioHigh, u.audioBeat);
}
