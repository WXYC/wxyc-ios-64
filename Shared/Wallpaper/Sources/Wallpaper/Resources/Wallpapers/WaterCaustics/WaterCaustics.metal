//
//  WaterCaustics.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

#include <metal_stdlib>
using namespace metal;

// ---- 3D simplex noise port (GLSL -> MSL) ----

static inline float4 mod289(float4 x) {
    return x - floor(x / 289.0f) * 289.0f;
}

static inline float4 permute(float4 x) {
    return mod289((x * 34.0f + 1.0f) * x);
}

static inline float4 snoise(float3 v)
{
    const float2 C = float2(1.0f / 6.0f, 1.0f / 3.0f);

    float3 i  = floor(v + dot(v, float3(C.y)));
    float3 x0 = v   - i + dot(i, float3(C.x));

    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0f - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);

    float3 x1 = x0 - i1 + C.x;
    float3 x2 = x0 - i2 + C.y;
    float3 x3 = x0 - 0.5f;

    float4 p =
      permute(permute(permute(i.z + float4(0.0f, i1.z, i2.z, 1.0f))
                            + i.y + float4(0.0f, i1.y, i2.y, 1.0f))
                            + i.x + float4(0.0f, i1.x, i2.x, 1.0f));

    float4 j = p - 49.0f * floor(p / 49.0f);

    float4 x_ = floor(j / 7.0f);
    float4 y_ = floor(j - 7.0f * x_);

    float4 x = (x_ * 2.0f + 0.5f) / 7.0f - 1.0f;
    float4 y = (y_ * 2.0f + 0.5f) / 7.0f - 1.0f;

    float4 h = 1.0f - abs(x) - abs(y);

    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);

    float4 s0 = floor(b0) * 2.0f + 1.0f;
    float4 s1 = floor(b1) * 2.0f + 1.0f;
    float4 sh = -step(h, float4(0.0f));

    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    float3 g0 = float3(a0.xy, h.x);
    float3 g1 = float3(a0.zw, h.y);
    float3 g2 = float3(a1.xy, h.z);
    float3 g3 = float3(a1.zw, h.w);

    float4 m = max(0.6f - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0f);
    float4 m2 = m * m;
    float4 m3 = m2 * m;
    float4 m4 = m2 * m2;

    float3 grad =
      -6.0f * m3.x * x0 * dot(x0, g0) + m4.x * g0 +
      -6.0f * m3.y * x1 * dot(x1, g1) + m4.y * g1 +
      -6.0f * m3.z * x2 * dot(x2, g2) + m4.z * g2 +
      -6.0f * m3.w * x3 * dot(x3, g3) + m4.w * g3;

    float4 px = float4(dot(x0, g0), dot(x1, g1), dot(x2, g2), dot(x3, g3));
    return 42.0f * float4(grad, dot(m4, px));
}

// ---- SwiftUI shader entry point ----

[[stitchable]]
half4 waterCaustics(float2 position,
                    half4  currentColor,
                    float2 resolutionPx,
                    float  timeSeconds,
                    float2 normalizedOffset) // Range [0, 1]
{
    float2 fragCoord = position;

    fragCoord.y = resolutionPx.y - fragCoord.y;

    float2 p = (-resolutionPx + 2.0f * fragCoord) / resolutionPx.y;

    // Offset mapping from normalized [0, 1] to the shader's range
    float prevX = normalizedOffset.x * 4.0f - 2.0f;
    float prevY = normalizedOffset.y * 4.0f - 2.0f;

    // Settings (copied from GLSL)
    float invertY    = -1.0f;
    float yaw        = -0.03f;
    float pitch      = 0.0f;
    float roll       = 0.0f;
    float height     = 2.0f;
    float fov        = 1.0f;
    float scale      = 8.0f;
    float speed      = 0.16f;
    float brightness = 1.7f;
    float contrast   = 2.0f;
    float multiply   = 0.2f;
    float3 rayColour = float3(1.0f, 0.964f, 0.690f);

    float offsetX = -prevX * 15.0f;
    float offsetY =  prevY * 15.0f;

    float3 ww = normalize(invertY * float3(yaw, height, pitch));
    float3 uu = normalize(cross(ww, float3(roll, 1.0f, 0.0f)));
    float3 vv = normalize(cross(uu, ww));

    float3 rd  = p.x * uu + p.y * vv + fov * ww;
    float3 pos = -ww + rd * (ww.y / rd.y);
    pos.y = timeSeconds * speed;
    pos *= scale;

    pos.x += offsetX;
    pos.z += offsetY;

    float4 n = snoise(pos);
    pos -= 0.07f * n.xyz; n = snoise(pos);
    pos -= 0.07f * n.xyz; n = snoise(pos);

    float intensity = exp(n.w * contrast - brightness);

    float fy = fragCoord.y / resolutionPx.y;
    float4 base = float4(234.0f/255.0f - fy*0.7f,
                         235.0f/255.0f - fy*0.4f,
                         166.0f/255.0f - fy*0.1f,
                         1.0f);

    float4 outColor = base + float4(rayColour * multiply * intensity, intensity);
    return half4(outColor);
}
