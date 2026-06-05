#pragma once

#include "MovementComponent.h"
#include "Core/Types/CollisionTypes.h"
#include "Math/Vector.h"

class UCapsuleComponent;

// APawn 계열에서 사용할 단순 이동 컴포넌트.
// UpdatedComponent만 직접 이동시키며, Alive 상태에서는 선택적으로 floor raycast로 Z를 보정한다.
// Mesh/ragdoll/Capsule 상태 전환은 알지 않고 Lua 또는 상위 Actor가 컴포넌트 API를 조합한다.
#include "Source/Engine/Component/Movement/GOIncRagdollMovementComponent.generated.h"

UCLASS()
class UGOIncRagdollMovementComponent : public UMovementComponent
{
public:
	GENERATED_BODY()
	UGOIncRagdollMovementComponent() = default;
	~UGOIncRagdollMovementComponent() override = default;

	UFUNCTION(Callable, Category="GOIncRagdollMovement|Input")
	void AddInputVector(const FVector& WorldVector);
	UFUNCTION(Callable, Category="GOIncRagdollMovement|Input")
	FVector ConsumeInputVector();

	UFUNCTION(Callable, Category="GOIncRagdollMovement")
	void StopMovementImmediately();

	UFUNCTION(Callable, Category="GOIncRagdollMovement")
	void SetMovementEnabled(bool bEnabled);
	UFUNCTION(Pure, Category="GOIncRagdollMovement")
	bool IsMovementEnabled() const { return bMovementEnabled; }

	UFUNCTION(Callable, Category="GOIncRagdollMovement")
	void SetMaxSpeed(float InMaxSpeed);
	UFUNCTION(Callable, Category="GOIncRagdollMovement")
	void SetAcceleration(float InAcceleration);
	UFUNCTION(Callable, Category="GOIncRagdollMovement")
	void SetBrakingDeceleration(float InBrakingDeceleration);

	UFUNCTION(Callable, Category="GOIncRagdollMovement|Floor")
	void SetFloorRaycastEnabled(bool bEnabled);
	UFUNCTION(Pure, Category="GOIncRagdollMovement|Floor")
	bool IsFloorRaycastEnabled() const { return bFloorRaycastEnabled; }
	UFUNCTION(Callable, Category="GOIncRagdollMovement|Floor")
	void SetGravityEnabled(bool bEnabled);
	UFUNCTION(Pure, Category="GOIncRagdollMovement|Floor")
	bool IsGravityEnabled() const { return bGravityEnabled; }
	UFUNCTION(Callable, Category="GOIncRagdollMovement|Floor")
	bool SnapUpdatedComponentToFloor();
	UFUNCTION(Pure, Category="GOIncRagdollMovement|Floor")
	bool IsGrounded() const { return bIsGrounded; }

	UFUNCTION(Pure, Category="GOIncRagdollMovement")
	FVector GetVelocity() const { return Velocity; }

	void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction& ThisTickFunction) override;
	void Serialize(FArchive& Ar) override;

	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement", DisplayName="Movement Enabled")
	bool bMovementEnabled = false;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement", DisplayName="Max Speed", Min=0.0f, Max=100.0f, Speed=0.1f)
	float MaxSpeed = 4.0f;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement", DisplayName="Acceleration", Min=0.0f, Max=200.0f, Speed=0.5f)
	float Acceleration = 15.0f;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement", DisplayName="Braking Deceleration", Min=0.0f, Max=200.0f, Speed=0.5f)
	float BrakingDeceleration = 10.0f;

	// Alive 상태에서 UpdatedComponent를 바닥 위로 붙이는 간단한 character-controller 보정.
	// Ragdoll 상태에서는 Lua가 꺼야 한다.
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Floor", DisplayName="Use Floor Raycast")
	bool bFloorRaycastEnabled = false;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Floor", DisplayName="Use Gravity")
	bool bGravityEnabled = false;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Floor", DisplayName="Gravity", Min=0.0f, Max=100.0f, Speed=0.1f)
	float Gravity = 9.8f;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Floor", DisplayName="Floor Probe Distance", Min=0.0f, Max=5.0f, Speed=0.01f)
	float FloorProbeDistance = 0.2f;

private:
	void ApplyInputToVelocity(const FVector& Input, float DeltaTime);
	void ApplyBraking(float DeltaTime);
	void ClampVelocityToMaxSpeed();
	bool TraceFloor(FHitResult& OutHit) const;
	float GetCapsuleHalfHeight() const;
	void ResolveFloorAfterMove();

	FVector PendingInputVector = FVector(0.0f, 0.0f, 0.0f);
	FVector Velocity = FVector(0.0f, 0.0f, 0.0f);
	bool bIsGrounded = false;
};
