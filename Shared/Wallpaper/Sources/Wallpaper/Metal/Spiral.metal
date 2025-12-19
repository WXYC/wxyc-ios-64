//
//  Spiral.metal
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

[[ stitchable ]]
half4 spiral(float2 position,
             half4 inColor,
             float width,
             float height,
             float time)
{
    float2 iResolution = float2(width, height);
    float2 fragCoord = position;
    float iTime = time;

    float2 uv = (fragCoord - 0.5f * iResolution) / max(iResolution.y, 1.0f);

    float a = atan2(uv.y, uv.x);
    float2 p = cos(a + iTime) * float2(cos(0.5f * iTime), sin(0.3f * iTime));

    float d1 = length(uv - p);
    float d2 = length(uv);

    float luv = max(length(uv), 1e-6f);
    float denom = max(d1 + d2, 1e-6f);
    float2 ratio = clamp(float2(d1, d2) / denom, float2(1e-4f), float2(1.0f));

    float2 uv2 = 2.0f * cos(log(luv) * 0.25f - 0.5f * iTime + log(ratio));

    float2 fpos = fract(4.0f * uv2) - 0.5f;
    float d = max(fabs(fpos.x), fabs(fpos.y));

    float k = 5.0f / max(iResolution.y, 1.0f);
    float s = smoothstep(-k, k, 0.25f - d);

    float3 col = float3(s, 0.5f * s, 0.1f - 0.1f * s);

    col += (1.0f / cosh(-2.5f * (length(uv - p) + length(uv))))
         * float3(1.0f, 0.5f, 0.1f);

    float c = cos(10.0f * length(uv2) + 4.0f * iTime);

    float angle = 9.0f * a + iTime;
    float field = cos(angle) * uv.x + sin(angle) * uv.y + 0.1f * c;

    col += (0.5f + 0.5f * c) * float3(0.5f, 1.0f, 1.0f)
         * exp(-9.0f * fabs(field));

    return half4(half3(col), 1.0h);
}
