#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float grain(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

/// The profile card's paper finish. The card is drawn in its real colours (cream, ink, ember); this adds paper grain
/// and a faint glint on the light areas that slides with `tilt` (device attitude, roughly -1...1 on each axis).
[[ stitchable ]] half4 paperSheen(float2 position, half4 color, float2 size, float2 tilt) {
    if (color.a < 0.001) { return color; }
    float3 rgb = float3(color.rgb) / float(color.a);
    float2 uv = position / size;
    float2 light = float2(0.5 - tilt.x * 0.6, 0.3 - tilt.y * 0.6);
    float2 d = (uv - light) * float2(1.0, size.y / size.x);
    float lum = dot(rgb, float3(0.299, 0.587, 0.114));
    rgb += exp(-dot(d, d) * 8.0) * 0.07 * smoothstep(0.5, 0.9, lum);
    rgb += (grain(floor(position)) - 0.5) * 0.045;
    return half4(half3(clamp(rgb, 0.0, 1.0)) * color.a, color.a);
}
