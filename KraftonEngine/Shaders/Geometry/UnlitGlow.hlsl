// =============================================================================
// UnlitGlow.hlsl — 가산(Additive) 발광 지오메트리 전용 무조명 셰이더
// 텍스처 RGB × Tint를 그대로 출력한다. 라이팅/스펙큘러/알파 분기 없음 —
// Additive 블렌드에서 텍스처의 검은 배경은 아무것도 더하지 않는다.
// (소환진 빛기둥 등 FX 메시용. 머티리얼에서 BlendState=Additive와 함께 사용)
// =============================================================================
#include "Common/Functions.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/SystemSamplers.hlsli"

Texture2D DiffuseTexture : register(t0);

cbuffer PerShader1 : register(b2)
{
    float4 Tint;
};

struct UnlitGlowVS_Output
{
    float4 position : SV_POSITION;
    float2 texcoord : TEXCOORD0;
};

UnlitGlowVS_Output VS(VS_Input_PNCTT input)
{
    UnlitGlowVS_Output output;
    output.position = ApplyMVP(input.position);
    output.texcoord = input.texcoord;
    return output;
}

float4 PS(UnlitGlowVS_Output input) : SV_TARGET
{
    float4 texColor = DiffuseTexture.Sample(LinearClampSampler, input.texcoord);
    return float4(texColor.rgb * Tint.rgb, texColor.a * Tint.a);
}
