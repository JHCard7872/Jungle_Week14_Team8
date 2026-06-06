#include "GameFramework/Pawn/GOIncRagdollPawn.h"

#include "Animation/AnimationManager.h"
#include "Component/Movement/GOIncRagdollMovementComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Component/Script/LuaScriptComponent.h"
#include "Component/SceneComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "Core/Logging/Log.h"
#include "Core/Types/CollisionTypes.h"
#include "GameFramework/World.h"
#include "Mesh/MeshManager.h"
#include "Runtime/Engine.h"

namespace
{
	const FString DefaultGOIncRagdollSkeletalMeshFileName = "Content/Data/Sonic/sc_dash_loop_anm_hkx_SkeletalMesh.uasset";
	const FString DefaultGOIncRagdollLuaScriptFileName = "GOIncRagdollPawn_Test.lua";
	const FString DefaultGOIncRagdollRunAnimationFileName = "Content/Data/Sonic/sc_dash_loop_anm_hkx_sc_dash_loop.uasset";

	constexpr float DefaultAliveCapsuleRadius = 1.8f;
	constexpr float DefaultAliveCapsuleHalfHeight = 3.0f;
	constexpr float DefaultReviveTriggerCapsuleRadius = 2.4f;
	constexpr float DefaultReviveTriggerCapsuleHalfHeight = 3.4f;
	constexpr float ReviveGroundTraceUp = 50.0f;
	constexpr float ReviveGroundTraceDown = 300.0f;
	constexpr float ReviveGroundSkinWidth = 0.02f;
}

void AGOIncRagdollPawn::InitDefaultComponents()
{
	InitDefaultComponents(DefaultGOIncRagdollSkeletalMeshFileName, DefaultGOIncRagdollLuaScriptFileName);
}

void AGOIncRagdollPawn::InitDefaultComponents(const FString& SkeletalMeshFileName, const FString& ScriptFile)
{
	AddTag(FName("Ragdoll"));
	// NPC Pawn이므로 PlayerController 자동 possess 대상이 되지 않게 둔다.
	SetAutoPossessPlayer(false);

	// 1) GOIncRoot — collision/physics가 없는 실제 Actor root.
	GOIncRootComponent = AddComponent<USceneComponent>();
	SetRootComponent(GOIncRootComponent);

	// 2) AliveCapsule — Alive 상태에서 이동/바닥/벽 충돌을 담당한다.
	CapsuleComponent = AddComponent<UCapsuleComponent>();
	CapsuleComponent->AttachToComponent(GOIncRootComponent);
	CapsuleComponent->SetRelativeLocation(FVector(0.0f, 0.0f, 0.0f));
	ConfigureAliveCollisionCapsuleDefaults();

	// 3) ReviveTriggerCapsule — DeadRagdoll 상태에서 Player overlap revive 감지만 담당한다.
	ReviveTriggerCapsuleComponent = AddComponent<UCapsuleComponent>();
	ReviveTriggerCapsuleComponent->AttachToComponent(GOIncRootComponent);
	ReviveTriggerCapsuleComponent->SetRelativeLocation(FVector(0.0f, 0.0f, 0.0f));
	ConfigureReviveTriggerCapsuleDefaults();

	// 4) SkeletalMesh — Animation/ragdoll 표현 담당.
	Mesh = AddComponent<USkeletalMeshComponent>();
	Mesh->AttachToComponent(GOIncRootComponent);

	SkeletalMeshPath = SkeletalMeshFileName.empty()
		? DefaultGOIncRagdollSkeletalMeshFileName
		: SkeletalMeshFileName;
	FleeAnimationPath = DefaultGOIncRagdollRunAnimationFileName;

	SetSkeletalMeshPath(SkeletalMeshPath);

	ApplyInitialRagdollState();

	// 5) GOIncRagdollMovement — non-scene. Root를 이동시키되, sweep shape는 AliveCapsule 값으로 사용한다.
	RagdollMovementComponent = AddComponent<UGOIncRagdollMovementComponent>();
	ConfigureMovementUpdatedComponent();

	// 6) LuaScript — 상태 판단/컴포넌트 API 조합은 Lua에서 처리한다.
	LuaScriptComponent = AddComponent<ULuaScriptComponent>();
	if (!ScriptFile.empty())
	{
		LuaScriptComponent->SetScriptFile(ScriptFile);
	}
}


void AGOIncRagdollPawn::ConfigureAliveCollisionCapsuleDefaults()
{
	if (!CapsuleComponent)
	{
		return;
	}

	CapsuleComponent->SetCapsuleSize(DefaultAliveCapsuleRadius, DefaultAliveCapsuleHalfHeight);
	CapsuleComponent->SetSimulatePhysics(false);
	CapsuleComponent->SetKinematicPhysics(true);
	CapsuleComponent->SetGenerateOverlapEvents(false);
	CapsuleComponent->SetCollisionObjectType(ECollisionChannel::Pawn);
	CapsuleComponent->SetCollisionResponseToAllChannels(ECollisionResponse::Block);
	CapsuleComponent->SetCollisionResponseToChannel(ECollisionChannel::Trigger, ECollisionResponse::Ignore);
	CapsuleComponent->SetCollisionEnabled(ECollisionEnabled::NoCollision);
}

void AGOIncRagdollPawn::ConfigureReviveTriggerCapsuleDefaults()
{
	if (!ReviveTriggerCapsuleComponent)
	{
		return;
	}

	ReviveTriggerCapsuleComponent->SetCapsuleSize(
		DefaultReviveTriggerCapsuleRadius,
		DefaultReviveTriggerCapsuleHalfHeight);

	ReviveTriggerCapsuleComponent->SetSimulatePhysics(false);
	ReviveTriggerCapsuleComponent->SetKinematicPhysics(true);

	// Trigger는 물리 충돌이 아니라 Player overlap 감지만 해야 함.
	ReviveTriggerCapsuleComponent->SetGenerateOverlapEvents(true);
	ReviveTriggerCapsuleComponent->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	ReviveTriggerCapsuleComponent->SetCollisionObjectType(ECollisionChannel::Trigger);

	// 기본은 전부 무시.
	ReviveTriggerCapsuleComponent->SetCollisionResponseToAllChannels(ECollisionResponse::Ignore);

	// Pawn 채널만 overlap.
	// 현재 Player도 Pawn 채널일 가능성이 높아서 우선 이렇게 둠.
	ReviveTriggerCapsuleComponent->SetCollisionResponseToChannel(
		ECollisionChannel::Pawn,
		ECollisionResponse::Overlap);

	AttachGOIncSceneComponentsToRoot();
}

void AGOIncRagdollPawn::EnsureGOIncRootComponent()
{
	USceneComponent* CurrentRoot = GetRootComponent();
	if (GOIncRootComponent && CurrentRoot == GOIncRootComponent)
	{
		return;
	}

	if (CurrentRoot && Cast<UCapsuleComponent>(CurrentRoot) == nullptr)
	{
		GOIncRootComponent = CurrentRoot;
		return;
	}

	const FVector CurrentActorLocation = GetActorLocation();
	GOIncRootComponent = AddComponent<USceneComponent>();
	SetRootComponent(GOIncRootComponent);
	GOIncRootComponent->SetWorldLocation(CurrentActorLocation);

	UE_LOG("[GOIncRagdollPawn] Added GOIncRootComponent and migrated Capsule root at runtime.");
}

void AGOIncRagdollPawn::EnsureReviveTriggerCapsuleComponent()
{
	EnsureGOIncRootComponent();
	if (!CapsuleComponent)
	{
		return;
	}

	if (!ReviveTriggerCapsuleComponent)
	{
		for (UActorComponent* Component : GetComponents())
		{
			UCapsuleComponent* Candidate = Cast<UCapsuleComponent>(Component);
			if (Candidate && Candidate != CapsuleComponent)
			{
				ReviveTriggerCapsuleComponent = Candidate;
				break;
			}
		}
	}

	// Existing scene files will not have the new trigger component yet.
	// Create it at runtime so old scenes keep working without manual scene edits.
	if (!ReviveTriggerCapsuleComponent)
	{
		ReviveTriggerCapsuleComponent = AddComponent<UCapsuleComponent>();
		ConfigureReviveTriggerCapsuleDefaults();
		UE_LOG("[GOIncRagdollPawn] Added missing ReviveTriggerCapsuleComponent at runtime.");
	}
	AttachGOIncSceneComponentsToRoot();
}

void AGOIncRagdollPawn::AttachGOIncSceneComponentsToRoot()
{
	EnsureGOIncRootComponent();
	if (!GOIncRootComponent)
	{
		return;
	}

	if (CapsuleComponent && CapsuleComponent->GetParent() != GOIncRootComponent)
	{
		const FVector WorldLocation = CapsuleComponent->GetWorldLocation();
		CapsuleComponent->AttachToComponent(GOIncRootComponent);
		CapsuleComponent->SetWorldLocation(WorldLocation);
	}

	if (ReviveTriggerCapsuleComponent && ReviveTriggerCapsuleComponent->GetParent() != GOIncRootComponent)
	{
		const FVector WorldLocation = ReviveTriggerCapsuleComponent->GetWorldLocation();
		ReviveTriggerCapsuleComponent->AttachToComponent(GOIncRootComponent);
		ReviveTriggerCapsuleComponent->SetWorldLocation(WorldLocation);
	}

	if (Mesh && Mesh->GetParent() != GOIncRootComponent)
	{
		const FVector WorldLocation = Mesh->GetWorldLocation();
		Mesh->AttachToComponent(GOIncRootComponent);
		Mesh->SetWorldLocation(WorldLocation);
	}
}

void AGOIncRagdollPawn::ConfigureMovementUpdatedComponent()
{
	if (!RagdollMovementComponent)
	{
		return;
	}

	USceneComponent* MovementRoot = GOIncRootComponent ? GOIncRootComponent : GetRootComponent();
	if (!MovementRoot)
	{
		MovementRoot = CapsuleComponent;
	}

	RagdollMovementComponent->SetUpdatedComponent(MovementRoot);

	if (CapsuleComponent && MovementRoot)
	{
		FVector CapsuleLocalOffset = FVector(0.0f, 0.0f, 0.0f);
		if (CapsuleComponent->GetParent() == MovementRoot)
		{
			CapsuleLocalOffset = CapsuleComponent->GetRelativeLocation();
		}

		RagdollMovementComponent->SetMovementCollisionCapsule(
			CapsuleComponent->GetScaledCapsuleRadius(),
			CapsuleComponent->GetScaledCapsuleHalfHeight(),
			CapsuleLocalOffset);
	}
	else
	{
		RagdollMovementComponent->ClearMovementCollisionCapsule();
	}
}

void AGOIncRagdollPawn::ApplyInitialRagdollState()
{
	if (!Mesh || !Mesh->GetSkeletalMesh())
	{
		return;
	}

	Mesh->SetRagdollSelfCollisionMode(ERagdollSelfCollisionMode::DisableParentChild);
	Mesh->SetRagdollGravityEnabled(true);
	Mesh->SetRagdollEnabled(true);
	Mesh->WakeAllRagdollBodies();
}


void AGOIncRagdollPawn::SetAliveCollisionCapsuleEnabled(bool bEnabled)
{
	if (!CapsuleComponent)
	{
		return;
	}

	CapsuleComponent->SetSimulatePhysics(false);
	CapsuleComponent->SetKinematicPhysics(true);
	CapsuleComponent->SetGenerateOverlapEvents(false);
	CapsuleComponent->SetCollisionObjectType(ECollisionChannel::Pawn);
	CapsuleComponent->SetCollisionResponseToAllChannels(ECollisionResponse::Block);
	CapsuleComponent->SetCollisionResponseToChannel(ECollisionChannel::Trigger, ECollisionResponse::Ignore);

	if (bEnabled)
	{
		// 새 collision split 구조에서는 Alive capsule이 바닥/환경 충돌 기준이다.
		// 기존 Scene처럼 revive trigger와 alive capsule이 같은 경우에는 QueryOnly fallback을 유지한다.
		const bool bHasSeparateReviveTrigger = ReviveTriggerCapsuleComponent && ReviveTriggerCapsuleComponent != CapsuleComponent;
		CapsuleComponent->SetCollisionEnabled(bHasSeparateReviveTrigger
			? ECollisionEnabled::QueryAndPhysics
			: ECollisionEnabled::QueryOnly);
	}
	else
	{
		CapsuleComponent->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	}
}

void AGOIncRagdollPawn::SetReviveTriggerCapsuleEnabled(bool bEnabled)
{
	EnsureReviveTriggerCapsuleComponent();
	if (!ReviveTriggerCapsuleComponent)
	{
		return;
	}

	ReviveTriggerCapsuleComponent->SetSimulatePhysics(false);
	ReviveTriggerCapsuleComponent->SetKinematicPhysics(true);
	ReviveTriggerCapsuleComponent->SetGenerateOverlapEvents(bEnabled);

	if (bEnabled)
	{
		ReviveTriggerCapsuleComponent->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	}
	else
	{
		ReviveTriggerCapsuleComponent->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	}
}

void AGOIncRagdollPawn::SetMovementRuntimeEnabled(bool bEnabled, bool bUseFloorAndGravity)
{
	if (!RagdollMovementComponent)
	{
		return;
	}

	RagdollMovementComponent->StopMovementImmediately();
	RagdollMovementComponent->SetMovementEnabled(bEnabled);
	RagdollMovementComponent->SetFloorRaycastEnabled(bEnabled && bUseFloorAndGravity);
	RagdollMovementComponent->SetGravityEnabled(bEnabled && bUseFloorAndGravity);
}

bool AGOIncRagdollPawn::GetRagdollMeshSyncWorldLocation(FVector& OutLocation) const
{
	OutLocation = FVector::ZeroVector;
	if (!Mesh)
	{
		return false;
	}

	if (Mesh->GetRagdollComponentSyncWorldLocation(OutLocation))
	{
		return true;
	}

	// Fallback for assets that have not captured the component sync offset yet.
	return Mesh->GetRagdollBodyWorldLocation(FName("Pelvis"), OutLocation);
}

bool AGOIncRagdollPawn::ProjectAliveCapsuleLocationToGround(
	const FVector& ActorTargetLocation,
	float SourceZ,
	FVector& OutProjectedLocation) const
{
	OutProjectedLocation = ActorTargetLocation;

	UWorld* World = GetWorld();
	if (!World || !CapsuleComponent)
	{
		return false;
	}

	const float HalfHeight = CapsuleComponent->GetScaledCapsuleHalfHeight();
	if (HalfHeight <= 0.0f)
	{
		return false;
	}

	const FVector Start(ActorTargetLocation.X, ActorTargetLocation.Y, SourceZ + ReviveGroundTraceUp);
	const FVector Dir(0.0f, 0.0f, -1.0f);
	const float MaxDist = ReviveGroundTraceUp + ReviveGroundTraceDown;

	FHitResult Hit;
	if (!World->PhysicsRaycastByObjectTypes(
		Start,
		Dir,
		MaxDist,
		Hit,
		ObjectTypeBit(ECollisionChannel::WorldStatic),
		this))
	{
		return false;
	}

	OutProjectedLocation = FVector(
		ActorTargetLocation.X,
		ActorTargetLocation.Y,
		Hit.WorldHitLocation.Z + HalfHeight + ReviveGroundSkinWidth);
	return true;
}

void AGOIncRagdollPawn::ResyncMeshComponentToCurrentRagdollBodies()
{
	if (!Mesh)
	{
		return;
	}

	// GOIncRoot를 Dead 상태에서 따라가게 만들면 자식인 Mesh의 component transform도 같이 움직인다.
	// 하지만 Dead 상태의 실제 위치 주체는 ragdoll bodies이므로, component만 다시 body 기준 위치로 되돌린다.
	// 그 뒤 LastRagdollComponentWorldMatrix를 갱신해서 다음 SkeletalMesh tick에서 이 이동을
	// 외부 component move로 오인하고 ragdoll bodies를 밀어버리지 않게 한다.
	Mesh->ResyncComponentToRagdollBodiesAfterParentMove();
}

bool AGOIncRagdollPawn::UpdateDeadRootFromRagdollSafe()
{
	RefreshGOIncRagdollPawnComponents();
	if (!GOIncRootComponent || !CapsuleComponent || !Mesh)
	{
		return false;
	}

	FVector MeshSyncLocation;
	if (!GetRagdollMeshSyncWorldLocation(MeshSyncLocation))
	{
		return false;
	}

	// Dead 상태에서 Root는 ragdoll raw Z를 그대로 따라가면 안 된다.
	// XY만 ragdoll sync 위치를 따라가고, Z는 AliveCapsule이 바닥 위에 서는 안전 위치로 보정한다.
	FVector SafeRootLocation;
	if (!ProjectAliveCapsuleLocationToGround(MeshSyncLocation, MeshSyncLocation.Z, SafeRootLocation))
	{
		return false;
	}

	SetAliveCollisionCapsuleEnabled(false);
	SetActorLocation(SafeRootLocation);
	ResyncMeshComponentToCurrentRagdollBodies();

	if (ReviveTriggerCapsuleComponent && CapsuleComponent && ReviveTriggerCapsuleComponent != CapsuleComponent)
	{
		// Trigger는 GOIncRoot 자식으로 두고 AliveCapsule의 safe 위치와 같이 이동시킨다.
		// Player overlap 감지는 ragdoll raw 위치가 아니라 revive 가능한 capsule 위치 기준으로 처리한다.
		ReviveTriggerCapsuleComponent->SetRelativeLocation(CapsuleComponent->GetRelativeLocation());
	}

	ConfigureMovementUpdatedComponent();
	return true;
}

bool AGOIncRagdollPawn::PrepareReviveFromRagdoll()
{
	// Dead tick에서 이미 UpdateDeadRootFromRagdollSafe()가 Root를 따라오게 하지만,
	// Reviving 진입 순간에 한 번 더 검증/최종 보정을 수행한다.
	if (!UpdateDeadRootFromRagdollSafe())
	{
		UE_LOG("[GOIncRagdollPawn] PrepareReviveFromRagdoll failed. No valid ragdoll ground sync.");
		return false;
	}

	// Collision stays off during Reviving; this move only prepares a safe AliveCapsule location.
	SetAliveCollisionCapsuleEnabled(false);
	SetReviveTriggerCapsuleEnabled(false);
	ResyncMeshComponentToCurrentRagdollBodies();
	return true;
}

void AGOIncRagdollPawn::EnterDeadRagdollState()
{
	RefreshGOIncRagdollPawnComponents();

	SetMovementRuntimeEnabled(false, false);
	SetAliveCollisionCapsuleEnabled(false);
	SetReviveTriggerCapsuleEnabled(true);

	if (Mesh)
	{
		Mesh->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
		Mesh->SetRagdollGravityEnabled(true);

		// Alive/Flee 중 마지막 animation pose 기준으로 ragdoll body가 시작되게 ragdoll을 먼저 켠다.
		Mesh->SetRagdollEnabled(true);
		Mesh->SetAllBodiesSimulatePhysics(true);
		Mesh->SetAllBodiesPhysicsBlendWeight(1.0f);
		Mesh->WakeAllRagdollBodies();
	}

	StopFleeAnimation();
}

void AGOIncRagdollPawn::EnterRevivingState()
{
	RefreshGOIncRagdollPawnComponents();

	SetMovementRuntimeEnabled(false, false);
	SetReviveTriggerCapsuleEnabled(false);
	SetAliveCollisionCapsuleEnabled(false);

	// 목표 animation pose가 있어야 recovery가 ragdoll pose -> animation pose로 보간된다.
	PlayFleeAnimation();

	if (Mesh)
	{
		// SetRagdollEnabled(false) 내부 recovery가 현재 ragdoll pose를 잡도록 둔다.
		Mesh->SetRagdollGravityEnabled(false);
		Mesh->SetRagdollEnabled(false);
		Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	}
}

void AGOIncRagdollPawn::EnterAliveFleeState()
{
	RefreshGOIncRagdollPawnComponents();

	if (Mesh)
	{
		// Recovery 완료 후 Mesh는 animation only 표현 담당으로 둔다.
		Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	}

	SetReviveTriggerCapsuleEnabled(false);
	SetAliveCollisionCapsuleEnabled(true);
	SetMovementRuntimeEnabled(true, true);
}

void AGOIncRagdollPawn::RefreshGOIncRagdollPawnComponents()
{
	USceneComponent* CurrentRoot = GetRootComponent();
	GOIncRootComponent = CurrentRoot && Cast<UCapsuleComponent>(CurrentRoot) == nullptr
		? CurrentRoot
		: GOIncRootComponent;

	CapsuleComponent = nullptr;
	ReviveTriggerCapsuleComponent = nullptr;
	Mesh = GetComponentByClass<USkeletalMeshComponent>();
	RagdollMovementComponent = GetComponentByClass<UGOIncRagdollMovementComponent>();
	LuaScriptComponent = GetComponentByClass<ULuaScriptComponent>();

	for (UActorComponent* Component : GetComponents())
	{
		UCapsuleComponent* Candidate = Cast<UCapsuleComponent>(Component);
		if (!Candidate)
		{
			continue;
		}

		if (!CapsuleComponent && Candidate == CurrentRoot)
		{
			CapsuleComponent = Candidate;
			continue;
		}

		if (!CapsuleComponent && Candidate->GetCollisionObjectType() == ECollisionChannel::Pawn)
		{
			CapsuleComponent = Candidate;
			continue;
		}

		if (!ReviveTriggerCapsuleComponent && Candidate->GetCollisionObjectType() == ECollisionChannel::Trigger)
		{
			ReviveTriggerCapsuleComponent = Candidate;
		}
	}

	if (!CapsuleComponent)
	{
		CapsuleComponent = GetComponentByClass<UCapsuleComponent>();
	}

	EnsureGOIncRootComponent();
	EnsureReviveTriggerCapsuleComponent();
	AttachGOIncSceneComponentsToRoot();
	ConfigureMovementUpdatedComponent();
}

void AGOIncRagdollPawn::SetRagdollId(const FString& InRagdollId)
{
	RagdollId = InRagdollId.empty() ? FString("blue-speedster") : InRagdollId;
}

void AGOIncRagdollPawn::RequestDeadRagdoll(const FString& Reason)
{
	RefreshGOIncRagdollPawnComponents();
	if (!LuaScriptComponent)
	{
		UE_LOG("[GOIncRagdollPawn] RequestDeadRagdoll ignored. Missing LuaScriptComponent. Reason: %s", Reason.c_str());
		return;
	}

	const FString SafeReason = Reason.empty() ? FString("ExternalRequest") : Reason;
	if (!LuaScriptComponent->CallFunctionString("RequestDeadRagdoll", SafeReason))
	{
		UE_LOG("[GOIncRagdollPawn] Lua RequestDeadRagdoll handler missing or failed. Reason: %s", SafeReason.c_str());
	}
}

void AGOIncRagdollPawn::SetSkeletalMeshPath(const FString& InSkeletalMeshPath)
{
	SkeletalMeshPath = InSkeletalMeshPath;
	if (!Mesh || SkeletalMeshPath.empty() || !GEngine)
	{
		return;
	}

	ID3D11Device* Device = GEngine->GetRenderer().GetFD3DDevice().GetDevice();
	USkeletalMesh* Asset = FMeshManager::LoadSkeletalMesh(SkeletalMeshPath, Device);
	if (!Asset)
	{
		UE_LOG("[GOIncRagdollPawn] Failed to load skeletal mesh: %s", SkeletalMeshPath.c_str());
		return;
	}

	Mesh->SetSkeletalMesh(Asset);
}

void AGOIncRagdollPawn::SetFleeAnimationPath(const FString& InFleeAnimationPath)
{
	FleeAnimationPath = InFleeAnimationPath;
}

void AGOIncRagdollPawn::SetMeshRelativeLocation(const FVector& InRelativeLocation)
{
	if (Mesh)
	{
		Mesh->SetRelativeLocation(InRelativeLocation);
	}
}

void AGOIncRagdollPawn::SetMeshRelativeScale(const FVector& InRelativeScale)
{
	if (Mesh)
	{
		Mesh->SetRelativeScale(InRelativeScale);
	}
}

void AGOIncRagdollPawn::SetAliveCapsuleSize(float Radius, float HalfHeight)
{
	if (CapsuleComponent)
	{
		CapsuleComponent->SetCapsuleSize(Radius, HalfHeight);
	}
	ConfigureMovementUpdatedComponent();
}

void AGOIncRagdollPawn::SetReviveTriggerCapsuleSize(float Radius, float HalfHeight)
{
	EnsureReviveTriggerCapsuleComponent();
	if (ReviveTriggerCapsuleComponent)
	{
		ReviveTriggerCapsuleComponent->SetCapsuleSize(Radius, HalfHeight);
	}
}

void AGOIncRagdollPawn::BeginPlay()
{
	RefreshGOIncRagdollPawnComponents();
	Super::BeginPlay();
}

void AGOIncRagdollPawn::PostDuplicate()
{
	Super::PostDuplicate();
	RefreshGOIncRagdollPawnComponents();
}

void AGOIncRagdollPawn::PlayFleeAnimation()
{
	if (!Mesh) return;

	const FString& AnimationPath = FleeAnimationPath.empty()
		? DefaultGOIncRagdollRunAnimationFileName
		: FleeAnimationPath;

	UAnimSequenceBase* RunAnim = FAnimationManager::Get().LoadAnimation(AnimationPath);

	if (!RunAnim)
	{
		UE_LOG("[GOIncRagdollPawn] Failed to load flee animation: %s",
			AnimationPath.c_str());
		return;
	}

	Mesh->PlayAnimation(RunAnim, true);
}

void AGOIncRagdollPawn::StopFleeAnimation()
{
	if (!Mesh) return;

	Mesh->StopAnimation();
}

void AGOIncRagdollPawn::OnOwnedComponentRemoved(UActorComponent* Component)
{
	Super::OnOwnedComponentRemoved(Component);
	if (Component == GOIncRootComponent)
	{
		GOIncRootComponent = nullptr;
	}
	if (Component == CapsuleComponent)
	{
		CapsuleComponent = nullptr;
	}
	if (Component == ReviveTriggerCapsuleComponent)
	{
		ReviveTriggerCapsuleComponent = nullptr;
	}
	if (Component == Mesh)
	{
		Mesh = nullptr;
	}
	if (Component == RagdollMovementComponent)
	{
		RagdollMovementComponent = nullptr;
	}
	if (Component == LuaScriptComponent)
	{
		LuaScriptComponent = nullptr;
	}
}
