#ifndef RIM_LIGHT_HLSLI
#define RIM_LIGHT_HLSLI

#include "Common/ConstantBuffers.hlsli"
#include "Common/SystemSamplers.hlsli"

Texture2D HitRimNoiseTexture : register(t26);

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

float GetHalfLambert(float3 normal, float3 direction)
{
    float halfLambert = saturate(dot(normalize(normal), normalize(direction)) * 0.5f + 0.5f);
    return halfLambert * halfLambert;
}

float3 ComputeHitRim(float3 normal, float3 viewDir, float2 uv, float4 colorAndIntensity, float power)
{
    float intensity = max(colorAndIntensity.a, 0.0f);
    if (intensity <= 0.0001f)
    {
        return float3(0.0f, 0.0f, 0.0f);
    }

    float rimPower = max(power, 0.1f);
    float facing = GetHalfLambert(normal, viewDir);
    float rim = pow(saturate(1.0f - facing), rimPower);
    return colorAndIntensity.rgb * rim * intensity * GetHitRimNoiseFactor(uv);
}

float GetHitImpactNoiseFactor(float2 uv, float distanceFromCenter)
{
    float2 impactUV = uv * 7.0f + float2(Time * 1.35f, -Time * 0.55f);
    float noise = HitRimNoiseTexture.Sample(LinearWrapSampler, impactUV).r;
    float spark = smoothstep(0.30f, 0.82f, noise);
    float flicker = 0.90f + 0.10f * sin(Time * 70.0f + distanceFromCenter * 10.0f + noise * 6.283185f);
    return lerp(0.85f, 1.35f, spark) * flicker;
}

float3 ComputeHitImpactGlow(float3 worldPos, float2 uv, float4 colorAndIntensity, float4 centerAndRadius, float4 impactParams)
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

    return colorAndIntensity.rgb * glow * rimIntensity * impactIntensity * GetHitImpactNoiseFactor(uv, distanceFromCenter) * pulse;
}

#endif // RIM_LIGHT_HLSLI
