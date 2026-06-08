#include "SkyPass.h"
#include "RenderPassRegistry.h"

#include "Render/Command/DrawCommandList.h"
#include "Render/Device/D3DDevice.h"
#include "Render/Resource/MeshBufferManager.h"
#include "Render/Resource/RenderResources.h"
#include "Render/Shader/ShaderManager.h"
#include "Render/Types/FrameContext.h"
#include "Render/Types/RenderConstants.h"
#include "Texture/Texture2D.h"

REGISTER_RENDER_PASS(FSkyPass)

namespace
{
	constexpr const char* SkyTexturePath = "Content/Data/SkySphere/Tycho.jpeg";
	constexpr float SkyHeightOffset = 50.0f;
}

FSkyPass::FSkyPass()
{
	PassType = ERenderPass::Sky;
	RenderState = { EDepthStencilState::DepthReadOnly, EBlendState::Opaque,
	                ERasterizerState::SolidFrontCull, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST, false };
}

FSkyPass::~FSkyPass()
{
	SkyPerObjectCB.Release();
}

bool FSkyPass::BeginPass(const FPassContext& Ctx)
{
	const FFrameContext& Frame = Ctx.Frame;
	if (Frame.bIsLightView || Frame.bIsOrtho)
	{
		return false;
	}

	if (!Frame.ViewportRTV || !Frame.ViewportDSV || Frame.ViewportWidth <= 0.0f || Frame.ViewportHeight <= 0.0f)
	{
		return false;
	}

	if (!EnsureResources(Ctx))
	{
		return false;
	}

	ID3D11DeviceContext* DC = Ctx.Device.GetDeviceContext();
	ID3D11RenderTargetView* RTV = Ctx.Cache.RTV;
	DC->OMSetRenderTargets(1, &RTV, Ctx.Cache.DSV);

	Ctx.Resources.SetDepthStencilState(Ctx.Device, RenderState.DepthStencil);
	Ctx.Resources.SetBlendState(Ctx.Device, RenderState.Blend);
	Ctx.Resources.SetRasterizerState(Ctx.Device, RenderState.Rasterizer);
	DC->IASetPrimitiveTopology(RenderState.Topology);

	Ctx.Cache.bForceAll = true;
	return true;
}

void FSkyPass::Execute(const FPassContext& Ctx)
{
	FShader* Shader = FShaderManager::Get().GetOrCreate(EShaderPath::SkySphere);
	if (!Shader || !Shader->IsValid() || !SkyTexture || !SkyTexture->IsLoaded())
	{
		return;
	}

	FMeshBuffer& MeshBuffer = FMeshBufferManager::Get().GetMeshBuffer(EMeshShape::SkySphere);
	if (!MeshBuffer.IsValid() || MeshBuffer.GetIndexBuffer().GetIndexCount() == 0)
	{
		return;
	}

	ID3D11DeviceContext* DC = Ctx.Device.GetDeviceContext();

	const float FarClip = Ctx.Frame.FarClip > 1.0f ? Ctx.Frame.FarClip : 1000.0f;
	const float SkyRadius = FarClip * 0.9f;
	const float SkyScale = SkyRadius * 2.0f;
	const FVector SkyCenter = Ctx.Frame.CameraPosition + FVector(0.0f, 0.0f, SkyHeightOffset);
	const FMatrix World =
		FMatrix::MakeScaleMatrix(FVector(SkyScale, SkyScale, SkyScale)) *
		FMatrix::MakeTranslationMatrix(SkyCenter);

	FPerObjectConstants PerObject = FPerObjectConstants::FromWorldMatrix(World);
	SkyPerObjectCB.Update(DC, &PerObject, sizeof(FPerObjectConstants));
	ID3D11Buffer* PerObjectBuffer = SkyPerObjectCB.GetBuffer();
	DC->VSSetConstantBuffers(ECBSlot::PerObject, 1, &PerObjectBuffer);

	Shader->Bind(DC);

	ID3D11ShaderResourceView* SkySRV = SkyTexture->GetSRV();
	DC->PSSetShaderResources((int)EMaterialTextureSlot::Diffuse, 1, &SkySRV);

	uint32 Offset = 0;
	ID3D11Buffer* VB = MeshBuffer.GetVertexBuffer().GetBuffer();
	uint32 Stride = MeshBuffer.GetVertexBuffer().GetStride();
	ID3D11Buffer* IB = MeshBuffer.GetIndexBuffer().GetBuffer();
	DC->IASetVertexBuffers(0, 1, &VB, &Stride, &Offset);
	DC->IASetIndexBuffer(IB, DXGI_FORMAT_R32_UINT, 0);
	DC->DrawIndexed(MeshBuffer.GetIndexBuffer().GetIndexCount(), 0, 0);

	ID3D11ShaderResourceView* NullSRV = nullptr;
	DC->PSSetShaderResources((int)EMaterialTextureSlot::Diffuse, 1, &NullSRV);

	Ctx.Cache.bForceAll = true;
}

void FSkyPass::EndPass(const FPassContext& Ctx)
{
	Ctx.Cache.bForceAll = true;
}

bool FSkyPass::EnsureResources(const FPassContext& Ctx)
{
	if (!SkyPerObjectCB.GetBuffer())
	{
		SkyPerObjectCB.Create(Ctx.Device.GetDevice(), sizeof(FPerObjectConstants), "SkyPerObjectCB");
	}

	if (!SkyPerObjectCB.GetBuffer())
	{
		return false;
	}

	if (!SkyTexture || !SkyTexture->IsLoaded())
	{
		SkyTexture = UTexture2D::LoadFromFile(SkyTexturePath, Ctx.Device.GetDevice(), ETextureColorSpace::SRGB);
	}

	return SkyTexture && SkyTexture->IsLoaded();
}
