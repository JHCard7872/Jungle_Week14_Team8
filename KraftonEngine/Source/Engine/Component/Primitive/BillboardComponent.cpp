#include "BillboardComponent.h"
#include "GameFramework/World.h"
#include "Component/Camera/CameraComponent.h"
#include "Render/Proxy/BillboardSceneProxy.h"
#include "Serialization/Archive.h"
#include "Object/Reflection/ObjectFactory.h"
#include "GameFramework/AActor.h"
#include "Materials/Material.h"
#include "Materials/MaterialManager.h"
#include "Object/GarbageCollection.h"
#include "Math/MathUtils.h"

#include <cstring>
#include <cmath>

namespace
{
	void BuildBillboardAxesWithRoll(const FVector& CameraForward, float RollDegrees, FVector& OutForward, FVector& OutRight, FVector& OutUp)
	{
		OutForward = (CameraForward * -1.0f).Normalized();
		FVector WorldUp = FVector(0.0f, 0.0f, 1.0f);

		if (std::abs(OutForward.Dot(WorldUp)) > 0.99f)
		{
			WorldUp = FVector(0.0f, 1.0f, 0.0f);
		}

		const FVector BaseRight = WorldUp.Cross(OutForward).Normalized();
		const FVector BaseUp = OutForward.Cross(BaseRight).Normalized();

		const float RollRadians = RollDegrees * FMath::DegToRad;
		const float RollCos = std::cos(RollRadians);
		const float RollSin = std::sin(RollRadians);

		OutRight = (BaseRight * RollCos + BaseUp * RollSin).Normalized();
		OutUp = (BaseUp * RollCos - BaseRight * RollSin).Normalized();
	}
}

FPrimitiveSceneProxy* UBillboardComponent::CreateSceneProxy()
{
	return new FBillboardSceneProxy(this);
}

void UBillboardComponent::PostDuplicate()
{
	UPrimitiveComponent::PostDuplicate();

	if (!MaterialSlot.empty() && MaterialSlot != "None")
	{
		UMaterial* LoadedMat = FMaterialManager::Get().GetOrCreateMaterial(MaterialSlot);
		if (LoadedMat)
		{
			SetMaterial(LoadedMat);
		}
	}
}


void UBillboardComponent::AddReferencedObjects(FReferenceCollector& Collector)
{
	UPrimitiveComponent::AddReferencedObjects(Collector);

	Collector.AddReferencedObject(Material, "UBillboardComponent.Material");
}

void UBillboardComponent::SetBillboardRollDegrees(float InDegrees)
{
	if (FMath::Abs(BillboardRollDegrees - InDegrees) <= FMath::KINDA_SMALL_NUMBER)
	{
		return;
	}

	BillboardRollDegrees = InDegrees;
	MarkRenderTransformDirty();
}

void UBillboardComponent::SetBillboardTintColor(const FVector4& InColor)
{
	if (FMath::Abs(BillboardTintColor.X - InColor.X) <= FMath::KINDA_SMALL_NUMBER &&
		FMath::Abs(BillboardTintColor.Y - InColor.Y) <= FMath::KINDA_SMALL_NUMBER &&
		FMath::Abs(BillboardTintColor.Z - InColor.Z) <= FMath::KINDA_SMALL_NUMBER &&
		FMath::Abs(BillboardTintColor.W - InColor.W) <= FMath::KINDA_SMALL_NUMBER)
	{
		return;
	}

	BillboardTintColor = InColor;
	MarkRenderTransformDirty();
}

void UBillboardComponent::SetBillboardOpacity(float InOpacity)
{
	FVector4 NewColor = BillboardTintColor;
	NewColor.W = FMath::Clamp(InOpacity, 0.0f, 1.0f);
	SetBillboardTintColor(NewColor);
}

void UBillboardComponent::SetMaterial(UMaterial* InMaterial)
{
	Material = InMaterial;
	if (Material)
	{
		MaterialSlot = Material->GetAssetPathFileName();
	}
	else
	{
		MaterialSlot = "None";
	}
	// 머티리얼 변경 시 렌더 스테이트와 프록시 갱신
	MarkProxyDirty(EDirtyFlag::Material);
	MarkProxyDirty(EDirtyFlag::Mesh);
}

void UBillboardComponent::PostEditProperty(const char* PropertyName)
{
	UPrimitiveComponent::PostEditProperty(PropertyName);

	if (strcmp(PropertyName, "BillboardRollDegrees") == 0 || strcmp(PropertyName, "BillboardTintColor") == 0)
	{
		MarkRenderTransformDirty();
	}

	if (strcmp(PropertyName, "MaterialSlot") == 0 || strcmp(PropertyName, "Material") == 0)
	{
		if (MaterialSlot == "None" || MaterialSlot.empty())
		{
			SetMaterial(nullptr);
		}
		else
		{
			UMaterial* LoadedMat = FMaterialManager::Get().GetOrCreateMaterial(MaterialSlot);
			if (LoadedMat)
			{
				SetMaterial(LoadedMat);
			}
		}
		MarkRenderStateDirty();
	}
}

void UBillboardComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction& ThisTickFunction)
{
	if (!IsValid(GetOwner())) return;
	UWorld* World = GetWorld();
	if (!World) return;

	// 잔여 정리: POV currency 사용.
	FMinimalViewInfo POV;
	if (!World->GetActivePOV(POV)) return;

	CachedWorldMatrix = ComputeBillboardMatrix(POV.Rotation.GetForwardVector().Normalized());

	UpdateWorldAABB();
}

bool UBillboardComponent::LineTraceComponent(const FRay& Ray, FHitResult& OutHitResult)
{
	FMatrix BillboardWorldMatrix = ComputeBillboardMatrix(Ray.Direction);
	FMatrix InvWorldMatrix = BillboardWorldMatrix.GetInverse();

	FRay LocalRay;
	LocalRay.Origin = InvWorldMatrix.TransformPositionWithW(Ray.Origin);
	LocalRay.Direction = InvWorldMatrix.TransformVector(Ray.Direction).Normalized();

	float t = -LocalRay.Origin.X / LocalRay.Direction.X;
	if (t < 0.0f) return false;

	FVector LocalHitPos = LocalRay.Origin + LocalRay.Direction * t;
	if (LocalHitPos.Y < -0.5f || LocalHitPos.Y > 0.5f ||
		LocalHitPos.Z < -0.5f || LocalHitPos.Z > 0.5f)
	{
		return false;
	}

	FVector WorldHitPos = BillboardWorldMatrix.TransformPositionWithW(LocalHitPos);
	OutHitResult.Distance = (WorldHitPos - Ray.Origin).Length();
	OutHitResult.HitComponent = this;
	return true;
}

FMatrix UBillboardComponent::ComputeBillboardMatrix(const FVector& CameraForward) const
{
	// TickComponent / Picking에서 동일한 Roll 적용 행렬을 사용한다.
	FVector Forward;
	FVector Right;
	FVector Up;
	BuildBillboardAxesWithRoll(CameraForward, BillboardRollDegrees, Forward, Right, Up);

	FMatrix RotMatrix;
	RotMatrix.SetAxes(Forward, Right, Up);

	return FMatrix::MakeScaleMatrix(GetWorldScale()) * RotMatrix * FMatrix::MakeTranslationMatrix(GetWorldLocation());
}
