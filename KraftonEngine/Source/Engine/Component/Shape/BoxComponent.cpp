// Copyright Epic Games, Inc. All Rights Reserved.
#include "BoxComponent.h"
#include "Collision/Ray/RayUtils.h"
#include "Object/Reflection/ObjectFactory.h"
#include "Serialization/Archive.h"
#include "Render/Scene/FScene.h"
#include "Math/Quat.h"
#include "Math/Transform.h"

#include <cstring>
#include <cmath>

namespace
{
	FVector ComputeBoxLocalNormal(const FVector& LocalHit, const FVector& Extent)
	{
		const float DX = std::abs(std::abs(LocalHit.X) - Extent.X);
		const float DY = std::abs(std::abs(LocalHit.Y) - Extent.Y);
		const float DZ = std::abs(std::abs(LocalHit.Z) - Extent.Z);

		if (DX <= DY && DX <= DZ)
		{
			return FVector(LocalHit.X >= 0.0f ? 1.0f : -1.0f, 0.0f, 0.0f);
		}
		if (DY <= DX && DY <= DZ)
		{
			return FVector(0.0f, LocalHit.Y >= 0.0f ? 1.0f : -1.0f, 0.0f);
		}
		return FVector(0.0f, 0.0f, LocalHit.Z >= 0.0f ? 1.0f : -1.0f);
	}
}

void UBoxComponent::SetBoxExtent(const FVector& InExtent)
{
	BoxExtent = InExtent;
	LocalExtents = BoxExtent;
	MarkWorldBoundsDirty();
	MarkRenderTransformDirty();
	// PhysX shape 도 새 extent 로 재구성 — 런타임에 SetBoxExtent 했을 때 콜리전/overlap
	// 영역이 안 바뀌던 버그 수정. bComponentHasBegunPlay 가 false 면 NotifyPhysicsBodyDirty
	// 가 no-op 라 BeginPlay 전 setter 호출은 영향 없음.
	NotifyPhysicsBodyDirty();
}

FVector UBoxComponent::GetScaledBoxExtent() const
{
	FVector Scale = GetWorldScale();
	return FVector(BoxExtent.X * Scale.X, BoxExtent.Y * Scale.Y, BoxExtent.Z * Scale.Z);
}

bool UBoxComponent::LineTraceComponent(const FRay& Ray, FHitResult& OutHitResult)
{
	const FVector Extent(
		std::abs(BoxExtent.X),
		std::abs(BoxExtent.Y),
		std::abs(BoxExtent.Z)
	);
	if (Extent.X <= 0.0f || Extent.Y <= 0.0f || Extent.Z <= 0.0f)
	{
		return false;
	}

	const FMatrix& WorldMatrix = GetWorldMatrix();
	const FMatrix& WorldInverse = GetWorldInverseMatrix();

	FRay LocalRay;
	LocalRay.Origin = WorldInverse.TransformPositionWithW(Ray.Origin);
	LocalRay.Direction = WorldInverse.TransformVector(Ray.Direction).GetSafeNormal();
	if (LocalRay.Direction.IsNearlyZero())
	{
		return false;
	}

	float TMin = 0.0f;
	float TMax = 0.0f;
	if (!FRayUtils::IntersectRayAABB(LocalRay, -Extent, Extent, TMin, TMax))
	{
		return false;
	}

	const float LocalDistance = TMin >= 0.0f ? TMin : TMax;
	if (LocalDistance < 0.0f)
	{
		return false;
	}

	const FVector LocalHit = LocalRay.Origin + LocalRay.Direction * LocalDistance;
	const FVector WorldHit = WorldMatrix.TransformPositionWithW(LocalHit);
	const FVector LocalNormal = ComputeBoxLocalNormal(LocalHit, Extent);
	const FVector WorldNormal = WorldMatrix.TransformVector(LocalNormal).GetSafeNormal();

	OutHitResult = {};
	OutHitResult.bHit = true;
	OutHitResult.Distance = FVector::Distance(Ray.Origin, WorldHit);
	OutHitResult.WorldHitLocation = WorldHit;
	OutHitResult.WorldNormal = WorldNormal;
	OutHitResult.ImpactNormal = WorldNormal;
	OutHitResult.HitComponent = this;
	return true;
}

void UBoxComponent::ContributeSelectedVisuals(FScene& Scene) const
{
	const FVector Center = GetWorldLocation();
	const FVector Ext = GetScaledBoxExtent();
	const FColor Color = GetShapeColor();
	// World rotation을 local 코너 오프셋에 적용 — 그러지 않으면 박스가 항상
	// 월드 축 정렬로 그려져 컴포넌트가 회전된 경우 자식들과 시각상 어긋난다.
	// 스케일 제거 후 회전 추출 — 비균등 스케일에서 ToQuat 직접 호출은 회전을 왜곡한다.
	const FQuat WorldRot = FTransform::FromMatrixWithScale(GetWorldMatrix()).Rotation;

	// 8 corners (회전 반영)
	FVector Corners[8];
	for (int32 i = 0; i < 8; ++i)
	{
		FVector LocalOffset(
			(i & 1) ? Ext.X : -Ext.X,
			(i & 2) ? Ext.Y : -Ext.Y,
			(i & 4) ? Ext.Z : -Ext.Z
		);
		Corners[i] = Center + WorldRot.RotateVector(LocalOffset);
	}

	// 12 edges: bottom 4, top 4, vertical 4
	// Bottom (z = -Ext.Z): 0-1, 1-3, 3-2, 2-0
	Scene.AddDebugLine(Corners[0], Corners[1], Color);
	Scene.AddDebugLine(Corners[1], Corners[3], Color);
	Scene.AddDebugLine(Corners[3], Corners[2], Color);
	Scene.AddDebugLine(Corners[2], Corners[0], Color);

	// Top (z = +Ext.Z): 4-5, 5-7, 7-6, 6-4
	Scene.AddDebugLine(Corners[4], Corners[5], Color);
	Scene.AddDebugLine(Corners[5], Corners[7], Color);
	Scene.AddDebugLine(Corners[7], Corners[6], Color);
	Scene.AddDebugLine(Corners[6], Corners[4], Color);

	// Vertical: 0-4, 1-5, 2-6, 3-7
	Scene.AddDebugLine(Corners[0], Corners[4], Color);
	Scene.AddDebugLine(Corners[1], Corners[5], Color);
	Scene.AddDebugLine(Corners[2], Corners[6], Color);
	Scene.AddDebugLine(Corners[3], Corners[7], Color);
}

void UBoxComponent::PostEditProperty(const char* PropertyName)
{
	UShapeComponent::PostEditProperty(PropertyName);

	if (strcmp(PropertyName, "BoxExtent") == 0 || strcmp(PropertyName, "Box Extent") == 0)
	{
		SetBoxExtent(BoxExtent);
	}
}
