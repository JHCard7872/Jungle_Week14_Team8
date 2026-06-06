#include "Render/Proxy/ShapeSceneProxy.h"

#include "Component/ShapeComponent.h"
#include "Component/Shape/BoxComponent.h"
#include "Component/Shape/SphereComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "Math/MathUtils.h"
#include "Render/Geometry/CollisionDebugGeometry.h"
#include "Object/Object.h"

FShapeSceneProxy::FShapeSceneProxy(UShapeComponent* InComponent)
	: FPrimitiveSceneProxy(InComponent)
{
	ProxyFlags = EPrimitiveProxyFlags::EditorOnly
	           | EPrimitiveProxyFlags::NeverCull
	           | EPrimitiveProxyFlags::WireShape;

	bDrawOnlyIfSelected = InComponent->IsDrawOnlyIfSelected();
	WireColor = InComponent->GetShapeColorVec4();

	bCastShadow = false;
	bCastShadowAsTwoSided = false;

	RebuildLines();
}

void FShapeSceneProxy::UpdateTransform()
{
	FPrimitiveSceneProxy::UpdateTransform();
	RebuildLines();
}

void FShapeSceneProxy::UpdateVisibility()
{
	FPrimitiveSceneProxy::UpdateVisibility();

	if (bVisible && bDrawOnlyIfSelected)
	{
		bVisible = IsSelected();
	}
}

void FShapeSceneProxy::RebuildLines()
{
	CachedLines.clear();

	UPrimitiveComponent* OwnerComp = GetOwner();
	if (!IsValid(OwnerComp))
	{
		return;
	}

	// 비균등 스케일이 포함된 월드 행렬에서 ToQuat을 바로 부르면 회전이 왜곡된다
	// (행 길이가 달라 정규화 안 된 회전 추출). 물리 바디 동기화(BodyInstance)와
	// 동일하게 스케일을 제거한 뒤 회전을 뽑는다.
	const FQuat WorldRot = FTransform::FromMatrixWithScale(OwnerComp->GetWorldMatrix()).Rotation;

	if (const UBoxComponent* Box = Cast<UBoxComponent>(OwnerComp))
	{
		const FTransform WorldTM(Box->GetWorldLocation(), WorldRot, FVector::OneVector);
		FCollisionDebugGeometry::AddWireBox(
			CachedLines,
			WorldTM,
			Box->GetScaledBoxExtent());
	}
	else if (const USphereComponent* Sphere = Cast<USphereComponent>(OwnerComp))
	{
		FCollisionDebugGeometry::AddWireSphere(
			CachedLines,
			Sphere->GetWorldLocation(),
			Sphere->GetScaledSphereRadius());
	}
	else if (const UCapsuleComponent* Capsule = Cast<UCapsuleComponent>(OwnerComp))
	{
		const FTransform WorldTM(Capsule->GetWorldLocation(), WorldRot, FVector::OneVector);
		const float Radius = Capsule->GetScaledCapsuleRadius();
		const float HalfHeight = Capsule->GetScaledCapsuleHalfHeight();
		const float CylinderLength = FMath::Max(0.0f, HalfHeight * 2.0f - Radius * 2.0f);

		FCollisionDebugGeometry::AddWireCapsule(
			CachedLines,
			WorldTM,
			Radius,
			CylinderLength);
	}
}
