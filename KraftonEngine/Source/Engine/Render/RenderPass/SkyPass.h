#pragma once

#include "Render/RenderPass/RenderPassBase.h"
#include "Render/Resource/Buffer.h"

class UTexture2D;

class FSkyPass final : public FRenderPassBase
{
public:
	FSkyPass();
	~FSkyPass() override;

	bool BeginPass(const FPassContext& Ctx) override;
	void Execute(const FPassContext& Ctx) override;
	void EndPass(const FPassContext& Ctx) override;

private:
	bool EnsureResources(const FPassContext& Ctx);

	UTexture2D* SkyTexture = nullptr;
	FConstantBuffer SkyPerObjectCB;
};
