#include "Component/Movement/GOIncRagdollMovementComponent.h"

#include "Component/SceneComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Math/Quat.h"
#include "Serialization/Archive.h"

#include <algorithm>

namespace
{
	constexpr float SmallInputThreshold = 1.0e-4f;
	constexpr float SmallMoveThreshold = 1.0e-4f;
	constexpr float WalkableFloorNormalZ = 0.55f;
	constexpr float FloorSnapClearance = 0.03f;
	constexpr int32 MaxSweepSlideIterations = 4;

	FVector GetBestHitNormal(const FHitResult& Hit)
	{
		FVector Normal = Hit.WorldNormal.GetSafeNormal();
		if (Normal.IsNearlyZero())
		{
			Normal = Hit.ImpactNormal.GetSafeNormal();
		}
		return Normal;
	}

	bool IsWalkableFloorHit(const FHitResult& Hit)
	{
		const FVector Normal = GetBestHitNormal(Hit);
		return !Normal.IsNearlyZero() && Normal.Z > WalkableFloorNormalZ;
	}
}

void UGOIncRagdollMovementComponent::AddInputVector(const FVector& WorldVector)
{
	PendingInputVector += WorldVector;
}

FVector UGOIncRagdollMovementComponent::ConsumeInputVector()
{
	const FVector Consumed = PendingInputVector;
	PendingInputVector = FVector(0.0f, 0.0f, 0.0f);
	return Consumed;
}

void UGOIncRagdollMovementComponent::StopMovementImmediately()
{
	Velocity = FVector(0.0f, 0.0f, 0.0f);
	PendingInputVector = FVector(0.0f, 0.0f, 0.0f);
}

void UGOIncRagdollMovementComponent::SetMovementEnabled(bool bEnabled)
{
	bMovementEnabled = bEnabled;
	if (!bMovementEnabled)
	{
		StopMovementImmediately();
	}
}

void UGOIncRagdollMovementComponent::SetMaxSpeed(float InMaxSpeed)
{
	MaxSpeed = std::max(0.0f, InMaxSpeed);
	ClampVelocityToMaxSpeed();
}

void UGOIncRagdollMovementComponent::SetAcceleration(float InAcceleration)
{
	Acceleration = std::max(0.0f, InAcceleration);
}

void UGOIncRagdollMovementComponent::SetBrakingDeceleration(float InBrakingDeceleration)
{
	BrakingDeceleration = std::max(0.0f, InBrakingDeceleration);
}

void UGOIncRagdollMovementComponent::SetFloorRaycastEnabled(bool bEnabled)
{
	bFloorRaycastEnabled = bEnabled;
	if (!bFloorRaycastEnabled)
	{
		bIsGrounded = false;
	}
}

void UGOIncRagdollMovementComponent::SetGravityEnabled(bool bEnabled)
{
	bGravityEnabled = bEnabled;
	if (!bGravityEnabled)
	{
		Velocity.Z = 0.0f;
	}
}

bool UGOIncRagdollMovementComponent::SnapUpdatedComponentToFloor()
{
	FHitResult FloorHit;
	if (!TraceFloor(FloorHit))
	{
		bIsGrounded = false;
		return false;
	}

	USceneComponent* Updated = GetUpdatedComponent();
	if (!Updated)
	{
		return false;
	}

	FVector Location = Updated->GetWorldLocation();
	Location.Z = FloorHit.WorldHitLocation.Z + GetCapsuleHalfHeight() + FloorSnapClearance;
	Updated->SetWorldLocation(Location);
	Velocity.Z = 0.0f;
	bIsGrounded = true;
	return true;
}

void UGOIncRagdollMovementComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction& ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);

	FVector Input = ConsumeInputVector();
	Input.Z = 0.0f;

	USceneComponent* Updated = GetUpdatedComponent();
	if (!bMovementEnabled || !Updated || DeltaTime <= 0.0f)
	{
		return;
	}

	ApplyInputToVelocity(Input, DeltaTime);

	if (bGravityEnabled)
	{
		if (bFloorRaycastEnabled && bIsGrounded && Velocity.Z <= 0.0f)
		{
			// 이미 바닥에 붙어 있는 상태에서는 매 프레임 아래 방향 sweep을 만들지 않는다.
			// 그렇지 않으면 floor contact가 horizontal sweep까지 끊어 먹어서 이동이 덜컥거린다.
			Velocity.Z = 0.0f;
		}
		else
		{
			Velocity.Z -= Gravity * DeltaTime;
		}
	}
	else
	{
		Velocity.Z = 0.0f;
	}

	const FVector HorizontalMoveDelta(Velocity.X * DeltaTime, Velocity.Y * DeltaTime, 0.0f);
	MoveUpdatedComponent(HorizontalMoveDelta, true);

	if (!bFloorRaycastEnabled || !bIsGrounded || Velocity.Z > 0.0f)
	{
		const FVector VerticalMoveDelta(0.0f, 0.0f, Velocity.Z * DeltaTime);
		MoveUpdatedComponent(VerticalMoveDelta, false);
	}

	if (bFloorRaycastEnabled)
	{
		ResolveFloorAfterMove();
	}
}


void UGOIncRagdollMovementComponent::MoveUpdatedComponent(const FVector& MoveDelta, bool bIgnoreWalkableFloorHits)
{
	USceneComponent* Updated = GetUpdatedComponent();
	if (!Updated || MoveDelta.Length() <= SmallMoveThreshold)
	{
		return;
	}

	if (bSweepMovementEnabled && CanUseCapsuleSweep() && MoveUpdatedComponentWithSweep(MoveDelta, bIgnoreWalkableFloorHits))
	{
		return;
	}

	Updated->SetWorldLocation(Updated->GetWorldLocation() + MoveDelta);
}

bool UGOIncRagdollMovementComponent::MoveUpdatedComponentWithSweep(const FVector& MoveDelta, bool bIgnoreWalkableFloorHits)
{
	USceneComponent* Updated = GetUpdatedComponent();
	if (!Updated)
	{
		return false;
	}

	FVector Remaining = MoveDelta;
	for (int32 Iteration = 0; Iteration < MaxSweepSlideIterations; ++Iteration)
	{
		const float RemainingDistance = Remaining.Length();
		if (RemainingDistance <= SmallMoveThreshold)
		{
			return true;
		}

		FHitResult Hit;
		if (!SweepCapsuleMove(Remaining, Hit))
		{
			Updated->SetWorldLocation(Updated->GetWorldLocation() + Remaining);
			return true;
		}

		// 수평 이동 중에는 floor contact를 벽처럼 처리하지 않는다.
		// 바닥 보정은 이동 마지막의 ResolveFloorAfterMove()에서 한 번만 수행한다.
		if (bIgnoreWalkableFloorHits && IsWalkableFloorHit(Hit))
		{
			Updated->SetWorldLocation(Updated->GetWorldLocation() + Remaining);
			return true;
		}

		const FVector MoveDir = Remaining * (1.0f / RemainingDistance);
		const float SafeDistance = std::max(0.0f, Hit.Distance - SweepSkinWidth);
		const FVector SafeMove = MoveDir * std::min(SafeDistance, RemainingDistance);
		if (SafeMove.Length() > SmallMoveThreshold)
		{
			Updated->SetWorldLocation(Updated->GetWorldLocation() + SafeMove);
		}

		if (Hit.bStartPenetrating)
		{
			Velocity.Z = std::max(0.0f, Velocity.Z);
			return true;
		}

		const FVector UsedMove = MoveDir * std::min(Hit.Distance, RemainingDistance);
		Remaining = Remaining - UsedMove;

		FVector Normal = GetBestHitNormal(Hit);
		if (Normal.IsNearlyZero())
		{
			return true;
		}

		const float IntoSurface = Remaining.Dot(Normal);
		if (IntoSurface < 0.0f)
		{
			Remaining = Remaining - Normal * IntoSurface;
		}

		if (Normal.Z > WalkableFloorNormalZ && Velocity.Z < 0.0f)
		{
			Velocity.Z = 0.0f;
			bIsGrounded = true;
		}
	}

	return true;
}

bool UGOIncRagdollMovementComponent::SweepCapsuleMove(const FVector& MoveDelta, FHitResult& OutHit) const
{
	USceneComponent* Updated = GetUpdatedComponent();
	UCapsuleComponent* Capsule = Cast<UCapsuleComponent>(Updated);
	UWorld* World = GetWorld();
	AActor* Owner = GetOwner();
	if (!Capsule || !World || !Owner)
	{
		return false;
	}

	const float MoveDistance = MoveDelta.Length();
	if (MoveDistance <= SmallMoveThreshold)
	{
		return false;
	}

	const FVector MoveDir = MoveDelta * (1.0f / MoveDistance);
	const float SweepShrink = std::min(SweepSkinWidth, Capsule->GetScaledCapsuleRadius() * 0.45f);
	const FCollisionShape Shape = FCollisionShape::MakeCapsule(
		std::max(0.001f, Capsule->GetScaledCapsuleRadius() - SweepShrink),
		std::max(0.001f, Capsule->GetScaledCapsuleHalfHeight() - SweepShrink));

	return World->PhysicsSweep(
		Updated->GetWorldLocation(),
		MoveDir,
		MoveDistance,
		Shape,
		FQuat::Identity,
		OutHit,
		ECollisionChannel::Pawn,
		Owner);
}

bool UGOIncRagdollMovementComponent::CanUseCapsuleSweep() const
{
	return Cast<UCapsuleComponent>(GetUpdatedComponent()) != nullptr;
}

void UGOIncRagdollMovementComponent::ApplyInputToVelocity(const FVector& Input, float DeltaTime)
{
	const float InputLength = Input.Length();
	if (InputLength > SmallInputThreshold)
	{
		const float InputScale = std::min(InputLength, 1.0f);
		const FVector Direction = Input * (1.0f / InputLength);
		Velocity.X += Direction.X * Acceleration * InputScale * DeltaTime;
		Velocity.Y += Direction.Y * Acceleration * InputScale * DeltaTime;
		ClampVelocityToMaxSpeed();
		return;
	}

	ApplyBraking(DeltaTime);
}

void UGOIncRagdollMovementComponent::ApplyBraking(float DeltaTime)
{
	const FVector Velocity2D(Velocity.X, Velocity.Y, 0.0f);
	const float Speed2D = Velocity2D.Length();
	if (Speed2D <= SmallInputThreshold)
	{
		Velocity.X = 0.0f;
		Velocity.Y = 0.0f;
		return;
	}

	const float NewSpeed = std::max(0.0f, Speed2D - BrakingDeceleration * DeltaTime);
	const FVector Direction = Velocity2D * (1.0f / Speed2D);
	Velocity.X = Direction.X * NewSpeed;
	Velocity.Y = Direction.Y * NewSpeed;
}

void UGOIncRagdollMovementComponent::ClampVelocityToMaxSpeed()
{
	const FVector Velocity2D(Velocity.X, Velocity.Y, 0.0f);
	const float Speed2D = Velocity2D.Length();
	if (Speed2D <= MaxSpeed || Speed2D <= SmallInputThreshold)
	{
		return;
	}

	const FVector Direction = Velocity2D * (1.0f / Speed2D);
	Velocity.X = Direction.X * MaxSpeed;
	Velocity.Y = Direction.Y * MaxSpeed;
}

bool UGOIncRagdollMovementComponent::TraceFloor(FHitResult& OutHit) const
{
	USceneComponent* Updated = GetUpdatedComponent();
	if (!Updated)
	{
		return false;
	}

	AActor* Owner = GetOwner();
	if (!Owner)
	{
		return false;
	}

	UWorld* World = GetWorld();
	if (!World)
	{
		return false;
	}

	const float HalfHeight = GetCapsuleHalfHeight();
	if (HalfHeight <= 0.0f)
	{
		return false;
	}

	const FVector Start = Updated->GetWorldLocation();
	const FVector Dir(0.0f, 0.0f, -1.0f);
	const float MaxDist = HalfHeight + FloorProbeDistance + FloorSnapClearance;

	return World->PhysicsRaycastByObjectTypes(
		Start,
		Dir,
		MaxDist,
		OutHit,
		ObjectTypeBit(ECollisionChannel::WorldStatic),
		Owner);
}

float UGOIncRagdollMovementComponent::GetCapsuleHalfHeight() const
{
	if (UCapsuleComponent* Capsule = Cast<UCapsuleComponent>(GetUpdatedComponent()))
	{
		return Capsule->GetScaledCapsuleHalfHeight();
	}

	return 0.0f;
}

void UGOIncRagdollMovementComponent::ResolveFloorAfterMove()
{
	if (SnapUpdatedComponentToFloor())
	{
		return;
	}

	bIsGrounded = false;
}

void UGOIncRagdollMovementComponent::Serialize(FArchive& Ar)
{
	Super::Serialize(Ar);
	Ar << bMovementEnabled;
	Ar << MaxSpeed;
	Ar << Acceleration;
	Ar << BrakingDeceleration;
	Ar << bFloorRaycastEnabled;
	Ar << bGravityEnabled;
	Ar << Gravity;
	Ar << FloorProbeDistance;
	Ar << bSweepMovementEnabled;
	Ar << SweepSkinWidth;
}
