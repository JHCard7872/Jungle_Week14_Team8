#include "Common/Functions.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/SystemSamplers.hlsli"

Texture2D SkyTexture : register(t0);

PS_Input_Tex VS(VS_Input_PNCT input)
{
    PS_Input_Tex output;
    output.position = ApplyMVP(input.position);
    output.texcoord = input.texcoord;
    return output;
}

float4 PS(PS_Input_Tex input) : SV_TARGET
{
    float3 color = SkyTexture.Sample(LinearClampSampler, input.texcoord).rgb;
    return float4(color, 1.0f);
}
