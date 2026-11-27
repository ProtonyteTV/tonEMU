// Liquid Glass: SDF lens refraction + light blur + saturation + specular rim.
// Used as ImageFilter.shader inside a BackdropFilter (Impeller). The FIRST sampler is the backdrop.
// All lengths are PHYSICAL pixels. One pass, at most 7 texture fetches, no loops.
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2  uSize;        // glass size
uniform float uRadius;      // corner radius (clamped to min(size)/2 in Dart)
uniform float uBezel;       // rim thickness where the lens bends light
uniform float uRefraction;  // max displacement at the very edge
uniform float uBlur;        // blur radius (0 = single tap)
uniform float uDispersion;  // chromatic split at the rim (0 = off)
uniform float uSaturation;  // 1 = unchanged
uniform float uSpecular;    // rim highlight strength
uniform vec2  uLight;       // unit vector pointing TOWARDS the light (screen space, y down)
uniform vec4  uTint;        // rgb = tint colour, a = tint amount

uniform sampler2D uBackdrop;

out vec4 fragColor;

vec3 grab(vec2 p) {
    return texture(uBackdrop, clamp(p, vec2(0.5), uSize - vec2(0.5)) / uSize).rgb;
}

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec2 half_ = uSize * 0.5;
    vec2 p = frag - half_;
    float r = min(uRadius, min(half_.x, half_.y));

    // Signed distance to the rounded rectangle (negative inside).
    vec2 q = abs(p) - (half_ - vec2(r));
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
    float depth = -d;                       // distance from the edge, going inwards

    float aa = 1.0 - smoothstep(-0.75, 0.75, d);
    if (aa <= 0.0) { fragColor = vec4(0.0); return; }

    // Outward normal of the shape.
    vec2 s = vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
    vec2 n;
    if (q.x > 0.0 && q.y > 0.0) n = normalize(q) * s;
    else if (q.x > q.y)         n = vec2(s.x, 0.0);
    else                        n = vec2(0.0, s.y);

    // Lens: strongest bend at the edge, fading to zero at the bezel depth.
    float t = clamp(depth / max(uBezel, 1.0), 0.0, 1.0);
    float m = 1.0 - t;
    float bend = m * m * sqrt(m);           // ~ (1-t)^2.5, cheap squircle-like falloff
    vec2 dir = -n;                          // light bends towards the lens centre
    vec2 pos = frag + dir * (uRefraction * bend);

    vec3 col;
    if (uBlur > 0.5) {
        vec2 o = vec2(uBlur);
        col = grab(pos) * 0.4
            + (grab(pos + vec2( o.x,  o.y)) + grab(pos + vec2(-o.x,  o.y))
             + grab(pos + vec2( o.x, -o.y)) + grab(pos + vec2(-o.x, -o.y))) * 0.15;
    } else {
        col = grab(pos);
    }

    // Chromatic dispersion, only inside the rim.
    if (uDispersion > 0.001 && bend > 0.02) {
        float k = uRefraction * bend * uDispersion * 0.35;
        col.r = grab(pos + dir * k).r;
        col.b = grab(pos - dir * k).b;
    }

    // Saturation boost (Apple's glass makes what is behind it a little more vivid).
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(lum), col, uSaturation);

    // Tint.
    col = mix(col, uTint.rgb, uTint.a);

    // Specular rim: bright where the edge faces the light, faint on the far side.
    float facing = dot(n, normalize(uLight));
    float lit = pow(max(facing, 0.0), 1.6) + 0.35 * pow(max(-facing, 0.0), 1.6);
    float band = 1.0 - smoothstep(0.0, max(uBezel * 0.30, 1.5), depth);
    float line = 1.0 - smoothstep(0.0, 1.4, depth);
    float spec = uSpecular * (band * (0.10 + 0.55 * lit) + line * (0.18 + 0.50 * lit));

    // Soft inner glow along the lit side.
    spec += uSpecular * 0.10 * lit * (1.0 - smoothstep(0.0, uBezel * 1.6, depth));

    col = clamp(col + vec3(spec), 0.0, 1.0);
    fragColor = vec4(col * aa, aa);
}
