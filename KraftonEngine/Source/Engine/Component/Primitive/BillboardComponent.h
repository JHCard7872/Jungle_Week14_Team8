#pragma once
#include "Component/PrimitiveComponent.h"
#include "Render/Resource/MeshBufferManager.h"
#include "Core/Types/ResourceTypes.h"
#include "Object/FName.h"
#include "Object/Ptr/SoftObjectPtr.h"
#include "Object/Ptr/ObjectPtr.h"
#include "Materials/Material.h"

#include "Source/Engine/Component/Primitive/BillboardComponent.generated.h"

class FPrimitiveSceneProxy;

UCLASS()
class UBillboardComponent : public UPrimitiveComponent
{
public:
	GENERATED_BODY()

	void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction& ThisTickFunction) override;
	FPrimitiveSceneProxy* CreateSceneProxy() override;

	void PostDuplicate() override;

	void PostEditProperty(const char* PropertyName) override;

	bool LineTraceComponent(const FRay& Ray, FHitResult& OutHitResult) override;

	void SetBillboardEnabled(bool bEnable) { bIsBillboard = bEnable; }

	// 화면 평면 기준 Roll 회전입니다.
	// 빌보드가 카메라를 바라보는 축은 유지하고, Right/Up 축만 Forward 축 기준으로 회전합니다.
	void SetBillboardRollDegrees(float InDegrees);
	float GetBillboardRollDegrees() const { return BillboardRollDegrees; }

	// Per-object tint/opacity입니다. 셰이더가 PerObject.Color를 사용하면 alpha fade까지 적용됩니다.
	void SetBillboardTintColor(const FVector4& InColor);
	const FVector4& GetBillboardTintColor() const { return BillboardTintColor; }
	void SetBillboardOpacity(float InOpacity);
	float GetBillboardOpacity() const { return BillboardTintColor.W; }

	// --- Material ---
	void SetMaterial(class UMaterial* InMaterial);
	class UMaterial* GetMaterial() const { return Material.Get(); }

	void AddReferencedObjects(FReferenceCollector& Collector) override;

	// 주어진 카메라 방향으로 빌보드 월드 행렬을 계산 (per-view 렌더링용)
	FMatrix ComputeBillboardMatrix(const FVector& CameraForward) const;

	FMeshBuffer* GetMeshBuffer() const override { return &FMeshBufferManager::Get().GetMeshBuffer(EMeshShape::Quad); }
	FMeshDataView GetMeshDataView() const override { return FMeshDataView::FromMeshData(FMeshBufferManager::Get().GetMeshData(EMeshShape::Quad)); }

protected:
	UPROPERTY(Edit, Save, Category="Rendering", DisplayName="Billboard")
	bool bIsBillboard = true;

	UPROPERTY(Edit, Save, Category="Rendering", DisplayName="Billboard Roll Degrees")
	float BillboardRollDegrees = 0.0f;

	UPROPERTY(Edit, Save, Category="Rendering", DisplayName="Billboard Tint Color")
	FVector4 BillboardTintColor = FVector4(1.0f, 1.0f, 1.0f, 1.0f);

	UPROPERTY(Edit, Save, Category="Rendering", DisplayName="Material", AssetType="Material")
	FSoftObjectPtr MaterialSlot = "None";
	// Runtime loaded material reference. MaterialSlot is the persistent asset identity.
	UPROPERTY(Transient, Category="Rendering")
	TObjectPtr<UMaterial> Material = nullptr;
};
