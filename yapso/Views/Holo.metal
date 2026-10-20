#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float grain(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

/// Holographic foil for the profile card. The card is drawn in greys first: light greys become pearl with a pastel
/// wash, dark greys (the engraved artwork and lettering) become saturated rainbow foil. The rainbow drifts across the
/// surface and with `tilt` (device attitude, roughly -1...1 on each axis); a soft sheen slides opposite the tilt, and
/// a fine grain sits over everything.
[[ stitchable ]] half4 holoFoil(float2 position, half4 color, float2 size, float2 tilt) {
    if (color.a < 0.001) { return color; }
    float3 rgb = float3(color.rgb) / float(color.a);
    float2 uv = position / size;

    float lum = dot(rgb, float3(0.299, 0.587, 0.114));
    // 1 on the engraving, 0 on the card body, smooth across anti-aliased edges.
    float ink = 1.0 - smoothstep(0.35, 0.85, lum);

    float phase = dot(uv - 0.5, float2(0.55, 0.85)) * 1.7 + tilt.x * 0.8 + tilt.y * 0.55;
    float3 rainbow = 0.5 + 0.5 * cos(6.28318 * (phase + float3(0.0, 0.33, 0.67)));

    float3 pearl = mix(float3(0.965, 0.955, 0.975), rainbow, 0.2);
    float3 foil = rainbow * 0.72 + 0.06;
    float3 result = mix(pearl, foil, ink);

    float2 light = float2(0.5 - tilt.x * 0.55, 0.32 - tilt.y * 0.55);
    float2 d = (uv - light) * float2(1.0, size.y / size.x);
    result += exp(-dot(d, d) * 7.0) * (0.32 - ink * 0.12);

    result += (grain(floor(position)) - 0.5) * 0.05;
    return half4(half3(clamp(result, 0.0, 1.0)) * color.a, color.a);
}
