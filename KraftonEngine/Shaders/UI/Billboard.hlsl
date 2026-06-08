#include "Common/Functions.hlsli"
#include "Common/VertexLayouts.hlsli"
#include "Common/SystemSamplers.hlsli"
#include "Common/RimLight.hlsli"

// 컬러 PNG/TGA 텍스처를 단일 quad에 그리는 빌보드 전용 셰이더.
// SubUV 와 다르게 R 채널이 아닌 알파 채널만으로 컷오프 판정한다.
Texture2D BillboardTex : register(t0);

struct PS_Input_Billboard
{
    float4 position : SV_POSITION;
    float2 texcoord : TEXCOORD0;
};

float ComputeBillboardUvNoiseRim(float2 uv, float alpha)
{
    float intensity = HitRimColorAndIntensity.a;
    if (intensity <= 0.0f)
        return 0.0f;

    float2 centered = abs(uv * 2.0f - 1.0f);
    float edgeDistance = 1.0f - max(centered.x, centered.y);
    float edgeMask = 1.0f - smoothstep(0.015f, 0.27f, edgeDistance);
    float alphaMask = smoothstep(0.45f, 0.75f, alpha);

    float density = max(HitRimParams.z, 1.0f);
    float speed = max(abs(HitRimParams.w), 0.01f);
    float2 scrollA = float2(Time * speed * 0.23f, -Time * speed * 0.34f);
    float2 scrollB = float2(-Time * speed * 0.41f, Time * speed * 0.29f);
    float2 scrollC = float2(Time * speed * 0.07f, Time * speed * 0.62f);
    float broadNoise = HitRimNoiseTexture.Sample(LinearWrapSampler, uv * density * 0.18f + scrollA).r;
    float detailNoise = HitRimNoiseTexture.Sample(LinearWrapSampler, (uv.yx + float2(0.13f, 0.37f)) * density * 0.47f + scrollB).r;
    float veinNoise = HitRimNoiseTexture.Sample(LinearWrapSampler, (uv + float2(uv.y, -uv.x) * 0.35f) * density * 0.32f + scrollC).r;
    float noise = saturate(broadNoise * 0.75f + detailNoise * 0.55f);

    float bolt = smoothstep(0.50f, 0.88f, noise);
    float vein = smoothstep(0.64f, 0.94f, veinNoise);
    float flow = 0.5f + 0.5f * sin((uv.y + uv.x * 0.37f) * density * 2.7f - Time * speed * 6.28318f);
    float shimmer = 0.78f + 0.22f * sin(Time * speed * 12.0f + detailNoise * 6.28318f);
    float flowGate = smoothstep(0.35f, 1.0f, flow);
    float edgeGlow = edgeMask * (0.80f + bolt * 1.35f + vein * flowGate * 0.85f);
    float bodyNoise = smoothstep(0.70f, 0.97f, saturate(detailNoise * 0.72f + veinNoise * 0.62f));
    return alphaMask * (edgeGlow + bodyNoise * 0.22f) * shimmer;
}

PS_Input_Billboard VS(VS_Input_PNCT input)
{
    PS_Input_Billboard output;
    output.position = ApplyMVP(input.position);
    output.texcoord = input.texcoord;
    return output;
}

float4 PS(PS_Input_Billboard input) : SV_TARGET
{
    float4 col = BillboardTex.Sample(LinearClampSampler, input.texcoord);

    // 알파 컷오프 (straight alpha PNG의 보간 헤일로 차단)
    if (!bIsWireframe && col.a < 0.5f)
        discard;

    float rim = ComputeBillboardUvNoiseRim(input.texcoord, col.a);
    float3 rimColor = HitRimColorAndIntensity.rgb * HitRimColorAndIntensity.a * rim * 1.85f;
    return float4(ApplyWireframe(col.rgb + rimColor), bIsWireframe ? 1.0f : col.a);
}
