#include "Render/Proxy/BillboardSceneProxy.h"
#include "Component/Primitive/BillboardComponent.h"
#include "Render/Resource/MeshBufferManager.h"
#include "Render/Types/FrameContext.h"
#include "GameFramework/AActor.h"
#include "Materials/Material.h"
#include "Texture/Texture2D.h"
#include "Object/Object.h"
#include "Math/MathUtils.h"

// ============================================================
// FBillboardSceneProxy
// ============================================================
FBillboardSceneProxy::FBillboardSceneProxy(UBillboardComponent* InComponent)
	: FPrimitiveSceneProxy(InComponent)
{
	ProxyFlags |= EPrimitiveProxyFlags::PerViewportUpdate;
	ProxyFlags &= ~EPrimitiveProxyFlags::ShowAABB;

	if (IsValid(InComponent) && InComponent->IsEditorOnly())
		ProxyFlags |= EPrimitiveProxyFlags::EditorOnly;
}

UBillboardComponent* FBillboardSceneProxy::GetBillboardComponent() const
{
	return Cast<UBillboardComponent>(GetOwner());
}

// ============================================================
// UpdateTransform — Scale/Location 캐싱
// ============================================================
void FBillboardSceneProxy::UpdateTransform()
{
	FPrimitiveSceneProxy::UpdateTransform();
	UBillboardComponent* Comp = GetBillboardComponent();
	if (!IsValid(Comp))
	{
		bVisible = false;
		CachedScale = FVector(1, 1, 1);
		CachedLocation = FVector(0, 0, 0);
		CachedRollDegrees = 0.0f;
		return;
	}

	CachedScale = Comp->GetWorldScale();
	CachedLocation = Comp->GetWorldLocation();
	CachedRollDegrees = Comp->GetBillboardRollDegrees();
}

// ============================================================
// UpdateMesh — TexturedQuad + Material shader/states
// ============================================================
void FBillboardSceneProxy::UpdateMesh()
{
	UBillboardComponent* Comp = GetBillboardComponent();
	UMaterial* Mat = IsValid(Comp) ? Comp->GetMaterial() : nullptr;

	if (Mat)
	{
		// TexturedQuad (FVertexPNCT with UVs)
		MeshBuffer = &FMeshBufferManager::Get().GetMeshBuffer(EMeshShape::TexturedQuad);

		// SectionDraws 단일 항목 — Material의 CachedSRVs로 텍스처 바인딩
		const uint32 IndexCount = MeshBuffer->GetIndexBuffer().GetIndexCount();
		SectionDraws.clear();
		SectionDraws.push_back({ Mat, 0, IndexCount });
	}
	else
	{
		UPrimitiveComponent* OwnerComp = GetOwner();
		MeshBuffer = IsValid(OwnerComp) ? OwnerComp->GetMeshBuffer() : nullptr;
		SectionDraws.clear();
	}
}

// ============================================================
// UpdatePerViewport — 뷰포트 카메라 기반 빌보드 행렬 갱신
// ============================================================
void FBillboardSceneProxy::UpdatePerViewport(const FFrameContext& Frame)
{
	if (!bVisible) return;

	// Frame 카메라 벡터로 per-view 빌보드 행렬 계산.
	// Forward 축은 카메라 facing을 유지하고, Right/Up 축만 Forward 축 기준 Roll만큼 회전한다.
	const float RollRadians = CachedRollDegrees * FMath::DegToRad;
	const float RollCos = std::cos(RollRadians);
	const float RollSin = std::sin(RollRadians);

	FVector BillboardForward = (Frame.CameraForward * -1.0f).Normalized();
	FVector BillboardRight = (Frame.CameraRight * RollCos + Frame.CameraUp * RollSin).Normalized();
	FVector BillboardUp = (Frame.CameraUp * RollCos - Frame.CameraRight * RollSin).Normalized();

	FMatrix RotMatrix;
	RotMatrix.SetAxes(BillboardForward, BillboardRight, BillboardUp);
	FMatrix BillboardMatrix = FMatrix::MakeScaleMatrix(CachedScale)
		* RotMatrix * FMatrix::MakeTranslationMatrix(CachedLocation);

	PerObjectConstants = FPerObjectConstants::FromWorldMatrix(BillboardMatrix);
	MarkPerObjectCBDirty();
}
