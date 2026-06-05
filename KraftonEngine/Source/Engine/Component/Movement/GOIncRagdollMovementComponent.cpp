#include "Component/Movement/GOIncRagdollMovementComponent.h"

#include "Component/SceneComponent.h"
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

	Velocity.Z = 0.0f;
	const FVector MoveDelta = Velocity * DeltaTime;
	Updated->SetWorldLocation(Updated->GetWorldLocation() + MoveDelta);
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
		Velocity.Z = 0.0f;
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
		Velocity = FVector(0.0f, 0.0f, 0.0f);
		return;
	}

	const float NewSpeed = std::max(0.0f, Speed2D - BrakingDeceleration * DeltaTime);
	const FVector Direction = Velocity2D * (1.0f / Speed2D);
	Velocity.X = Direction.X * NewSpeed;
	Velocity.Y = Direction.Y * NewSpeed;
	Velocity.Z = 0.0f;
}

void UGOIncRagdollMovementComponent::ClampVelocityToMaxSpeed()
{
	const FVector Velocity2D(Velocity.X, Velocity.Y, 0.0f);
	const float Speed2D = Velocity2D.Length();
	if (Speed2D <= MaxSpeed || Speed2D <= SmallInputThreshold)
	{
		Velocity.Z = 0.0f;
		return;
	}

	const FVector Direction = Velocity2D * (1.0f / Speed2D);
	Velocity.X = Direction.X * MaxSpeed;
	Velocity.Y = Direction.Y * MaxSpeed;
	Velocity.Z = 0.0f;
}

void UGOIncRagdollMovementComponent::Serialize(FArchive& Ar)
{
	Super::Serialize(Ar);
	Ar << bMovementEnabled;
	Ar << MaxSpeed;
	Ar << Acceleration;
	Ar << BrakingDeceleration;
}
