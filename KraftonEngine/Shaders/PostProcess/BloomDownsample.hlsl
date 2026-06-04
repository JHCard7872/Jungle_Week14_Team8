#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"

Texture2D<float4> SourceTexture : register(t0);

cbuffer BloomCB : register(b2)
{
    float2 SourceTexelSize;
    float2 Pad;
};

PS_Input_UV VS(uint vertexID : SV_VertexID)
{
    return FullscreenTriangleVS(vertexID);
}

float4 PS(PS_Input_UV input) : SV_TARGET
{
    float2 uv = input.uv;
    float2 t = SourceTexelSize;

    float3 color = SourceTexture.SampleLevel(LinearClampSampler, uv, 0).rgb * 4.0f;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv + float2(-t.x, -t.y), 0).rgb;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv + float2( t.x, -t.y), 0).rgb;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv + float2(-t.x,  t.y), 0).rgb;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv + float2( t.x,  t.y), 0).rgb;

    return float4(color * 0.125f, 1.0f);
}
