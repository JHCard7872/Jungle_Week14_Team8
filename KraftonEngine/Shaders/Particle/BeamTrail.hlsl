#include "Common/ConstantBuffers.hlsli"
#include "Common/SystemSamplers.hlsli"

Texture2D BeamTrailTexture : register(t0);

cbuffer PerMaterial : register(b2)
{
    float4 SectionColor;
    float EmissiveStrength;
    float EffectMode;
    float ScanSpeed;
    float ScanWidth;
    float ScanSoftness;
    float ScanTrailStrength;
    float FlickerStrength;
    float LightningScrollSpeed;
};

struct VS_Input_BeamTrail
{
    float3 position : POSITION;
    float relativeTime : RELATIVE_TIME;
    float3 oldPosition : OLD_POSITION;
    float particleId : PARTICLE_ID;
    float2 size : SIZE;
    float rotation : ROTATION;
    float subImageIndex : SUBIMAGE_INDEX;
    float4 color : COLOR;
    float2 texcoord : TEXCOORD0;
    float2 texcoord2 : TEXCOORD1;
};

struct PS_Input_BeamTrail
{
    float4 position : SV_POSITION;
    float2 texcoord : TEXCOORD0;
    float4 color : COLOR;
};

PS_Input_BeamTrail VS(VS_Input_BeamTrail input)
{
    PS_Input_BeamTrail output;
    output.position = mul(float4(input.position, 1.0f), mul(View, Projection));
    output.texcoord = input.texcoord;
    output.color = input.color;
    return output;
}

float4 PS(PS_Input_BeamTrail input) : SV_TARGET
{
    float2 uv = input.texcoord;
    float2 lightningUV = float2(frac(uv.x + Time * LightningScrollSpeed), uv.y);
    float4 tex = BeamTrailTexture.Sample(LinearClampSampler, lightningUV);
    float flicker = lerp(1.0f, 0.82f + 0.18f * sin(Time * 72.0f + uv.x * 18.0f), saturate(FlickerStrength));
    float4 col = tex * input.color * SectionColor;

    if (EffectMode > 0.5f)
    {
        float phase = frac(Time * max(ScanSpeed, 0.0f));
        float forwardDist = frac(uv.x - phase + 1.0f);
        float head = 1.0f - smoothstep(max(ScanWidth, 0.001f), max(ScanWidth + ScanSoftness, 0.001f), forwardDist);
        float tail = saturate(1.0f - forwardDist / max(ScanWidth + ScanSoftness * 5.0f, 0.001f));
        float scanMask = saturate(head + tail * ScanTrailStrength);
        float widthMask = 1.0f - smoothstep(0.42f, 0.5f, abs(uv.y - 0.5f));
        col.a *= saturate(scanMask * widthMask + 0.08f);
        col.rgb *= lerp(0.35f, 1.75f, scanMask);
    }

    col.rgb *= max(EmissiveStrength, 0.0f) * flicker;
    clip(col.a - 0.01f);
    return col;
}
