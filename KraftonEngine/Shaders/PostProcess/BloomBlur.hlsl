#include "Common/Functions.hlsli"
#include "Common/SystemSamplers.hlsli"

Texture2D<float4> SourceTexture : register(t0);

cbuffer BloomCB : register(b2)
{
    float2 SourceTexelSize;
    float2 Direction;
    float Radius;
    float3 Pad;
};

PS_Input_UV VS(uint vertexID : SV_VertexID)
{
    return FullscreenTriangleVS(vertexID);
}

float4 PS(PS_Input_UV input) : SV_TARGET
{
    float2 stepUV = Direction * SourceTexelSize * max(Radius, 0.001f);
    float2 uv = input.uv;

    float3 color = SourceTexture.SampleLevel(LinearClampSampler, uv, 0).rgb * 0.227027f;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv + stepUV * 1.0f, 0).rgb * 0.1945946f;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv - stepUV * 1.0f, 0).rgb * 0.1945946f;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv + stepUV * 2.0f, 0).rgb * 0.1216216f;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv - stepUV * 2.0f, 0).rgb * 0.1216216f;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv + stepUV * 3.0f, 0).rgb * 0.054054f;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv - stepUV * 3.0f, 0).rgb * 0.054054f;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv + stepUV * 4.0f, 0).rgb * 0.016216f;
    color += SourceTexture.SampleLevel(LinearClampSampler, uv - stepUV * 4.0f, 0).rgb * 0.016216f;

    return float4(color, 1.0f);
}
