#pragma once

#include "MovementComponent.h"
#include "Math/Vector.h"

// APawn 계열에서 사용할 단순 이동 컴포넌트.
// UpdatedComponent만 직접 이동시키며, sweep/raycast/경사면/계단 처리는 의도적으로 하지 않는다.
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

private:
	void ApplyInputToVelocity(const FVector& Input, float DeltaTime);
	void ApplyBraking(float DeltaTime);
	void ClampVelocityToMaxSpeed();

	FVector PendingInputVector = FVector(0.0f, 0.0f, 0.0f);
	FVector Velocity = FVector(0.0f, 0.0f, 0.0f);
};
