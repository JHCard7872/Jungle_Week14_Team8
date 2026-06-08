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

	UFUNCTION(Callable, Category="GOIncRagdollMovement|Collision")
	void SetSweepMovementEnabled(bool bEnabled) { bSweepMovementEnabled = bEnabled; }
	UFUNCTION(Pure, Category="GOIncRagdollMovement|Collision")
	bool IsSweepMovementEnabled() const { return bSweepMovementEnabled; }
	UFUNCTION(Callable, Category="GOIncRagdollMovement|Collision")
	void SetWallAvoidanceEnabled(bool bEnabled) { bWallAvoidanceEnabled = bEnabled; }
	UFUNCTION(Pure, Category="GOIncRagdollMovement|Collision")
	bool IsWallAvoidanceEnabled() const { return bWallAvoidanceEnabled; }
	UFUNCTION(Pure, Category="GOIncRagdollMovement|Collision")
	bool HasLastWallAvoidanceDirection() const { return !LastWallAvoidanceDirection.IsNearlyZero(); }
	UFUNCTION(Pure, Category="GOIncRagdollMovement|Collision")
	FVector GetLastWallAvoidanceDirection() const { return LastWallAvoidanceDirection; }
	UFUNCTION(Callable, Category="GOIncRagdollMovement|Collision")
	void ClearLastWallAvoidanceDirection() { LastWallAvoidanceDirection = FVector(0.0f, 0.0f, 0.0f); }
	UFUNCTION(Callable, Category="GOIncRagdollMovement|Step")
	void SetStepUpEnabled(bool bEnabled) { bStepUpEnabled = bEnabled; }
	UFUNCTION(Pure, Category="GOIncRagdollMovement|Step")
	bool IsStepUpEnabled() const { return bStepUpEnabled; }
	UFUNCTION(Callable, Category="GOIncRagdollMovement|Step")
	void SetMaxStepHeight(float InMaxStepHeight);
	UFUNCTION(Pure, Category="GOIncRagdollMovement|Floor")
	bool IsGrounded() const { return bIsGrounded; }

	UFUNCTION(Callable, Category="GOIncRagdollMovement|Collision")
	void SetMovementCollisionCapsule(float Radius, float HalfHeight, const FVector& LocalOffset);
	UFUNCTION(Callable, Category="GOIncRagdollMovement|Collision")
	void ClearMovementCollisionCapsule();

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

	// Alive 상태에서는 UpdatedComponent를 그냥 teleport하지 않고 capsule sweep으로 이동한다.
	// UpdatedComponent가 Capsule이 아니어도, 외부에서 sweep capsule shape/offset을 값으로 설정하면 사용할 수 있다.
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Collision", DisplayName="Use Sweep Movement")
	bool bSweepMovementEnabled = true;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Collision", DisplayName="Sweep Skin Width", Min=0.0f, Max=0.5f, Speed=0.005f)
	float SweepSkinWidth = 0.02f;
	UPROPERTY(Edit, Category="GOIncRagdollMovement|Collision", DisplayName="Use Wall Avoidance")
	bool bWallAvoidanceEnabled = true;
	UPROPERTY(Edit, Category="GOIncRagdollMovement|Collision", DisplayName="Wall Avoidance Probe Distance", Min=0.0f, Max=10.0f, Speed=0.01f)
	float WallAvoidanceProbeDistance = 1.5f;
	UPROPERTY(Edit, Category="GOIncRagdollMovement|Collision", DisplayName="Wall Avoidance Strength", Min=0.0f, Max=1.0f, Speed=0.01f)
	float WallAvoidanceStrength = 1.0f;
	UPROPERTY(Edit, Category="GOIncRagdollMovement|Collision", DisplayName="Wall Avoidance Side Probe Angle", Min=0.0f, Max=90.0f, Speed=0.5f)
	float WallAvoidanceSideProbeAngleDegrees = 35.0f;
	UPROPERTY(Edit, Category="GOIncRagdollMovement|Collision", DisplayName="Wall Avoidance Side Bias", Min=0.0f, Max=1.0f, Speed=0.01f)
	float WallAvoidanceSideBias = 0.25f;
	UPROPERTY(Edit, Category="GOIncRagdollMovement|Collision", DisplayName="Wall Avoidance Normal Push", Min=0.0f, Max=1.0f, Speed=0.01f)
	float WallAvoidanceNormalPush = 0.65f;
	UPROPERTY(Edit, Category="GOIncRagdollMovement|Collision", DisplayName="Wall Avoidance Smoothing Speed", Min=0.0f, Max=60.0f, Speed=0.1f)
	float WallAvoidanceSmoothingSpeed = 12.0f;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Step", DisplayName="Use Step Up")
	bool bStepUpEnabled = true;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Step", DisplayName="Max Step Height", Min=0.0f, Max=2.0f, Speed=0.01f)
	float MaxStepHeight = 0.0f;

	// Component 간 직접 참조를 피하기 위해 CapsuleComponent 포인터 대신 shape 값만 저장한다.
	// Actor/Lua가 AliveCapsule의 크기와 UpdatedComponent 기준 local offset을 전달한다.
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Collision", DisplayName="Use Explicit Sweep Capsule")
	bool bUseExplicitSweepCapsule = false;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Collision", DisplayName="Explicit Capsule Radius", Min=0.0f, Max=100.0f, Speed=0.01f)
	float ExplicitSweepCapsuleRadius = 0.0f;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Collision", DisplayName="Explicit Capsule Half Height", Min=0.0f, Max=100.0f, Speed=0.01f)
	float ExplicitSweepCapsuleHalfHeight = 0.0f;
	UPROPERTY(Edit, Save, Category="GOIncRagdollMovement|Collision", DisplayName="Explicit Capsule Local Offset")
	FVector ExplicitSweepCapsuleLocalOffset = FVector(0.0f, 0.0f, 0.0f);

private:
	FVector AdjustInputForWallAvoidance(const FVector& Input, float DeltaTime);
	bool ProbeWallAvoidance(const FVector& Direction, float ProbeDistance, FHitResult& OutHit) const;
	float GetWallAvoidanceClearance(const FVector& Direction, float ProbeDistance) const;
	void ApplyInputToVelocity(const FVector& Input, float DeltaTime);
	void ApplyBraking(float DeltaTime);
	void ClampVelocityToMaxSpeed();
	bool TraceFloor(FHitResult& OutHit) const;
	float GetCapsuleHalfHeight() const;
	void ResolveFloorAfterMove();
	void MoveUpdatedComponent(const FVector& MoveDelta, bool bIgnoreWalkableFloorHits = false);
	bool MoveUpdatedComponentWithSweep(const FVector& MoveDelta, bool bIgnoreWalkableFloorHits);
	bool TryStepUp(const FVector& MoveDelta, const FHitResult& BlockingHit);
	bool SweepCapsuleMove(const FVector& MoveDelta, FHitResult& OutHit) const;
	bool SweepCapsuleMoveFrom(const FVector& Start, const FVector& MoveDelta, FHitResult& OutHit) const;
	bool CanUseCapsuleSweep() const;
	FVector GetSweepCapsuleWorldLocation() const;
	float GetSweepCapsuleRadius() const;
	float GetSweepCapsuleHalfHeight() const;

	FVector PendingInputVector = FVector(0.0f, 0.0f, 0.0f);
	FVector Velocity = FVector(0.0f, 0.0f, 0.0f);
	FVector LastWallAvoidanceDirection = FVector(0.0f, 0.0f, 0.0f);
	bool bIsGrounded = false;
};
