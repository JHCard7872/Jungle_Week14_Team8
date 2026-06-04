#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"

Texture2D<float4> SourceTexture : register(t0);

cbuffer BloomCB : register(b2)
{
    float Threshold;
    float SoftKnee;
    float2 SourceTexelSize;
};

PS_Input_UV VS(uint vertexID : SV_VertexID)
{
    return FullscreenTriangleVS(vertexID);
}

float3 ApplyBloomThreshold(float3 color)
{
    float brightness = max(color.r, max(color.g, color.b));
    float knee = max(Threshold * SoftKnee, 0.0001f);
    float soft = brightness - Threshold + knee;
    soft = saturate(soft / (2.0f * knee)) * soft;
    float contribution = max(soft, brightness - Threshold);
    contribution /= max(brightness, 0.0001f);
    return color * contribution;
}

float4 PS(PS_Input_UV input) : SV_TARGET
{
    float2 uv = input.uv;
    float2 diagonal = SourceTexelSize;

    float3 bloom = ApplyBloomThreshold(SourceTexture.SampleLevel(LinearClampSampler, uv, 0).rgb) * 4.0f;
    bloom += ApplyBloomThreshold(SourceTexture.SampleLevel(LinearClampSampler, uv + float2(-diagonal.x, -diagonal.y), 0).rgb);
    bloom += ApplyBloomThreshold(SourceTexture.SampleLevel(LinearClampSampler, uv + float2( diagonal.x, -diagonal.y), 0).rgb);
    bloom += ApplyBloomThreshold(SourceTexture.SampleLevel(LinearClampSampler, uv + float2(-diagonal.x,  diagonal.y), 0).rgb);
    bloom += ApplyBloomThreshold(SourceTexture.SampleLevel(LinearClampSampler, uv + float2( diagonal.x,  diagonal.y), 0).rgb);

    return float4(bloom * 0.125f, 1.0f);
}
