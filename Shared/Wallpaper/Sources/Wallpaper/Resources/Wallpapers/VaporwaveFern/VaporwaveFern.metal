//
//  VaporwaveFern.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//  Two-pass shader: Buffer A renders fern, Main applies post-processing
//

#include <metal_stdlib>
using namespace metal;

// === MTKView Support ===
struct Uniforms {
    float2 resolution;
    float time;
    float displayScale;
    int frame;
    int passIndex;
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
// Buffer A: Fern Rendering
// ============================================================================

// Colors used to draw the plant
constant float3 LEAF = float3(0.89f, 0.435f, 0.9f);
constant float3 LEAF_TIP = float3(0.68f, 0.7f, 0.97f);
constant float3 LEAF_OUTLINE = float3(0.7f, 0.75f, 0.95f);
constant float THRESH = 0.5f;
constant float STEPS = 25.0f;
constant float STROKE = 0.8f;
constant float LEAF_COUNT = 19.0f;
constant float EPS = 0.01f;

static float2 interpolate(float2 a, float2 b, float2 c, float2 d, float p) {
    float2 v0 = mix(a, b, p);
    float2 v1 = mix(b, c, p);
    float2 v2 = mix(c, d, p);
    float2 v3 = mix(v0, v1, p);
    float2 v4 = mix(v1, v2, p);
    return mix(v3, v4, p);
}

static float df_line(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0f, 1.0f);
    return length(pa - ba * h);
}

static float sharpen(float d, float w, float2 iResolution) {
    float e = 1.0f / min(iResolution.y, iResolution.x);
    return 1.0f - smoothstep(-e, e, d - w);
}

static float sdEgg(float2 p, float ra, float rb) {
    const float k = sqrt(3.0f);
    p.x = abs(p.x);
    float r = ra - rb;
    return ((p.y < 0.0f) ? length(float2(p.x, p.y)) - r :
            (k * (p.x + r) < p.y) ? length(float2(p.x, p.y - k * r)) :
            length(float2(p.x + r, p.y)) - 2.0f * r) - rb;
}

static float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0f)) + min(max(d.x, d.y), 0.0f);
}

static float sdEquilateralTriangle(float2 p) {
    const float k = sqrt(3.0f);
    p.x = abs(p.x) - 1.0f;
    p.y = p.y + 1.0f / k;
    if (p.x + k * p.y > 0.0f) {
        p = float2(p.x - k * p.y, -k * p.x - p.y) / 2.0f;
    }
    p.x -= clamp(p.x, -2.0f, 0.0f);
    return -length(p) * sign(p.y);
}

static float2 opRep(float2 p, float2 c) {
    return fmod(p + 0.5f * c, c) - 0.5f * c;
}

static float2 opRepLim(float2 p, float2 s, float2 lima, float2 limb) {
    return p - s * clamp(round(p / s), lima, limb);
}

static float polyImpulse(float k, float n, float x) {
    return (n / (n - 1.0f)) * pow((n - 1.0f) * k, 1.0f / n) * x / (1.0f + k * pow(x, n));
}

static float noiseFloat(float2 p) {
    p = fract(p * float2(1000.0f * 0.21353f, 1000.0f * 0.97019f));
    p = p + dot(p, p + 1000.0f * 0.54823f);
    return fract(p.x * p.y);
}

static float2 noiseVector(float2 p) {
    float n = noiseFloat(p);
    return float2(n, noiseFloat(p + n));
}

static float2 GetPos(float2 id, float2 offsets) {
    float2 n = noiseVector(id + offsets) * 500.0f * (8000.0f / (1000.0f * 50.0f));
    return (sin(n) * 0.9f) + offsets;
}

static float Stars(float2 uv, float gain) {
    uv -= 1.0f;
    float m = 0.0f;
    uv = uv * 10.0f;
    float2 gv = fract(uv) - 0.5f;
    float2 id = floor(uv);

    float2 p[9];
    int n = 0;
    for (float y = -1.0f; y <= 1.0f; y++) {
        for (float x = -1.0f; x <= 1.0f; x++) {
            p[n++] = GetPos(id, float2(x, y));
        }
    }
    for (int i = 0; i < 9; i++) {
        float2 j = (p[i] - gv) * 2.0f;
        float sparkle = 0.1f / dot(j, j) * (gain / 8000.0f);
        m = m + sparkle * (sin((8000.0f + p[i].x) * 0.5f) * 0.5f + 0.9f);
    }
    return m;
}

static float Leaf(float2 uv, float radius, float tip, float pos) {
    float2 size = mix(float2(4.0f), float2(0.75f, 0.7f), polyImpulse(1.5f, 1.5f, pos));
    float2 p = uv * size;
    p += float2(0.0f, tip * 0.5f);
    float leaf = sdEgg(p, radius, tip);
    leaf = min(leaf, sdEgg(-p, radius, tip));
    return leaf;
}

static float Margin(float sdf) {
    return clamp(1.0f - smoothstep(0.005f, 0.01f, abs(sdf)), 0.0f, 1.0f);
}

static float AStep(float d) {
    return smoothstep(0.9f, 1.01f, d);
}

static float MStep(float d) {
    return 1.0f - clamp(smoothstep(-0.005f, 0.0f, d), 0.0f, 1.0f);
}

static float2 Rotate2D(float2 p, float theta) {
    float co = cos(theta);
    float si = sin(theta);
    return float2(co * p.x + si * p.y, -si * p.x + co * p.y);
}

static float LeafTier(float2 uv, float2 a, float2 b, float2 c, float2 d,
                      float pos, thread float4& col, float iTime, float2 iResolution) {
    float2 end1 = interpolate(a, b, c, d, 0.0f);
    float2 p = interpolate(a, b, c, d, pos);
    float radius = 0.05f;
    float tip = -0.5f;
    float2 leafPos = uv - p;
    float r = dot(leafPos, end1);
    leafPos = Rotate2D(leafPos, -1.0f + r / max(0.2f, pos));
    float leaf = Leaf(leafPos, radius, tip, pos);
    leafPos = Rotate2D(leafPos, 2.0f - (cos(iTime * 0.5f) * r / max(0.2f, pos)));
    leaf = min(leaf, Leaf(leafPos, radius, tip, pos));
    float maxDist = 0.4f;
    float dist = distance(uv, p);
    dist = clamp(dist / maxDist, 0.0f, 1.0f);
    col.rgb = mix(LEAF, LEAF_TIP, dist);
    col.rgb = mix(col.rgb, LEAF_OUTLINE, Margin(leaf) * dist);
    col.a = step(pos, THRESH);
    return sharpen(leaf, EPS * 1.0f, iResolution);
}

static float Branch(float2 uv, thread float4& leafCol, float iTime, float2 iResolution) {
    float2 a = float2(-0.25f, 0.25f) * 1.0f + (cos(iTime * 0.5f) * 0.25f);
    float2 b = float2(0.0f, 0.75f) * (cos(iTime * 0.25f) * 0.5f + 0.5f);
    float2 c = float2(0.75f, -0.75f);
    float2 d = float2(0.0f, -0.9f);

    float leaf = 0.0f;
    float stem = 0.0f;
    leafCol.a = 0.0f;
    for (float i = 0.0f; i < STEPS; i++) {
        float2 p0 = interpolate(a, b, c, d, i / STEPS);
        float2 p1 = interpolate(a, b, c, d, (i + 1.0f) / STEPS);
        float l = sharpen(df_line(uv, p0, p1), EPS * STROKE, iResolution);
        leafCol.a = stem > l ? leafCol.a : step(i / STEPS, THRESH);
        stem = max(stem, l);
    }
    leaf = stem;
    leafCol.rgb = LEAF * 0.9f * stem;
    for (float i = 0.1f; i < LEAF_COUNT; i++) {
        float4 nextCol;
        float nextLeaf = LeafTier(uv, a, b, c, d, 0.05f * i, nextCol, iTime, iResolution);
        leafCol = mix(leafCol, nextCol, nextLeaf);
        leaf = max(leaf, nextLeaf);
    }
    return leaf;
}

static float IsBlack(float3 col) {
    return step(abs(col.r + col.g + col.b), 0.0f);
}

static float IsWhite(float3 col) {
    return step(1.0f, (col.r + col.g + col.b) / 3.0f);
}

static float3 Dodge(float3 col, float3 effect) {
    float isBlack = IsBlack(effect);
    float3 inverted = (1.0f - effect) * (1.0f - isBlack) + isBlack;
    float anyWhite = min(IsWhite(effect) + IsWhite(col), 1.0f);
    return clamp(col / inverted, 0.0f, 1.0f) * (1.0f - anyWhite) + anyWhite;
}

fragment half4 vaporwaveFernBufferA(VertexOut in [[stage_in]],
                                     constant Uniforms& u [[buffer(0)]]) {
    float2 fragCoord = in.uv * u.resolution;
    float2 iResolution = u.resolution;
    float iTime = u.time;

    float2 uv = (fragCoord / iResolution * 2.0f - 1.0f);
    uv.x *= iResolution.x / iResolution.y;
    uv = uv * 0.8f + float2(0.0f, -0.1f);

    float2 checkUV = opRepLim(uv * 10.0f, float2(2.0f, 0.0f),
                               float2(-10.0f, 0.0f), float2(10.0f, 1.0f));
    float check = sdBox(checkUV, float2(0.5f));
    checkUV = opRepLim(uv * 10.0f + float2(1.0f, 1.0f),
                       float2(2.0f, 0.0f), float2(-10.0f, 0.0f), float2(10.0f, 1.0f));
    check = min(check, sdBox(checkUV, float2(0.5f)));
    float3 bg = mix(float3(1.0f, 0.78f, 1.0f), float3(0.0f), MStep(check));

    float2 gridUV = opRep(uv * 10.0f, float2(1.0f));
    float grid = sdBox(gridUV, float2(0.48f));
    bg = mix(float3(1.0f), bg, MStep(grid));

    float bA = sdBox(uv + float2(0.75f, 0.75f), float2(0.5f, 0.1f));
    float aVal = mix(0.1f, 0.5f, clamp(uv.x * 0.5f + 0.5f, 0.0f, 1.0f));
    float3 dCol = float3(0.9f, 0.9f, 0.1f) * aVal;
    bg = mix(bg, Dodge(dCol, bg), MStep(bA));
    bA = sdBox(uv + float2(-0.75f, -0.5f), float2(0.5f, 0.1f));
    aVal = mix(0.1f, 0.5f, clamp(-uv.x * 0.5f + 0.5f, 0.0f, 1.0f));
    dCol = float3(0.9f, 0.9f, 0.1f) * aVal;
    bg = mix(bg, Dodge(dCol, bg), MStep(bA));

    float specks = smoothstep(0.05f, 0.1f, Stars(uv * 0.5f, 50.0f));
    bg = clamp(bg + specks, 0.0f, 1.0f);

    float3 low = float3(0.8f, 0.035f, 0.96f);
    float3 high = float3(0.39f, 0.69f, 0.94f);
    float3 col = mix(low, high, clamp(uv.y + 1.0f, 0.0f, 1.0f));
    float4 leafCol = float4(col, 0.0f);
    float branch = AStep(Branch(uv, leafCol, iTime, iResolution));
    col = mix(col, leafCol.rgb, branch);
    float2 triUV = uv * 1.5f + float2(0.0f, 0.2f);
    triUV = Rotate2D(triUV, iTime * 0.25f);
    float fullTri = sdEquilateralTriangle(triUV);
    float tri = abs(fullTri) - 0.02f;
    float3 dodge = Dodge(col, col);
    col = mix(col, dodge, MStep(tri));
    col = mix(col, bg, 1.0f - MStep(fullTri));
    col = mix(col, leafCol.rgb, clamp(branch * leafCol.a, 0.0f, 1.0f));

    return half4(half3(col), 1.0h);
}

// ============================================================================
// Main Pass: Post-Processing
// ============================================================================

static float nrand(float x, float y) {
    return fract(sin(dot(float2(x, y), float2(12.9898f, 78.233f))) * 43758.5453f);
}

static float4 Blend(float4 top, float4 bottom) {
    float4 result;
    result.a = top.a + bottom.a * (1.0f - top.a);
    result.rgb = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0f - top.a)) / result.a;
    return result;
}

fragment half4 vaporwaveFernMain(VertexOut in [[stage_in]],
                                  constant Uniforms& u [[buffer(0)]],
                                  texture2d<half> bufferA [[texture(0)]],
                                  sampler s [[sampler(0)]]) {
    float2 iResolution = u.resolution;
    float iTime = u.time;
    float2 uv = in.uv;

    float jitter = nrand(uv.y, iTime / 20.0f) * 2.0f - 1.0f;
    uv.x += jitter * step(0.0f, abs(jitter)) * 0.00175f;

    float2 texel = 1.0f / iResolution;
    float3 duv = texel.xyx * float3(0.5f, 0.5f, -0.5f);

    float3 blur = float3(bufferA.sample(s, uv - duv.xy).rgb);
    blur += float3(bufferA.sample(s, uv - duv.zy).rgb);
    blur += float3(bufferA.sample(s, uv + duv.zy).rgb);
    blur += float3(bufferA.sample(s, uv + duv.xy).rgb);
    blur /= 4.0f;

    float sub = -0.1f;
    float hard = 0.3f;

    float modulo = floor(fmod(uv.x / texel.x * 0.25f, 3.0f));
    float3 tmp = blur;
    float is0 = step(modulo, 0.0f) * step(0.0f, modulo);
    float is1 = step(1.0f, modulo) * step(modulo, 1.0f);
    tmp -= float3(0.0f, sub * hard, sub * hard * 2.0f) * is0;
    tmp -= float3(sub * hard, 0.0f, sub * hard) * step(1.0f, modulo) * step(modulo, 1.0f);
    tmp -= float3(sub * hard * 2.0f, sub * hard, 0.0f) * (1.0f - is0) * (1.0f - is1);
    float3 col = Blend(float4(tmp, 0.9f), float4(blur, 1.0f)).rgb;

    float scanline = sin((uv.y - sin(iTime / 200.0f)) * iResolution.y) * 0.025f;
    col -= scanline;

    return half4(half3(col), 1.0h);
}
