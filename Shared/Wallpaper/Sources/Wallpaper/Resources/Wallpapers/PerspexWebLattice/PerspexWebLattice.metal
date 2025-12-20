//
//  PerspexWebLattice.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

#include <metal_stdlib>
using namespace metal;

#define FAR 2.0

struct Uniforms {
    float2 resolution;   // pixels
    float  time;         // seconds
    float  _pad;         // alignment
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen triangle (no vertex buffer)
vertex VSOut vertexMain(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2( 3.0, -1.0), float2(-1.0,  3.0) };
    float2 uv [3] = { float2( 0.0,  0.0), float2( 2.0,  0.0), float2( 0.0,  2.0) };

    VSOut o;
    o.position = float4(pos[vid], 0.0, 1.0);
    o.uv = uv[vid];
    return o;
}



inline float  sat(float  x) { return clamp(x, 0.0, 1.0); }
inline float3 sat(float3 x) { return clamp(x, 0.0, 1.0); }

inline float3 mix3(float3 a, float3 b, float3 t) { return a + (b - a) * t; }
inline float3 mix3(float3 a, float3 b, float  t) { return a + (b - a) * t; }

// Tri-planar blend
float3 tex3D(texture2d<float> tex, sampler smp, float3 p, float3 n) {
    n = max((abs(n) - 0.2), 0.001);
    n /= (n.x + n.y + n.z);

    float3 tX = tex.sample(smp, p.yz).xyz;
    float3 tY = tex.sample(smp, p.zx).xyz;
    float3 tZ = tex.sample(smp, p.xy).xyz;

    float3 col = tX * n.x + tY * n.y + tZ * n.z;

    // Loose sRGB->linear-ish compensation (matches original shader intent)
    return col * col;
}

// IQ-style compact 3D value noise
float n3D(float3 p) {
    const float3 s = float3(7.0, 157.0, 113.0);
    float3 ip = floor(p);
    p -= ip;

    float4 h = float4(0.0, s.y, s.z, s.y + s.z) + dot(ip, s);

    p = p * p * (3.0 - 2.0 * p);

    float4 a = fract(sin(h) * 43758.5453);
    float4 b = fract(sin(h + s.x) * 43758.5453);

    h = mix(a, b, p.x);
    h.xy = mix(h.xz, h.yw, p.y);
    return mix(h.x, h.y, p.z);
}

float2 hash22(float2 p, float time) {
    float n = sin(dot(p, float2(41.0, 289.0)));
    p = fract(float2(262144.0, 32768.0) * n);
    return sin(p * 6.2831853 + time) * 0.45 + 0.5;
}

float Voronoi(float2 p, float time) {
    float2 g = floor(p);
    p -= g;

    float3 d = float3(1.0);

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 o = float2((float)x, (float)y);
            o += hash22(g + o, time) - p;

            d.z = dot(o, o);
            d.y = max(d.x, min(d.y, d.z));
            d.x = min(d.x, d.z);
        }
    }

    return max(d.y / 1.2 - d.x * 1.0, 0.0) / 1.2;
}

float heightMap(float3 p, float time, thread int &objId) {
    objId = 0;
    float c = Voronoi(p.xy * 4.0, time);

    if (c < 0.07) {
        c = smoothstep(0.7, 1.0, 1.0 - c) * 0.2;
        objId = 1;
    }
    return c;
}

float m(float3 p, float time) {
    int dummy = 0;
    float h = heightMap(p, time, dummy);
    return 1.0 - p.z - h * 0.1;
}

// Normal + edge in one pass
float3 nr(float3 p, float time, thread float &edge) {
    float2 e = float2(0.005, 0.0);

    float d1 = m(p + float3(e.x, e.y, e.y), time);
    float d2 = m(p - float3(e.x, e.y, e.y), time);
    float d3 = m(p + float3(e.y, e.x, e.y), time);
    float d4 = m(p - float3(e.y, e.x, e.y), time);
    float d5 = m(p + float3(e.y, e.y, e.x), time);
    float d6 = m(p - float3(e.y, e.y, e.x), time);

    float d0 = m(p, time) * 2.0;

    edge = fabs(d1 + d2 - d0) + fabs(d3 + d4 - d0) + fabs(d5 + d6 - d0);
    edge = smoothstep(0.0, 1.0, sqrt(edge / e.x * 2.0));

    return normalize(float3(d1 - d2, d3 - d4, d5 - d6));
}

float3 eMap(float3 rd, float3 sn, float time) {
    (void)sn;

    float3 sRd = rd;

    rd.xy -= time * 0.25;
    rd *= 3.0;

    float c = n3D(rd) * 0.57 + n3D(rd * 2.0) * 0.28 + n3D(rd * 4.0) * 0.15;
    c = smoothstep(0.5, 1.0, c);

    float3 col = float3(min(c * 1.5, 1.0), pow(c, 2.5), pow(c, 12.0)).zyx;

    return mix3(col, col.yzx, sRd * 0.25 + 0.25);
}

fragment float4 fragmentMain(
    VSOut in [[stage_in]],
    constant Uniforms &u [[buffer(0)]],
    texture2d<float> iChannel0 [[texture(0)]],
    sampler smp [[sampler(0)]]
) {
    float2 fragCoord = in.uv * u.resolution;

    float3 r = normalize(float3(fragCoord - u.resolution * 0.5, u.resolution.y));
    float3 o = float3(0.0);
    float3 l = o + float3(0.0, 0.0, -1.0);

    float2 a = sin(float2(1.570796, 0.0) + u.time / 8.0);

    // rotation matrix with columns (a.x, -a.y) and (a.y, a.x)
    float2x2 rot = float2x2(float2(a.x, -a.y), float2(a.y, a.x));
    r.xy = rot * r.xy;

    float d = 0.0;
    float t = 0.0;

    for (int i = 0; i < 32; i++) {
        d = m(o + r * t, u.time);
        if (fabs(d) < 0.001 || t > FAR) break;
        t += d * 0.7;
    }

    t = min(t, (float)FAR);

    float3 col = float3(0.0);

    if (t < FAR) {
        float3 p = o + r * t;

        float edge = 0.0;
        float3 n = nr(p, u.time, edge);

        float3 ldir = l - p;
        float dist = max(length(ldir), 0.001);
        ldir /= dist;

        int objId = 0;
        float hm = heightMap(p, u.time, objId);

        float3 tx = tex3D(iChannel0, smp, (p * 2.0 + hm * 0.2), n);

        col = float3(1.0) * (hm * 0.8 + 0.2);
        col *= float3(1.5) * tx;

        float gray = dot(col, float3(0.299, 0.587, 0.114));

        if (objId == 0) {
            col *= float3(min(gray * 1.5, 1.0), pow(gray, 5.0), pow(gray, 24.0)) * 2.0;
        } else {
            col *= 0.1;
        }

        float df = max(dot(ldir, n), 0.0);
        float sp = pow(max(dot(reflect(-ldir, n), -r), 0.0), 32.0);
        if (objId == 1) sp *= sp;

        col = col * (df + 0.75)
            + float3(1.0, 0.97, 0.92) * sp
            + float3(0.5, 0.7, 1.0) * pow(sp, 32.0);

        float3 em = eMap(reflect(r, n), n, u.time);
        if (objId == 1) em *= 0.5;
        col += em;

        col *= 1.0 - edge * 0.8;
        col *= 1.0 / (1.0 + dist * dist * 0.125);
    }

    col = sqrt(sat(col)); // matches original "gamma-ish" output
    return float4(col, 1.0);
}
