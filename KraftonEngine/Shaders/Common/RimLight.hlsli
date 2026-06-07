#ifndef RIM_LIGHT_HLSLI
#define RIM_LIGHT_HLSLI

#include "Common/ConstantBuffers.hlsli"
#include "Common/SystemSamplers.hlsli"

Texture2D HitRimNoiseTexture : register(t26);

static const float HitRimHdrBoost = 2.0;
static const float HitRimFlickerMin = 0.06f;
static const float HitRimFlickerMax = 1.95f;
static const float HitRimFlickerHz = 7.0f;
static const float HitRimFlickerDuty = 1.2f;
static const float HitRimFlickerSoftness = 0.045f;
static const float HitRimBodyGlow = 0.20f;
static const float HitRimBodyFlickerInfluence = 0.55f;
static const float HitRimHologramLineWidth = 0.10f;
static const float HitRimHologramLineSoftness = 0.08f;
static const float HitRimHologramTravelGradientDensity = 0.75f;
static const float HitRimHologramTravelGradientSpeedScale = 0.22f;
static const float HitRimHologramTravelGradientPower = 1.35f;
static const float HitRimHologramTravelGradientMin = 0.05f;
static const float HitRimHologramWorldPosScale = 0.5f;
static const float HitRimHologramWorldPosOffset = 0.5f;
static const float HitRimHologramBlinking = 3.0f;
static const float HitRimHologramHdrBoost = 0.55f;

float GetAbsSinPulse(float phase)
{
    return abs(sin(Time + phase));
}

float GetHitRimNoiseFactor(float2 uv)
{
    float2 fastUV = uv * 3.0f + float2(Time * 0.35f, Time * 1.40f);
    float2 detailUV = uv * 8.0f + float2(-Time * 1.20f, Time * 2.70f);

    float broad = HitRimNoiseTexture.Sample(LinearWrapSampler, fastUV).r;
    float detail = HitRimNoiseTexture.Sample(LinearWrapSampler, detailUV).r;

    float broadStrike = smoothstep(0.42f, 0.86f, broad);
    float detailStrike = smoothstep(0.66f, 0.98f, detail);
    float lightningMask = saturate(broadStrike + detailStrike * 0.55f);
    float flicker = 0.88f + 0.12f * sin(Time * 48.0f + detail * 6.283185f);

    return lerp(0.65f, 1.55f, lightningMask) * flicker;
}

float3 SafeNormalizeHitRim(float3 value, float3 fallback)
{
    float lengthSq = dot(value, value);
    return lengthSq > 1.0e-6f ? value * rsqrt(lengthSq) : fallback;
}

float3 GetHitRimObjectCenter()
{
    return float3(Model._41, Model._42, Model._43);
}

float GetHitRimWorldLightningFactor(float3 worldPos, float3 fakeNormal)
{
    float3 normalWeight = abs(fakeNormal);
    normalWeight /= max(normalWeight.x + normalWeight.y + normalWeight.z, 0.001f);

    float3 noisePos = worldPos * 0.055f;
    float2 scrollA = float2(Time * 0.32f, Time * 1.10f);
    float2 scrollB = float2(-Time * 1.15f, Time * 0.46f);

    float broadX = HitRimNoiseTexture.Sample(LinearWrapSampler, noisePos.yz + scrollA).r;
    float broadY = HitRimNoiseTexture.Sample(LinearWrapSampler, noisePos.xz + scrollA * 0.83f).r;
    float broadZ = HitRimNoiseTexture.Sample(LinearWrapSampler, noisePos.xy + scrollA * 1.17f).r;
    float broad = dot(float3(broadX, broadY, broadZ), normalWeight);

    float detailX = HitRimNoiseTexture.Sample(LinearWrapSampler, noisePos.yz * 3.5f + scrollB).r;
    float detailY = HitRimNoiseTexture.Sample(LinearWrapSampler, noisePos.xz * 3.5f + scrollB * 1.21f).r;
    float detailZ = HitRimNoiseTexture.Sample(LinearWrapSampler, noisePos.xy * 3.5f + scrollB * 0.74f).r;
    float detail = dot(float3(detailX, detailY, detailZ), normalWeight);

    float lightningMask = saturate(smoothstep(0.60f, 0.88f, broad) + smoothstep(0.72f, 0.97f, detail) * 0.85f);
    float flicker = 0.82f + 0.18f * sin(Time * 58.0f + detail * 6.283185f);

    return lerp(0.12f, 1.75f, lightningMask) * flicker;
}

float GetHitRimWorldScanLineFactor(float3 worldPos, float3 fakeNormal, float lineDensity, float scrollSpeed)
{
    float density = max(lineDensity, 0.001f);
    float speed = max(scrollSpeed, 0.0f);
    float phase = frac(worldPos.z * density - Time * speed);
    float lineDistance = min(phase, 1.0f - phase);
    float holo = 1.0f - smoothstep(HitRimHologramLineWidth, HitRimHologramLineWidth + HitRimHologramLineSoftness, lineDistance);
    float secWorldPos = pow(saturate(worldPos.z * HitRimHologramWorldPosScale + HitRimHologramWorldPosOffset), 1.2f);
    float blink = abs(sin(Time * HitRimHologramBlinking));
    float normalBias = 0.86f + 0.14f * saturate(dot(abs(fakeNormal), float3(0.22f, 0.22f, 0.56f)));

    return holo * lerp(0.86f, 1.0f, blink) * lerp(0.72f, 1.0f, secWorldPos) * normalBias;
}

float GetHitRimWorldTravelGradientFactor(float3 worldPos, float3 fakeNormal, float scrollSpeed)
{
    float speed = max(scrollSpeed, 0.0f);
    float relativeHeight = worldPos.z - GetHitRimObjectCenter().z;
    float phase = frac(relativeHeight * HitRimHologramTravelGradientDensity - Time * speed * HitRimHologramTravelGradientSpeedScale);
    float gradient = pow(saturate(1.0f - phase), HitRimHologramTravelGradientPower);
    float normalBias = 0.90f + 0.10f * saturate(dot(abs(fakeNormal), float3(0.22f, 0.22f, 0.56f)));

    return lerp(HitRimHologramTravelGradientMin, 1.0f, gradient) * normalBias;
}

float GetHitRimFlickerFactor(float3 fakeNormal)
{
    float objectPhase = frac(dot(GetHitRimObjectCenter(), float3(0.031f, 0.047f, 0.059f)));
    float phase = frac(Time * HitRimFlickerHz + objectPhase);
    float softness = max(HitRimFlickerSoftness, 0.001f);
    float duty = clamp(HitRimFlickerDuty, softness * 2.0f, 0.95f);
    float onRamp = smoothstep(0.0f, softness, phase);
    float offRamp = 1.0f - smoothstep(duty - softness, duty, phase);
    float strobeGate = onRamp * offRamp;

    float faceBias = 0.92f + 0.08f * saturate(dot(abs(fakeNormal), float3(0.37f, 0.29f, 0.34f)));
    return lerp(HitRimFlickerMin, HitRimFlickerMax, strobeGate) * faceBias;
}

float GetHalfLambert(float3 normal, float3 direction)
{
    float halfLambert = saturate(dot(normalize(normal), normalize(direction)) * 0.5f + 0.5f);
    return halfLambert * halfLambert;
}

float3 ComputeHitRim(float3 normal, float3 viewDir, float3 worldPos, float2 uv, float4 colorAndIntensity, float4 rimParams)
{
    float intensity = max(colorAndIntensity.a, 0.0f);
    if (intensity <= 0.0001f)
    {
        return float3(0.0f, 0.0f, 0.0f);
    }

    float rimPower = max(rimParams.x, 0.1f);
    float effectStyle = rimParams.y;
    float3 safeViewDir = SafeNormalizeHitRim(viewDir, float3(0.0f, 0.0f, 1.0f));
    float3 safeNormal = SafeNormalizeHitRim(normal, safeViewDir);
    float3 fakeNormal = SafeNormalizeHitRim(worldPos - GetHitRimObjectCenter(), safeNormal);

    float surfaceFacing = GetHalfLambert(safeNormal, safeViewDir);
    float surfaceRim = pow(saturate(1.0f - surfaceFacing), rimPower);
    float fakeRim = pow(saturate(1.0f - saturate(dot(fakeNormal, safeViewDir))), rimPower);
    float rim = saturate(max(surfaceRim * 0.72f, fakeRim));

    if (effectStyle >= 0.5f)
    {
        float scan = GetHitRimWorldScanLineFactor(worldPos, fakeNormal, rimParams.z, rimParams.w);
        float travelGradient = GetHitRimWorldTravelGradientFactor(worldPos, fakeNormal, rimParams.w);
        float flicker = lerp(1.0f, GetHitRimFlickerFactor(fakeNormal), 0.22f);
        float baseGlow = 0.22f + rim * 0.46f;
        float scanGlow = scan * (0.22f + rim * 0.34f) + travelGradient * (0.18f + rim * 0.28f);
        float glow = baseGlow + scanGlow;
        return colorAndIntensity.rgb * glow * intensity * flicker * HitRimHologramHdrBoost;
    }

    float lightning = GetHitRimWorldLightningFactor(worldPos, fakeNormal);
    float flicker = GetHitRimFlickerFactor(fakeNormal);
    float stableFlicker = lerp(1.0f, flicker, HitRimBodyFlickerInfluence);
    float glow = HitRimBodyGlow + rim * lightning;
    return colorAndIntensity.rgb * glow * intensity * stableFlicker * HitRimHdrBoost;
}

float GetHitImpactNoiseFactor(float2 uv, float distanceFromCenter)
{
    float2 impactUV = uv * 7.0f + float2(Time * 1.35f, -Time * 0.55f);
    float noise = HitRimNoiseTexture.Sample(LinearWrapSampler, impactUV).r;
    float spark = smoothstep(0.30f, 0.82f, noise);
    float flicker = 0.90f + 0.10f * sin(Time * 70.0f + distanceFromCenter * 10.0f + noise * 6.283185f);
    return lerp(0.85f, 1.35f, spark) * flicker;
}

float3 ComputeHitImpactGlow(float3 worldPos, float2 uv, float4 colorAndIntensity, float4 centerAndRadius, float4 impactParams, float4 rimParams)
{
    float rimIntensity = max(colorAndIntensity.a, 0.0f);
    float radius = max(centerAndRadius.w, 0.0f);
    float coreRadius = max(impactParams.x, 0.001f);
    float impactIntensity = max(impactParams.y, 0.0f);
    float enabled = impactParams.w;

    if (enabled <= 0.5f || rimIntensity <= 0.0001f || radius <= 0.0001f || impactIntensity <= 0.0001f)
    {
        return float3(0.0f, 0.0f, 0.0f);
    }

    float distanceFromCenter = distance(worldPos, centerAndRadius.xyz);
    float outerRadius = max(radius, coreRadius + 0.001f);
    float halo = 1.0f - smoothstep(coreRadius, outerRadius, distanceFromCenter);
    float hotCore = 1.0f - smoothstep(0.0f, coreRadius, distanceFromCenter);
    float glow = saturate(halo * 0.78f + hotCore * 1.35f);
    float pulse = GetAbsSinPulse(distanceFromCenter * 2.0f);
    float effectFactor = GetHitImpactNoiseFactor(uv, distanceFromCenter);

    if (rimParams.y >= 0.5f)
    {
        float3 impactNormal = SafeNormalizeHitRim(worldPos - centerAndRadius.xyz, float3(0.0f, 0.0f, 1.0f));
        float scan = GetHitRimWorldScanLineFactor(worldPos, impactNormal, rimParams.z, rimParams.w);
        float travelGradient = GetHitRimWorldTravelGradientFactor(worldPos, impactNormal, rimParams.w);
        effectFactor = lerp(0.45f, 1.0f, saturate(scan * 0.65f + travelGradient * 0.75f));
    }

    return colorAndIntensity.rgb * glow * rimIntensity * impactIntensity * effectFactor * pulse;
}

#endif // RIM_LIGHT_HLSLI
