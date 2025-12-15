#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Noise Functions

float rand(float2 st) {
    return fract(sin(dot(st.xy, float2(12.9898,78.233))) * 43758.5453123);
}

float overlay(float base, float blend) {
    return (base <= 0.5)
      ? (2.0*base*blend)
      : (1.0-2.0*(1.0-base)*(1.0-blend));
}

float mapStrength(float2 position, float2 size, float offset, float interpolation, float direction) {
    // 0: topToBottom, 1: bottomToTop, 2: leftToRight, 3: rightToLeft
    int dir = int(direction);
    
    // Normalize coordinate relevant to direction
    float coord;
    bool inverted = false;
    
    if (dir == 0) { // topToBottom
        coord = position.y / size.y;
    } else if (dir == 1) { // bottomToTop
        coord = position.y / size.y;
        inverted = true;
    } else if (dir == 2) { // leftToRight
        coord = position.x / size.x;
    } else { // rightToLeft
        coord = position.x / size.x;
        inverted = true;
    }
    
    // Calculate progress
    // offset is where it STARTS.
    // interpolation is the length of the ramp.
    // if not inverted: 0..offset is 0. offset..offset+interp is 0..1. > is 1.
    // if inverted: like 1..0.
    // Actually, "distance from view's edge".
    // For BottomToTop, it means from Bottom.
    
    if (inverted) {
        coord = 1.0 - coord;
    }
    
    if (coord < offset) {
        return 0.0;
    } else if (coord > offset + interpolation) {
        return 1.0;
    } else {
        return (coord - offset) / interpolation;
    }
}

// MARK: - Blur Shader

[[ stitchable ]] half4 progressiveBlur(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float radius,
    float offsetVal,
    float interpolation,
    float direction,
    float noiseStrength,
    float2 stride // (1,0) or (0,1)
) {
    // 1. Calculate Strength
    float s = mapStrength(position, size, offsetVal, interpolation, direction);
    
    // 2. Variable Blur
    float currentRadius = radius * s;
    
    half4 color = 0;
    float totalWeight = 0;
    
    // Optimization: If radius is very small, just sample center.
    if (currentRadius < 1.0) {
        color = layer.sample(position);
        totalWeight = 1.0;
    } else {
        // Gaussian Loop
        // We limit the loop to avoid TDR or excessive cost.
        // A fixed reasonable max radius like 20-30 pixels.
        // If user asks for more, we clamp or subsample.
        // For 'Progressive', usually we want high quality.
        // Let's use a sigma = radius / 2.
        
        float sigma = max(currentRadius * 0.5, 0.1);
        int blurRadius = min(int(ceil(currentRadius)), 50); // Cap at 50 for performance
        
        // Accumulate center
        color += layer.sample(position);
        totalWeight += 1.0;
        
        for (int i = 1; i <= blurRadius; ++i) {
            float dist = float(i);
            float weight = exp(-(dist * dist) / (2.0 * sigma * sigma));
            
            float2 offset = stride * dist;
            
            color += layer.sample(position + offset) * weight;
            color += layer.sample(position - offset) * weight;
            
            totalWeight += 2.0 * weight;
        }
    }
    
    color /= totalWeight;
    
    // 3. Apply Noise (Only if noiseStrength > 0)
    // We expect the Swift side to pass noiseStrength > 0 only on the LAST pass.
    if (noiseStrength > 0.0 && s > 0.0) {
        // Pseudo-Random Hash
        // "float2 pos = position * 10;"
        // "float2 floored = floor(pos);"
        // "float white = rand(floored) * 0.5 + 0.5;"
        
        float2 noisePos = position * 10.0; // Wait, position is in points? Or pixels?
        // SwiftUI layer position is usually in points (user space).
        // If we want "pixel perfect" noise we might want strictly pixels, but points is fine for consistent look across densities if desired.
        // User said "position * 10".
        
        float2 floored = floor(noisePos);
        float white = rand(floored) * 0.5 + 0.5;
        
        // "Overlay Blend Mode"
        // Blend 'color' with 'white'.
        // Wait, the noise itself is monochrome.
        // Usually we apply independent noise to channels or same noise to all?
        // User: "The same noise value is applied to R, G, and B channels, resulting in monochrome grain."
        
        // We mix based on 's' AND 'noiseStrength'?
        // "float s = mapStrength(...)" - this S is for BLUR.
        // User said: "float s = mapStrength...; return mix(color, newColor, s);"
        // This 's' for noise might be the SAME as blur strength?
        // "Controls where and how strongly noise is applied."
        // "Clamped to [0, strength]" -> Wait, "strength" here refers to "noiseStrength" presumably?
        
        // Let's re-read carefully: "float s = mapStrength(..., strength, ...)"
        // If I reuse `mapStrength` for noise, I should pass `noiseStrength` as the max strength.
        // But the Blur also uses `mapStrength`. The Blur and Noise follow the same gradient?
        // "Directional Noise Mask... This allows noise to fade in across space"
        
        // Yes, likely they fade in together.
        // But the User passed `strength` into `mapStrength`.
        // So for the *Noise* part:
        float noiseS = mapStrength(position, size, offsetVal, interpolation, direction);
        noiseS = clamp(noiseS * noiseStrength, 0.0, 1.0); // Scale by max noise intensity
        
        // Calculate new color with overlay
        half3 c = color.rgb;
        half3 noiseRGB = half3(white);
        
        half3 blended;
        blended.r = overlay(c.r, noiseRGB.r);
        blended.g = overlay(c.g, noiseRGB.g);
        blended.b = overlay(c.b, noiseRGB.b);
        
        // Mix: "return mix(color, newColor, s);"
        // Here s is the noiseS we calculated.
        color.rgb = mix(color.rgb, blended, half(noiseS));
    }
    
    return color;
}
