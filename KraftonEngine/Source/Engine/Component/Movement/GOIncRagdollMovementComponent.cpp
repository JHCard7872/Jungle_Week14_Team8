#include "Component/Movement/GOIncRagdollMovementComponent.h"

#include "Component/SceneComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Math/MathUtils.h"
#include "Math/Quat.h"
#include "Serialization/Archive.h"

#include <algorithm>
#include <cmath>

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

	FVector RotateDirection2D(const FVector& Direction, float Degrees)
	{
		const float Radians = Degrees * FMath::DegToRad;
		const float Cos = std::cos(Radians);
		const float Sin = std::sin(Radians);
		return FVector(
			Direction.X * Cos - Direction.Y * Sin,
			Direction.X * Sin + Direction.Y * Cos,
			0.0f);
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
	ClearLastWallAvoidanceDirection();
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

void UGOIncRagdollMovementComponent::SetMaxStepHeight(float InMaxStepHeight)
{
	MaxStepHeight = std::max(0.0f, InMaxStepHeight);
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

void UGOIncRagdollMovementComponent::SetMovementCollisionCapsule(float Radius, float HalfHeight, const FVector& LocalOffset)
{
	ExplicitSweepCapsuleRadius = std::max(0.0f, Radius);
	ExplicitSweepCapsuleHalfHeight = std::max(0.0f, HalfHeight);
	ExplicitSweepCapsuleLocalOffset = LocalOffset;
	bUseExplicitSweepCapsule = ExplicitSweepCapsuleRadius > 0.0f && ExplicitSweepCapsuleHalfHeight > 0.0f;
}

void UGOIncRagdollMovementComponent::ClearMovementCollisionCapsule()
{
	bUseExplicitSweepCapsule = false;
	ExplicitSweepCapsuleRadius = 0.0f;
	ExplicitSweepCapsuleHalfHeight = 0.0f;
	ExplicitSweepCapsuleLocalOffset = FVector(0.0f, 0.0f, 0.0f);
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

	const float DesiredCapsuleZ = FloorHit.WorldHitLocation.Z + GetCapsuleHalfHeight() + FloorSnapClearance;
	const float CurrentCapsuleZ = GetSweepCapsuleWorldLocation().Z;
	FVector Location = Updated->GetWorldLocation();
	Location.Z += DesiredCapsuleZ - CurrentCapsuleZ;
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
		LastWallAvoidanceDirection = FVector(0.0f, 0.0f, 0.0f);
		return;
	}

	Input = AdjustInputForWallAvoidance(Input, DeltaTime);
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

		if (bIgnoreWalkableFloorHits && bStepUpEnabled && bIsGrounded && !IsWalkableFloorHit(Hit))
		{
			const FVector RemainingAfterSafeMove = Remaining - SafeMove;
			if (TryStepUp(RemainingAfterSafeMove, Hit))
			{
				return true;
			}
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

bool UGOIncRagdollMovementComponent::TryStepUp(const FVector& MoveDelta, const FHitResult& BlockingHit)
{
	return AttemptStepUp(MoveDelta, BlockingHit, true);
}

bool UGOIncRagdollMovementComponent::AttemptStepUp(const FVector& MoveDelta, const FHitResult& BlockingHit, bool bCommitMove)
{
	USceneComponent* Updated = GetUpdatedComponent();
	if (!Updated || !bStepUpEnabled || MaxStepHeight <= 0.0f)
	{
		return false;
	}

	if (!bFloorRaycastEnabled || !bIsGrounded)
	{
		return false;
	}

	if (IsWalkableFloorHit(BlockingHit))
	{
		return false;
	}

	const FVector HorizontalDelta(MoveDelta.X, MoveDelta.Y, 0.0f);
	if (HorizontalDelta.Length() <= SmallMoveThreshold)
	{
		return false;
	}

	const FVector OriginalLocation = Updated->GetWorldLocation();
	const float OriginalCapsuleZ = GetSweepCapsuleWorldLocation().Z;
	const bool bWasGrounded = bIsGrounded;
	FVector StepStartNudge(0.0f, 0.0f, 0.0f);
	if (BlockingHit.bStartPenetrating || BlockingHit.Distance <= SweepSkinWidth + SmallMoveThreshold)
	{
		FVector BlockingNormal = GetBestHitNormal(BlockingHit);
		BlockingNormal.Z = 0.0f;
		BlockingNormal = BlockingNormal.GetSafeNormal();
		if (!BlockingNormal.IsNearlyZero())
		{
			StepStartNudge = BlockingNormal * (SweepSkinWidth + 0.01f);
			Updated->SetWorldLocation(OriginalLocation + StepStartNudge);
		}
	}
	const FVector StepUpDelta(0.0f, 0.0f, MaxStepHeight);

	FHitResult UpHit;
	if (SweepCapsuleMoveFrom(GetSweepCapsuleWorldLocation(), StepUpDelta, UpHit))
	{
		const FVector HitNormal = GetBestHitNormal(UpHit);
		const bool bCanIgnoreInitialUpBlock =
			UpHit.Distance <= SweepSkinWidth + SmallMoveThreshold &&
			HitNormal.Z < -WalkableFloorNormalZ &&
			(BlockingHit.bStartPenetrating || BlockingHit.Distance <= SweepSkinWidth + SmallMoveThreshold);
		if (!bCanIgnoreInitialUpBlock)
		{
			Updated->SetWorldLocation(OriginalLocation);
			bIsGrounded = bWasGrounded;
			return false;
		}
	}

	Updated->SetWorldLocation(OriginalLocation + StepStartNudge + StepUpDelta);

	FHitResult ForwardHit;
	if (SweepCapsuleMove(HorizontalDelta, ForwardHit))
	{
		Updated->SetWorldLocation(OriginalLocation);
		bIsGrounded = bWasGrounded;
		return false;
	}

	Updated->SetWorldLocation(Updated->GetWorldLocation() + HorizontalDelta);

	FHitResult StepFloorHit;
	const float StepFloorProbeDistance = MaxStepHeight + FloorProbeDistance;
	const FVector HorizontalDir = HorizontalDelta.GetSafeNormal();
	const float CapsuleRadius = GetSweepCapsuleRadius();
	const float ForwardProbeDistance = std::max(
		HorizontalDelta.Length(),
		CapsuleRadius + std::max(0.0f, StepForwardProbeDistance));
	const FVector ForwardProbeCapsuleLocation = GetSweepCapsuleWorldLocation() + HorizontalDir * ForwardProbeDistance;
	bool bFoundStepFloor =
		TraceFloorAtCapsuleLocation(ForwardProbeCapsuleLocation, StepFloorProbeDistance, StepFloorHit) &&
		IsWalkableFloorHit(StepFloorHit);

	if (bFoundStepFloor)
	{
		const float CandidateCapsuleZ = StepFloorHit.WorldHitLocation.Z + GetCapsuleHalfHeight() + FloorSnapClearance;
		const float CandidateStepHeight = CandidateCapsuleZ - OriginalCapsuleZ;
		if (CandidateStepHeight < -MaxStepHeight - FloorSnapClearance ||
			CandidateStepHeight > MaxStepHeight + FloorSnapClearance)
		{
			bFoundStepFloor = false;
		}
	}

	if (!bFoundStepFloor)
	{
		bFoundStepFloor =
			TraceFloorAtCapsuleLocation(GetSweepCapsuleWorldLocation(), StepFloorProbeDistance, StepFloorHit) &&
			IsWalkableFloorHit(StepFloorHit);
	}

	if (!bFoundStepFloor)
	{
		Updated->SetWorldLocation(OriginalLocation);
		bIsGrounded = bWasGrounded;
		return false;
	}

	const float DesiredCapsuleZ = StepFloorHit.WorldHitLocation.Z + GetCapsuleHalfHeight() + FloorSnapClearance;
	const float StepHeight = DesiredCapsuleZ - OriginalCapsuleZ;
	if (StepHeight < -MaxStepHeight - FloorSnapClearance || StepHeight > MaxStepHeight + FloorSnapClearance)
	{
		Updated->SetWorldLocation(OriginalLocation);
		bIsGrounded = bWasGrounded;
		return false;
	}

	FVector FinalLocation = Updated->GetWorldLocation();
	FinalLocation.Z += DesiredCapsuleZ - GetSweepCapsuleWorldLocation().Z;
	Updated->SetWorldLocation(FinalLocation);

	if (!bCommitMove)
	{
		Updated->SetWorldLocation(OriginalLocation);
		bIsGrounded = bWasGrounded;
		return true;
	}

	Velocity.Z = 0.0f;
	bIsGrounded = true;
	return true;
}

bool UGOIncRagdollMovementComponent::SweepCapsuleMove(const FVector& MoveDelta, FHitResult& OutHit) const
{
	return SweepCapsuleMoveFrom(GetSweepCapsuleWorldLocation(), MoveDelta, OutHit);
}

bool UGOIncRagdollMovementComponent::SweepCapsuleMoveFrom(const FVector& Start, const FVector& MoveDelta, FHitResult& OutHit) const
{
	UWorld* World = GetWorld();
	AActor* Owner = GetOwner();
	if (!World || !Owner || !CanUseCapsuleSweep())
	{
		return false;
	}

	const float MoveDistance = MoveDelta.Length();
	if (MoveDistance <= SmallMoveThreshold)
	{
		return false;
	}

	const FVector MoveDir = MoveDelta * (1.0f / MoveDistance);
	const float Radius = GetSweepCapsuleRadius();
	const float HalfHeight = GetSweepCapsuleHalfHeight();
	const float SweepShrink = std::min(SweepSkinWidth, Radius * 0.45f);
	const FCollisionShape Shape = FCollisionShape::MakeCapsule(
		std::max(0.001f, Radius - SweepShrink),
		std::max(0.001f, HalfHeight - SweepShrink));

	return World->PhysicsSweep(
		Start,
		MoveDir,
		MoveDistance,
		Shape,
		FQuat::Identity,
		OutHit,
		ECollisionChannel::Pawn,
		Owner);
}

FVector UGOIncRagdollMovementComponent::AdjustInputForWallAvoidance(const FVector& Input, float DeltaTime)
{
	const float InputLength = Input.Length();
	if (InputLength <= SmallInputThreshold)
	{
		ClearLastWallAvoidanceDirection();
		return Input;
	}

	const float ProbeDistance = std::max(0.0f, WallAvoidanceProbeDistance);
	const float Strength = FMath::Clamp(WallAvoidanceStrength, 0.0f, 1.0f);
	if (!bWallAvoidanceEnabled || !bSweepMovementEnabled || Strength <= SmallInputThreshold ||
		ProbeDistance <= SmallMoveThreshold || !CanUseCapsuleSweep())
	{
		ClearLastWallAvoidanceDirection();
		return Input;
	}

	FVector DesiredDir(Input.X, Input.Y, 0.0f);
	DesiredDir = DesiredDir.GetSafeNormal();
	if (DesiredDir.IsNearlyZero())
	{
		ClearLastWallAvoidanceDirection();
		return Input;
	}

	if (CornerEscapeTimer > 0.0f && !CornerEscapeDirection.IsNearlyZero())
	{
		CornerEscapeTimer = std::max(0.0f, CornerEscapeTimer - DeltaTime);
		LastWallAvoidanceDirection = CornerEscapeDirection;
		return CornerEscapeDirection * InputLength;
	}

	auto RemoveVelocityIntoNormal = [this](const FVector& Normal)
	{
		if (Normal.IsNearlyZero())
		{
			return;
		}

		FVector HorizontalVelocity(Velocity.X, Velocity.Y, 0.0f);
		const float VelocityIntoWall = HorizontalVelocity.Dot(Normal);
		if (VelocityIntoWall < 0.0f)
		{
			HorizontalVelocity = HorizontalVelocity - Normal * VelocityIntoWall;
			Velocity.X = HorizontalVelocity.X;
			Velocity.Y = HorizontalVelocity.Y;
		}
	};

	auto TryBeginCornerEscape = [&](const FVector& CurrentWallNormal, const FHitResult& Hit)
	{
		if (LockedWallNormal.IsNearlyZero() || CurrentWallNormal.IsNearlyZero())
		{
			return false;
		}

		const float NormalDotThreshold = FMath::Clamp(CornerNormalDotThreshold, -1.0f, 1.0f);
		if (CurrentWallNormal.Dot(LockedWallNormal) >= NormalDotThreshold)
		{
			return false;
		}

		if (Hit.Distance > SweepSkinWidth + SmallMoveThreshold)
		{
			return false;
		}

		FVector EscapeDir = CurrentWallNormal + LockedWallNormal;
		EscapeDir.Z = 0.0f;
		EscapeDir = EscapeDir.GetSafeNormal(1.0e-6f, LockedWallAvoidanceDirection);
		if (EscapeDir.IsNearlyZero())
		{
			EscapeDir = CurrentWallNormal;
		}

		CornerEscapeDirection = EscapeDir;
		CornerEscapeTimer = std::max(0.0f, CornerEscapeDuration);
		LastWallAvoidanceDirection = CornerEscapeDirection;
		LockedWallAvoidanceDirection = CornerEscapeDirection;
		WallAvoidanceLockTimer = 0.0f;

		RemoveVelocityIntoNormal(CurrentWallNormal);
		RemoveVelocityIntoNormal(LockedWallNormal);

		if (USceneComponent* Updated = GetUpdatedComponent())
		{
			const float NudgeDistance = std::max(CornerNudgeDistance, SweepSkinWidth);
			if (NudgeDistance > 0.0f)
			{
				Updated->SetWorldLocation(Updated->GetWorldLocation() + CornerEscapeDirection * NudgeDistance);
			}
		}

		return true;
	};

	if (WallAvoidanceLockTimer > 0.0f && !LockedWallAvoidanceDirection.IsNearlyZero())
	{
		FHitResult LockedForwardHit;
		if (ProbeWallAvoidance(LockedWallAvoidanceDirection, ProbeDistance, LockedForwardHit))
		{
			FVector LockedHitNormal = GetBestHitNormal(LockedForwardHit);
			LockedHitNormal.Z = 0.0f;
			LockedHitNormal = LockedHitNormal.GetSafeNormal();
			if (TryBeginCornerEscape(LockedHitNormal, LockedForwardHit))
			{
				return CornerEscapeDirection * InputLength;
			}
		}

		WallAvoidanceLockTimer = std::max(0.0f, WallAvoidanceLockTimer - DeltaTime);
		LastWallAvoidanceDirection = LockedWallAvoidanceDirection;
		return LockedWallAvoidanceDirection * InputLength;
	}

	FHitResult ForwardHit;
	if (!ProbeWallAvoidance(DesiredDir, ProbeDistance, ForwardHit))
	{
		ClearLastWallAvoidanceDirection();
		return Input;
	}

	USceneComponent* Updated = GetUpdatedComponent();
	if (Updated && bStepUpEnabled && bIsGrounded)
	{
		const FVector OriginalLocation = Updated->GetWorldLocation();
		const bool bWasGrounded = bIsGrounded;
		const float SafeDistance = std::max(0.0f, ForwardHit.Distance - SweepSkinWidth);
		const float ClampedSafeDistance = std::min(SafeDistance, ProbeDistance);
		const FVector SafeMove = DesiredDir * ClampedSafeDistance;
		if (SafeMove.Length() > SmallMoveThreshold)
		{
			Updated->SetWorldLocation(OriginalLocation + SafeMove);
		}

		const float RemainingProbeDistance = std::max(SmallMoveThreshold, ProbeDistance - ClampedSafeDistance);
		const bool bCanStepUp = AttemptStepUp(DesiredDir * RemainingProbeDistance, ForwardHit, false);
		Updated->SetWorldLocation(OriginalLocation);
		bIsGrounded = bWasGrounded;

		if (bCanStepUp)
		{
			ClearLastWallAvoidanceDirection();
			return Input;
		}
	}

	FVector WallNormal = GetBestHitNormal(ForwardHit);
	WallNormal.Z = 0.0f;
	WallNormal = WallNormal.GetSafeNormal();
	if (WallNormal.IsNearlyZero())
	{
		ClearLastWallAvoidanceDirection();
		return Input;
	}

	if (TryBeginCornerEscape(WallNormal, ForwardHit))
	{
		return CornerEscapeDirection * InputLength;
	}

	const float IntoWall = DesiredDir.Dot(WallNormal);
	if (IntoWall >= -SmallInputThreshold)
	{
		ClearLastWallAvoidanceDirection();
		return Input;
	}

	USceneComponent* UpdatedForWallNudge = GetUpdatedComponent();
	if (UpdatedForWallNudge && ForwardHit.Distance <= SweepSkinWidth + SmallMoveThreshold && WallContactNudgeDistance > 0.0f)
	{
		UpdatedForWallNudge->SetWorldLocation(
			UpdatedForWallNudge->GetWorldLocation() +
			WallNormal * std::max(WallContactNudgeDistance, SweepSkinWidth));
	}

	RemoveVelocityIntoNormal(WallNormal);

	const float SideAngle = FMath::Clamp(WallAvoidanceSideProbeAngleDegrees, 0.0f, 90.0f);
	const FVector LeftDir = RotateDirection2D(DesiredDir, SideAngle).GetSafeNormal();
	const FVector RightDir = RotateDirection2D(DesiredDir, -SideAngle).GetSafeNormal();
	const float LeftClearance = GetWallAvoidanceClearance(LeftDir, ProbeDistance);
	const float RightClearance = GetWallAvoidanceClearance(RightDir, ProbeDistance);

	FVector PreferredSideDir = LeftClearance >= RightClearance ? LeftDir : RightDir;
	const float ClearanceDiff = std::abs(LeftClearance - RightClearance);
	if (ClearanceDiff <= SweepSkinWidth && !LastWallAvoidanceDirection.IsNearlyZero())
	{
		PreferredSideDir =
			LeftDir.Dot(LastWallAvoidanceDirection) >= RightDir.Dot(LastWallAvoidanceDirection)
				? LeftDir
				: RightDir;
	}

	FVector SlideDir = DesiredDir - WallNormal * IntoWall;
	SlideDir.Z = 0.0f;
	if (SlideDir.IsNearlyZero())
	{
		SlideDir = FVector(-WallNormal.Y, WallNormal.X, 0.0f);
		if (SlideDir.Dot(PreferredSideDir) < 0.0f)
		{
			SlideDir *= -1.0f;
		}
	}
	SlideDir = SlideDir.GetSafeNormal();

	FVector AvoidDir =
		SlideDir +
		PreferredSideDir * FMath::Clamp(WallAvoidanceSideBias, 0.0f, 1.0f) +
		WallNormal * FMath::Clamp(WallAvoidanceNormalPush, 0.0f, 1.0f);
	AvoidDir.Z = 0.0f;
	AvoidDir = AvoidDir.GetSafeNormal(1.0e-6f, SlideDir);

	const float HitDistance = std::max(0.0f, ForwardHit.Distance);
	const float Closeness = 1.0f - FMath::Clamp(HitDistance / ProbeDistance, 0.0f, 1.0f);
	const float AvoidanceWeight = FMath::Clamp(Strength * (0.45f + Closeness * 0.55f), 0.0f, 1.0f);
	if (AvoidanceWeight <= SmallInputThreshold)
	{
		return Input;
	}

	if (LastWallAvoidanceDirection.IsNearlyZero() || WallAvoidanceSmoothingSpeed <= 0.0f)
	{
		LastWallAvoidanceDirection = AvoidDir;
	}
	else
	{
		const float SmoothAlpha = FMath::Clamp(WallAvoidanceSmoothingSpeed * DeltaTime, 0.0f, 1.0f);
		LastWallAvoidanceDirection =
			FVector::Lerp(LastWallAvoidanceDirection, AvoidDir, SmoothAlpha).GetSafeNormal(1.0e-6f, AvoidDir);
	}

	FVector AdjustedDir = FVector::Lerp(DesiredDir, LastWallAvoidanceDirection, AvoidanceWeight);
	AdjustedDir.Z = 0.0f;
	AdjustedDir = AdjustedDir.GetSafeNormal(1.0e-6f, LastWallAvoidanceDirection);

	const float LockDuration = std::max(0.0f, WallAvoidanceLockDuration);
	if (LockDuration > 0.0f)
	{
		LockedWallAvoidanceDirection = AdjustedDir;
		LockedWallNormal = WallNormal;
		WallAvoidanceLockTimer = LockDuration;
	}

	return AdjustedDir * InputLength;
}

bool UGOIncRagdollMovementComponent::ProbeWallAvoidance(const FVector& Direction, float ProbeDistance, FHitResult& OutHit) const
{
	const FVector ProbeDir = FVector(Direction.X, Direction.Y, 0.0f).GetSafeNormal();
	if (ProbeDir.IsNearlyZero() || ProbeDistance <= SmallMoveThreshold)
	{
		return false;
	}

	if (!SweepCapsuleMoveFrom(GetSweepCapsuleWorldLocation(), ProbeDir * ProbeDistance, OutHit))
	{
		return false;
	}

	return !IsWalkableFloorHit(OutHit);
}

float UGOIncRagdollMovementComponent::GetWallAvoidanceClearance(const FVector& Direction, float ProbeDistance) const
{
	FHitResult Hit;
	if (!ProbeWallAvoidance(Direction, ProbeDistance, Hit))
	{
		return ProbeDistance;
	}

	return std::max(0.0f, Hit.Distance);
}

bool UGOIncRagdollMovementComponent::CanUseCapsuleSweep() const
{
	return GetSweepCapsuleRadius() > 0.0f && GetSweepCapsuleHalfHeight() > 0.0f;
}

FVector UGOIncRagdollMovementComponent::GetSweepCapsuleWorldLocation() const
{
	USceneComponent* Updated = GetUpdatedComponent();
	if (!Updated)
	{
		return FVector(0.0f, 0.0f, 0.0f);
	}

	if (bUseExplicitSweepCapsule)
	{
		return Updated->GetWorldMatrix().TransformPosition(ExplicitSweepCapsuleLocalOffset);
	}

	return Updated->GetWorldLocation();
}

float UGOIncRagdollMovementComponent::GetSweepCapsuleRadius() const
{
	if (bUseExplicitSweepCapsule)
	{
		return ExplicitSweepCapsuleRadius;
	}

	if (UCapsuleComponent* Capsule = Cast<UCapsuleComponent>(GetUpdatedComponent()))
	{
		return Capsule->GetScaledCapsuleRadius();
	}

	return 0.0f;
}

float UGOIncRagdollMovementComponent::GetSweepCapsuleHalfHeight() const
{
	if (bUseExplicitSweepCapsule)
	{
		return ExplicitSweepCapsuleHalfHeight;
	}

	if (UCapsuleComponent* Capsule = Cast<UCapsuleComponent>(GetUpdatedComponent()))
	{
		return Capsule->GetScaledCapsuleHalfHeight();
	}

	return 0.0f;
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
	return TraceFloorAtCapsuleLocation(GetSweepCapsuleWorldLocation(), FloorProbeDistance, OutHit);
}

bool UGOIncRagdollMovementComponent::TraceFloorAtCapsuleLocation(const FVector& CapsuleLocation, float ProbeDistance, FHitResult& OutHit) const
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

	const FVector Dir(0.0f, 0.0f, -1.0f);
	const float MaxDist = HalfHeight + std::max(0.0f, ProbeDistance) + FloorSnapClearance;

	return World->PhysicsRaycastByObjectTypes(
		CapsuleLocation,
		Dir,
		MaxDist,
		OutHit,
		ObjectTypeBit(ECollisionChannel::WorldStatic),
		Owner);
}

float UGOIncRagdollMovementComponent::GetCapsuleHalfHeight() const
{
	return GetSweepCapsuleHalfHeight();
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
	Ar << bUseExplicitSweepCapsule;
	Ar << ExplicitSweepCapsuleRadius;
	Ar << ExplicitSweepCapsuleHalfHeight;
	Ar << ExplicitSweepCapsuleLocalOffset;
	Ar << bStepUpEnabled;
	Ar << MaxStepHeight;
	Ar << StepForwardProbeDistance;
}
