#include "Component/Movement/GOIncRagdollMovementComponent.h"

#include "Component/SceneComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Serialization/Archive.h"

#include <algorithm>

namespace
{
	constexpr float SmallInputThreshold = 1.0e-4f;
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
	Location.Z = FloorHit.WorldHitLocation.Z + GetCapsuleHalfHeight();
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
		Velocity.Z -= Gravity * DeltaTime;
	}
	else
	{
		Velocity.Z = 0.0f;
	}

	const FVector MoveDelta = Velocity * DeltaTime;
	Updated->SetWorldLocation(Updated->GetWorldLocation() + MoveDelta);

	if (bFloorRaycastEnabled)
	{
		ResolveFloorAfterMove();
	}
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
	const float MaxDist = HalfHeight + FloorProbeDistance;

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
}
