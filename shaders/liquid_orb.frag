#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform float uProgress;
uniform vec2 uTouch;
uniform vec3 uTint;
uniform float uUseTint;

out vec4 fragColor;

const float GL_KA = 6.0;
const float GL_KG = 4.1209;
const float GL_KR = 0.32;
const float GL_GH = 1.73205081;
const float GL_CLEAR_EA = 0.995;
const float GL_CLEAR_EB = 1.04;

float lqHash(vec2 p) {
    vec2 q = fract(p * vec2(123.34, 456.21));
    q += dot(q, q + 45.32);
    return fract(q.x * q.y);
}

float lqNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(lqHash(i), lqHash(i + vec2(1.0, 0.0)), f.x),
        mix(lqHash(i + vec2(0.0, 1.0)), lqHash(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

vec2 lqFbm(vec2 pIn, float bs) {
    vec2 p = pIn;
    float s = 0.0;
    float a = 0.5;
    float m = 0.0;
    float vr = 0.0;
    float e = -GL_KA * bs * bs;
    float g = 1.0;
    for (int i = 0; i < 5; i++) {
        float b = exp(e * g);
        s += a * (0.5 + b * (lqNoise(p) - 0.5));
        vr += a * a * (1.0 - b * b);
        m += a;
        a *= 0.5;
        g *= GL_KG;
        p = vec2(0.8 * p.x - 0.6 * p.y, 0.6 * p.x + 0.8 * p.y) * 2.03;
    }
    return vec2(s / m, GL_KR * sqrt(max(vr, 0.0)) / m);
}

float lqRidge(float v, float k) {
    return pow(clamp(1.0 - abs(v * 2.0 - 1.0), 0.0, 1.0), k);
}

float lqRidgeS(vec2 vs, float k) {
    float d = GL_GH * vs.y;
    return (lqRidge(vs.x - d, k) + 4.0 * lqRidge(vs.x, k) + lqRidge(vs.x + d, k)) / 6.0;
}

vec2 glsRotate(vec2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

vec3 lqRamp(float v, vec3 cA, vec3 cB, vec3 cC, vec3 cD) {
    vec3 c = mix(cA, cB, smoothstep(0.0, 0.45, v));
    c = mix(c, cC, smoothstep(0.38, 0.72, v));
    c = mix(c, cD, smoothstep(0.68, 1.0, v));
    return c;
}

vec2 glsContourWave(float angle, float t) {
    float wave = sin(angle * 3.0 + t * 0.62) * 0.52 +
                 sin(angle * 5.0 - t * 0.41 + 1.7) * 0.31 +
                 sin(angle * 7.0 + t * 0.23) * 0.17;
    float slope = cos(angle * 3.0 + t * 0.62) * 1.56 +
                  cos(angle * 5.0 - t * 0.41 + 1.7) * 1.55 +
                  cos(angle * 7.0 + t * 0.23) * 1.19;
    return vec2(wave, slope);
}

float glsContourScale(vec2 uv, float t, float amount) {
    if (amount <= 0.0) return 1.0;
    vec2 contour = glsContourWave(atan(uv.y, uv.x), t);
    return 1.0 + clamp(amount, 0.0, 1.0) * 0.11 * contour.x;
}

vec2 glsContourNormal(vec2 uv, float rad, float t, float amount) {
    float dist = length(uv);
    if (dist <= 0.0001) return vec2(0.0);
    vec2 radial = uv / dist;
    vec2 contour = glsContourWave(atan(uv.y, uv.x), t);
    float slope = clamp(amount, 0.0, 1.0) * 0.11 * contour.y;
    vec2 tangent = vec2(-radial.y, radial.x);
    return normalize(radial - tangent * (rad * slope / dist));
}

float glsRefractionProfile(float t) {
    float depth = clamp(t, 0.0, 1.0);
    float circular = sqrt(max(1.0 - (1.0 - depth) * (1.0 - depth), 0.0));
    return 1.0 - circular;
}

float glsHighlightLobe(vec2 normal, vec2 direction, float cut, float power) {
    float angular = clamp((dot(normal, direction) - cut) / max(1.0 - cut, 0.001), 0.0, 1.0);
    return pow(angular, power);
}

vec3 glsOver(vec3 dst, vec3 src, float a) {
    float k = clamp(a, 0.0, 1.0);
    return src * k + dst * (1.0 - k);
}

vec3 glsFinishPresetFluid(vec3 colorIn, vec2 p, float shade, vec3 highlightColor) {
    vec3 color = colorIn;
    color = mix(color, highlightColor, shade * 0.22 * smoothstep(0.15, 1.15, dot(p, vec2(-0.32, 0.78))));
    color *= (1.0 - shade * 0.34 * smoothstep(-0.1, 1.2, dot(p, vec2(0.45, -0.62))));
    color *= (1.0 - shade * 0.22 * smoothstep(0.72, 1.08, length(p)));
    return clamp(color, vec3(0.0), vec3(1.0));
}

vec3 glsBlueDropFluid(
    vec2 p,
    float t,
    float zoom,
    float warp,
    float ridgeAmt,
    float sharp,
    float shade,
    vec3 colorA,
    vec3 colorB,
    vec3 colorC,
    vec3 colorD,
    vec3 highlightColor
) {
    float depth = sqrt(max(1.0 - clamp(dot(p, p), 0.0, 1.0), 0.0));
    vec2 q = p * mix(0.72, 1.0, depth * 0.62 + 0.38);
    q = glsRotate(q, -0.24 + 0.06 * sin(t * 0.17));

    float scale = 1.0 + zoom * 1.12;
    float blur = 0.012 + 0.006 * zoom;

    vec2 driftA = lqFbm(q * 1.28 + vec2(t * 0.095, -t * 0.034), blur * 1.28);
    vec2 driftB = lqFbm(glsRotate(q, 1.08) * 1.62 + vec2(-t * 0.042, t * 0.078), blur * 1.62);

    vec2 flowed = q + vec2(driftA.x - 0.5, driftB.x - 0.5) * (0.24 + warp * 0.1);
    flowed.x += sin(flowed.y * 2.15 + t * 0.24) * (0.035 + warp * 0.012);
    flowed.y += sin(flowed.x * 1.38 - t * 0.18) * (0.045 + warp * 0.01);

    vec2 body = lqFbm(flowed * scale + vec2(t * 0.025, -t * 0.018), blur * scale);

    float marbleScale = 1.72 + zoom * 0.9;
    float marble = lqRidgeS(
        lqFbm(flowed * marbleScale + vec2(2.7, -t * 0.035), blur * marbleScale),
        0.8 + sharp * 0.46
    );

    float value = clamp(mix(body.x, body.x * 0.62 + marble * 0.58, ridgeAmt), 0.0, 1.0);
    vec3 color = lqRamp(value, colorA, colorB, colorC, colorD);

    vec3 surface = normalize(vec3(p.x, p.y, depth));
    vec3 direction = normalize(vec3(-0.48, 0.62, 0.92));
    float light = pow(max(dot(surface, direction), 0.0), 3.2);

    color = mix(color, highlightColor, light * (0.035 + 0.05 * shade));
    color *= 0.74 + 0.26 * depth;

    return glsFinishPresetFluid(color, p, shade, highlightColor);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = (2.0 * fragCoord - uSize) / max(min(uSize.x, uSize.y), 1.0);

    float progress = clamp(uProgress, 0.0, 1.0);

    // Dynamic state interpolation between idle and thinking
    float speed = mix(0.27, 0.90, progress);
    float t = uTime * speed;
    float zoom = mix(0.4464, 0.48, progress);
    float warp = mix(1.325, 2.65, progress);
    float ridgeAmt = mix(0.1932, 0.42, progress);
    float sharp = mix(1.968, 2.40, progress);
    float shade = 0.16;
    float sheen = 0.22;
    float gloss = 0.42;
    float shellMidAlpha = 0.32;
    float shellEdgeAlpha = 0.24;
    float exposure = mix(0.8184, 1.24, progress);
    float glassOpacity = 0.66;
    float contourDeform = mix(0.028, 0.08, progress);
    float baseRad = 0.86;
    float contourRad = baseRad * glsContourScale(uv, t, contourDeform);

    vec3 colorA = mix(vec3(0.0078, 0.0314, 0.0706), vec3(0.0078, 0.0431, 0.1137), progress);
    vec3 colorB = mix(vec3(0.0392, 0.1725, 0.3529), vec3(0.0275, 0.3373, 0.7216), progress);
    vec3 colorC = mix(vec3(0.1412, 0.4039, 0.5412), vec3(0.1176, 0.7843, 1.0), progress);
    vec3 colorD = mix(vec3(0.6431, 0.7647, 0.7922), vec3(0.8667, 0.9843, 1.0), progress);
    vec3 highlightColor = mix(vec3(0.6235, 0.7843, 0.8353), vec3(0.9176, 0.9843, 1.0), progress);

    vec3 shellInner = vec3(0.9647, 0.9922, 1.0);
    vec3 shellMid = vec3(0.3098, 0.8431, 1.0);
    vec3 shellEdge = vec3(0.2745, 0.4275, 1.0);
    vec3 sheenColor = vec3(0.8667, 0.9843, 1.0);
    vec3 specColor = vec3(0.6588, 0.8510, 1.0);
    vec3 canvasColor = vec3(0.0039, 0.0078, 0.0275);
    vec3 glowColor = mix(vec3(0.1216, 0.3137, 0.4627), vec3(0.0863, 0.5529, 1.0), progress);

    // Apply dynamic album palette tinting if enabled (uUseTint > 0.0), else pure blue default
    if (uUseTint > 0.01) {
        float tintWeight = clamp(uUseTint, 0.0, 1.0);
        vec3 tintDark = uTint * 0.15;
        vec3 tintMid = uTint * 0.75;
        vec3 tintVibrant = mix(uTint, vec3(1.0), 0.35);
        vec3 tintLight = mix(uTint, vec3(1.0), 0.75);

        colorA = mix(colorA, tintDark, tintWeight);
        colorB = mix(colorB, tintMid, tintWeight);
        colorC = mix(colorC, tintVibrant, tintWeight);
        colorD = mix(colorD, tintLight, tintWeight);
        shellMid = mix(shellMid, tintVibrant, tintWeight);
        shellEdge = mix(shellEdge, tintMid, tintWeight);
        glowColor = mix(glowColor, tintVibrant, tintWeight);
    }

    float pd = length(uv) / contourRad;

    // Atmospheric outer glow
    if (pd > 1.06) {
        float glowDist = length(uv) - contourRad;
        float haloAlpha = clamp(exp(-max(glowDist, 0.0) * 8.5) * (0.16 + progress * 0.25), 0.0, 1.0);
        fragColor = vec4(glowColor * haloAlpha, haloAlpha);
        return;
    }

    vec2 p = uv / contourRad;
    float clearFa = 1.0 - smoothstep(GL_CLEAR_EA, GL_CLEAR_EB, pd);

    vec2 normal = glsContourNormal(uv, baseRad, t, contourDeform);
    normal = normalize(normal + uTouch * 0.22);

    float edgeDepth = max(1.0 - pd, 0.0);
    float refractionWidth = 0.015 + 0.95 * shellMidAlpha;
    float refractionT = edgeDepth / max(refractionWidth, 0.001);
    float refractionProfile = pow(glsRefractionProfile(refractionT), 0.68);
    float refractionAmount = 1.6 * glassOpacity * refractionProfile;

    vec2 refractedP = p - normal * refractionAmount;
    float channelSplit = 0.14 * gloss * glassOpacity * refractionProfile;

    vec3 redSample = glsBlueDropFluid(
        refractedP - normal * channelSplit, t, zoom, warp, ridgeAmt, sharp, shade,
        colorA, colorB, colorC, colorD, highlightColor
    );
    vec3 greenSample = glsBlueDropFluid(
        refractedP, t, zoom, warp, ridgeAmt, sharp, shade,
        colorA, colorB, colorC, colorD, highlightColor
    );
    vec3 blueSample = glsBlueDropFluid(
        refractedP + normal * channelSplit, t, zoom, warp, ridgeAmt, sharp, shade,
        colorA, colorB, colorC, colorD, highlightColor
    );
    vec3 fcol = vec3(redSample.x, greenSample.y, blueSample.z);

    float lum = dot(fcol, vec3(0.213, 0.715, 0.072));
    vec3 clearSat = clamp(vec3(lum) + (fcol - vec3(lum)) * 1.22, vec3(0.0), vec3(1.0));
    vec3 col = glsOver(canvasColor, clearSat, 0.99 * clearFa);

    // Optical glass rim & dispersion
    float surfaceWidth = 0.026 + 0.055 * shellEdgeAlpha;
    float surfaceBand = (1.0 - smoothstep(0.0, surfaceWidth, edgeDepth)) * clearFa;
    float opticalRim = pow(surfaceBand, 1.8);
    float innerRimAlpha = opticalRim * glassOpacity * 0.45;
    col = glsOver(col, shellInner, innerRimAlpha);

    vec2 coolDirection = normalize(vec2(0.84, 0.54));
    vec2 warmDirection = normalize(vec2(-0.62, -0.78));
    float coolSplit = glsHighlightLobe(normal, coolDirection, -0.32, 1.8);
    float warmSplit = glsHighlightLobe(normal, warmDirection, -0.28, 2.0);
    float dispersion = opticalRim * gloss * (0.8 + 0.8 * shellEdgeAlpha);

    col = glsOver(col, shellMid, dispersion * coolSplit);
    col = glsOver(col, shellEdge, dispersion * warmSplit);

    float edgeShadow = opticalRim * (0.015 + 0.15 * shellEdgeAlpha) *
                       (0.15 + 0.85 * max(dot(normal, vec2(0.45, -0.89)), 0.0));
    col *= (1.0 - edgeShadow);

    // Specular highlights
    vec2 keyDirection = normalize(vec2(-0.68, 0.73));
    vec2 fillDirection = normalize(vec2(0.74, -0.67));
    float key = opticalRim * glsHighlightLobe(normal, keyDirection, 0.2, 2.8) * sheen * 1.4;
    float fill = opticalRim * glsHighlightLobe(normal, fillDirection, 0.4, 3.6) * sheen * 1.0;

    col = glsOver(col, sheenColor, key);
    col = glsOver(col, specColor, fill);

    float ballA = 1.0 - smoothstep(0.985, 1.015, pd);
    col = clamp(col * max(exposure, 0.0), vec3(0.0), vec3(1.0)) * ballA;

    // Atmospheric outer rim glow
    float r = length(uv);
    float halo = (0.14 + progress * 0.25) * exp(-max(r - contourRad, 0.0) * 8.5);
    col += glowColor * halo;

    float finalAlpha = clamp(max(ballA, halo * 0.8), 0.0, 1.0);
    fragColor = vec4(col, finalAlpha);
}
