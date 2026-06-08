#include "Common/ConstantBuffers.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/SystemSamplers.hlsli"
#define USE_FOG 1
#include "Common/Fog.hlsli"

Texture2D ParticleTexture : register(t0);

// b2: 카메라 Right/Up (빌보드 확장용 — FFrameContext에서 매 프레임 업데이트)
// AlignMode: 0 = 카메라 빌보드(기본), 1 = 실린드리컬(월드 Z축 고정, Z 둘레만 카메라 지향)
cbuffer ParticleFrameBuffer : register(b2)
{
    float3 CameraRight;
    float _pad0;
    float3 CameraUp;
    float _pad1;
    float3 CameraPosition;
    float AlignMode;
}

struct PS_Input_Particle
{
    float4 position : SV_POSITION;
    float2 texcoord : TEXCOORD0;
    float4 color    : COLOR;
    float3 worldPos : TEXCOORD1;
};

PS_Input_Particle VS(VS_Input_ParticleQuad quad, VS_Input_ParticleInstance inst)
{
    float sinR = sin(inst.rotation);
    float cosR = cos(inst.rotation);

    float2 rotUV = float2(
        quad.cornerUV.x * cosR - quad.cornerUV.y * sinR,
        quad.cornerUV.x * sinR + quad.cornerUV.y * cosR
    );

    float3 axisRight = CameraRight;
    float3 axisUp    = CameraUp;
    if (AlignMode > 0.5f)
    {
        // 실린드리컬 — 세로축을 월드 Z에 고정하고 Z 둘레로만 카메라를 향한다 (빛기둥)
        axisUp = float3(0.0f, 0.0f, 1.0f);
        float3 toCam = CameraPosition - inst.position;
        toCam -= axisUp * dot(toCam, axisUp);
        if (dot(toCam, toCam) > 0.0001f)
        {
            axisRight = normalize(cross(axisUp, toCam));
        }
    }

    float3 worldPos = inst.position
                    + axisRight * rotUV.x * inst.size
                    + axisUp * rotUV.y * inst.size;

    PS_Input_Particle output;
    output.position = mul(float4(worldPos, 1.0f), mul(View, Projection));
    output.texcoord = quad.cornerUV + 0.5f;
    output.color    = inst.color;
    output.worldPos = worldPos;
    return output;
}

float4 PS(PS_Input_Particle input) : SV_TARGET
{
    float4 col = ParticleTexture.Sample(LinearClampSampler, input.texcoord);
    col *= input.color;
    clip(col.a - 0.01f);
    return ApplyFogTranslucent(col, input.worldPos, CameraWorldPos);
}