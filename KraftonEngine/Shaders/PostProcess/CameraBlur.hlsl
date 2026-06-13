// CameraBlur.hlsl — 풀스크린 가우시안 근사 블러.
// EarlyPostProcess 패스가 SceneColor 복사본(t17)을 t17에 바인딩한 뒤 풀스크린 트라이앵글로 그린다.
// Strength(0..1)로 커널 반경을 스케일한다. 결과는 불투명(Opaque)으로 RT에 덮어쓴다.
#include "Common/Functions.hlsli"
#include "Common/SystemResources.hlsli"   // SceneColorTexture : register(t17)
#include "Common/SystemSamplers.hlsli"    // LinearClampSampler : register(s0)

cbuffer CameraBlurCB : register(b2)
{
    float Strength;
    float TexelSizeX;
    float TexelSizeY;
    float _Pad;
};

PS_Input_UV VS(uint vertexID : SV_VertexID)
{
    return FullscreenTriangleVS(vertexID);
}

float4 PS(PS_Input_UV input) : SV_Target
{
    float2 texel = float2(TexelSizeX, TexelSizeY);
    // 최대 반경 6텍셀까지 강도에 비례. 강도 0이면 step=0이라 원본과 동일.
    float radius = saturate(Strength) * 6.0f;
    float2 stepUV = texel * radius;

    // 13탭: 중심 + 십자(±1) + 대각(±1) + 십자(±2). 가중치 합 = 1.
    const float2 offs[13] =
    {
        float2( 0,  0),
        float2( 1,  0), float2(-1,  0), float2( 0,  1), float2( 0, -1),
        float2( 1,  1), float2(-1,  1), float2( 1, -1), float2(-1, -1),
        float2( 2,  0), float2(-2,  0), float2( 0,  2), float2( 0, -2)
    };
    const float w[13] =
    {
        0.196f,
        0.118f, 0.118f, 0.118f, 0.118f,
        0.045f, 0.045f, 0.045f, 0.045f,
        0.0125f, 0.0125f, 0.0125f, 0.0125f
    };

    float4 acc = 0.0f;
    [unroll] for (int i = 0; i < 13; ++i)
    {
        acc += SceneColorTexture.SampleLevel(LinearClampSampler, input.uv + offs[i] * stepUV, 0) * w[i];
    }

    return float4(acc.rgb, 1.0f);
}
