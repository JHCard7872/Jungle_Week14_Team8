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
#include "Mesh/Skeletal/SkeletalMesh.h"
#include "PhysicsEngine/PhysicsAssetManager.h"
#include "Runtime/Engine.h"

#include <cstring>

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

	void ConfigureDeadRagdollMeshCollisionForGOInc(USkeletalMeshComponent* Mesh)
	{
		if (!Mesh)
		{
			return;
		}

		// Dead ragdoll bodies still need to collide with the floor/world and be queryable by the beam.
		// AliveFlee movement now uses the Alive Capsule as the physical collision shape,
		// so dead ragdolls must block Pawn-channel sweeps instead of letting revived NPCs pass through them.
		Mesh->SetCollisionObjectType(ECollisionChannel::WorldDynamic);
		Mesh->SetCollisionResponseToAllChannels(ECollisionResponse::Block);
		Mesh->SetCollisionResponseToChannel(ECollisionChannel::Pawn, ECollisionResponse::Block);
	}

	void ConfigureAliveCollisionCapsuleCollisionForGOInc(UCapsuleComponent* Capsule)
	{
		if (!Capsule)
		{
			return;
		}

		Capsule->SetSimulatePhysics(false);
		Capsule->SetKinematicPhysics(true);
		Capsule->SetGenerateOverlapEvents(false);
		Capsule->SetCollisionObjectType(ECollisionChannel::Pawn);
		Capsule->SetCollisionResponseToAllChannels(ECollisionResponse::Block);
		Capsule->SetCollisionResponseToChannel(ECollisionChannel::Trigger, ECollisionResponse::Ignore);
		// Alive Capsule is the moving physical body for AliveFlee, so it should push against
		// other GOInc ragdolls / alive capsules instead of ghosting through them.
		Capsule->SetCollisionResponseToChannel(ECollisionChannel::Pawn, ECollisionResponse::Block);
	}

	void ConfigureReviveTriggerCapsuleCollisionForGOInc(UCapsuleComponent* TriggerCapsule)
	{
		if (!TriggerCapsule)
		{
			return;
		}

		TriggerCapsule->SetSimulatePhysics(false);
		TriggerCapsule->SetKinematicPhysics(true);
		TriggerCapsule->SetCollisionObjectType(ECollisionChannel::Trigger);
		TriggerCapsule->SetCollisionResponseToAllChannels(ECollisionResponse::Ignore);
		TriggerCapsule->SetCollisionResponseToChannel(ECollisionChannel::Pawn, ECollisionResponse::Overlap);
	}
}

void AGOIncRagdollPawn::InitDefaultComponents()
{
	EnsureDefaultComponents();
	RefreshCharacterConfig();
	ApplyInitialRagdollState();
}

void AGOIncRagdollPawn::InitDefaultComponents(const FString& SkeletalMeshFileName, const FString& ScriptFile)
{
	EnsureDefaultComponents();

	FGOIncRagdollCharacterConfig Config = MakeCharacterConfig();

	if (!SkeletalMeshFileName.empty())
	{
		Config.SkeletalMeshPath.SetPath(SkeletalMeshFileName);
	}

	Config.LuaScriptFile = ScriptFile;

	ApplyCharacterConfig(Config);
	ApplyInitialRagdollState();
}

void AGOIncRagdollPawn::EnsureDefaultComponents()
{
	AddTag(FName("Ragdoll"));
	// NPC Pawn이므로 PlayerController 자동 possess 대상이 되지 않게 둔다.
	SetAutoPossessPlayer(false);

	RefreshGOIncRagdollPawnComponents();
	EnsureGOIncRootComponent();

	const bool bCreatedAliveCapsule = CapsuleComponent == nullptr;
	if (bCreatedAliveCapsule)
	{
		CapsuleComponent = AddComponent<UCapsuleComponent>();
		CapsuleComponent->AttachToComponent(GOIncRootComponent);
		CapsuleComponent->SetRelativeLocation(FVector(0.0f, 0.0f, 0.0f));
		ConfigureAliveCollisionCapsuleDefaults();
	}

	const bool bCreatedReviveTriggerCapsule = ReviveTriggerCapsuleComponent == nullptr;
	if (bCreatedReviveTriggerCapsule)
	{
		ReviveTriggerCapsuleComponent = AddComponent<UCapsuleComponent>();
		ReviveTriggerCapsuleComponent->AttachToComponent(GOIncRootComponent);
		ReviveTriggerCapsuleComponent->SetRelativeLocation(FVector(0.0f, 0.0f, 0.0f));
		ConfigureReviveTriggerCapsuleDefaults();
	}

	if (!Mesh)
	{
		Mesh = AddComponent<USkeletalMeshComponent>();
		Mesh->AttachToComponent(GOIncRootComponent);
	}

	if (!RagdollMovementComponent)
	{
		// GOIncRagdollMovement — non-scene. Root를 이동시키되, sweep shape는 AliveCapsule 값으로 사용한다.
		RagdollMovementComponent = AddComponent<UGOIncRagdollMovementComponent>();
	}

	if (!LuaScriptComponent)
	{
		// LuaScript — 상태 판단/컴포넌트 API 조합은 Lua에서 처리한다.
		LuaScriptComponent = AddComponent<ULuaScriptComponent>();
	}

	AttachGOIncSceneComponentsToRoot();
	ConfigureMovementUpdatedComponent();
}

FGOIncRagdollCharacterConfig AGOIncRagdollPawn::MakeCharacterConfig() const
{
	FGOIncRagdollCharacterConfig Config;

	// 기존 SpawnRagdollPawn 경로는 SetRagdollId()를 InitDefaultComponents()보다 먼저 호출한다.
	// 1차 리팩토링에서는 그 값을 Sonic 기본 id로 덮어쓰지 않도록 보존한다.
	if (!RagdollId.empty())
	{
		Config.RagdollId = RagdollId;
		if (RagdollId != "blue-speedster")
		{
			Config.DisplayName = RagdollId;
		}
	}

	if (!SkeletalMeshPath.empty())
	{
		Config.SkeletalMeshPath = SkeletalMeshPath;
	}
	if (!PhysicsAssetPath.empty())
	{
		Config.PhysicsAssetPath = PhysicsAssetPath;
	}
	if (!FleeAnimationPath.empty())
	{
		Config.FleeAnimationPath = FleeAnimationPath;
	}

	return Config;
}

void AGOIncRagdollPawn::ApplyCharacterConfig(const FGOIncRagdollCharacterConfig& InCharacterConfig)
{
	CharacterConfig = InCharacterConfig;

	SetRagdollId(CharacterConfig.RagdollId);
	SetPhysicsAssetPath(CharacterConfig.PhysicsAssetPath);
	SetSkeletalMeshPath(CharacterConfig.SkeletalMeshPath);
	SetFleeAnimationPath(CharacterConfig.FleeAnimationPath);
	SetMeshRelativeLocation(CharacterConfig.MeshRelativeLocation);
	SetMeshRelativeScale(CharacterConfig.MeshRelativeScale);
	SetAliveCapsuleSize(CharacterConfig.AliveCapsuleRadius, CharacterConfig.AliveCapsuleHalfHeight);
	SetReviveTriggerCapsuleSize(CharacterConfig.ReviveTriggerCapsuleRadius, CharacterConfig.ReviveTriggerCapsuleHalfHeight);

	if (RagdollMovementComponent)
	{
		RagdollMovementComponent->SetMaxSpeed(CharacterConfig.FleeSpeed);
		RagdollMovementComponent->SetAcceleration(CharacterConfig.FleeAcceleration);
		RagdollMovementComponent->SetBrakingDeceleration(CharacterConfig.FleeBrakingDeceleration);
	}

	if (LuaScriptComponent && !CharacterConfig.LuaScriptFile.empty())
	{
		LuaScriptComponent->SetScriptFile(CharacterConfig.LuaScriptFile);
	}
}

void AGOIncRagdollPawn::RefreshCharacterConfig()
{
	EnsureDefaultComponents();
	ApplyCharacterConfig(bUseEditableCharacterConfig ? CharacterConfig : MakeCharacterConfig());
}

void AGOIncRagdollPawn::ApplyEditableCharacterConfig()
{
	bUseEditableCharacterConfig = true;
	EnsureDefaultComponents();
	ApplyCharacterConfig(CharacterConfig);
}

void AGOIncRagdollPawn::ResetCharacterConfigToClassDefaults()
{
	bUseEditableCharacterConfig = false;
	EnsureDefaultComponents();
	ApplyCharacterConfig(MakeCharacterConfig());
}

void AGOIncRagdollPawn::SetUseEditableCharacterConfig(bool bEnabled)
{
	bUseEditableCharacterConfig = bEnabled;
	RefreshCharacterConfig();
}

bool AGOIncRagdollPawn::IsCharacterConfigPropertyName(const char* PropertyName) const
{
	if (!PropertyName || PropertyName[0] == '\0')
	{
		return false;
	}

	return std::strcmp(PropertyName, "CharacterConfig") == 0
		|| std::strcmp(PropertyName, "RagdollId") == 0
		|| std::strcmp(PropertyName, "DisplayName") == 0
		|| std::strcmp(PropertyName, "SkeletalMeshPath") == 0
		|| std::strcmp(PropertyName, "PhysicsAssetPath") == 0
		|| std::strcmp(PropertyName, "FleeAnimationPath") == 0
		|| std::strcmp(PropertyName, "LuaScriptFile") == 0
		|| std::strcmp(PropertyName, "MeshRelativeLocation") == 0
		|| std::strcmp(PropertyName, "MeshRelativeScale") == 0
		|| std::strcmp(PropertyName, "AliveCapsuleRadius") == 0
		|| std::strcmp(PropertyName, "AliveCapsuleHalfHeight") == 0
		|| std::strcmp(PropertyName, "ReviveTriggerCapsuleRadius") == 0
		|| std::strcmp(PropertyName, "ReviveTriggerCapsuleHalfHeight") == 0
		|| std::strcmp(PropertyName, "bCanRevive") == 0
		|| std::strcmp(PropertyName, "ReviveBlendDuration") == 0
		|| std::strcmp(PropertyName, "FleeSpeed") == 0
		|| std::strcmp(PropertyName, "FleeAcceleration") == 0
		|| std::strcmp(PropertyName, "FleeBrakingDeceleration") == 0
		|| std::strcmp(PropertyName, "FleeEndDistance") == 0
		|| std::strcmp(PropertyName, "FleeStopDuration") == 0
		|| std::strcmp(PropertyName, "FleeStopMinBrakingDeceleration") == 0
		|| std::strcmp(PropertyName, "FleeRotationYawOffsetDegrees") == 0
		|| std::strcmp(PropertyName, "FleeAnimationBaseSpeed") == 0
		|| std::strcmp(PropertyName, "FleeAnimationMinPlayRate") == 0
		|| std::strcmp(PropertyName, "FleeAnimationMaxPlayRate") == 0
		|| std::strcmp(PropertyName, "FleeStopStartPlayRate") == 0
		|| std::strcmp(PropertyName, "FleeStopEndPlayRate") == 0;
}

void AGOIncRagdollPawn::ConfigureAliveCollisionCapsuleDefaults()
{
	if (!CapsuleComponent)
	{
		return;
	}

	CapsuleComponent->SetCapsuleSize(DefaultAliveCapsuleRadius, DefaultAliveCapsuleHalfHeight);
	ConfigureAliveCollisionCapsuleCollisionForGOInc(CapsuleComponent);
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

	ConfigureReviveTriggerCapsuleCollisionForGOInc(ReviveTriggerCapsuleComponent);

	// Trigger는 물리 충돌이 아니라 Player overlap 감지만 해야 함.
	ReviveTriggerCapsuleComponent->SetGenerateOverlapEvents(true);
	ReviveTriggerCapsuleComponent->SetCollisionEnabled(ECollisionEnabled::QueryOnly);

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

	// Scene-authored capsules may have been saved as a plain CapsuleComponent.
	// Once we select one as ReviveTrigger, always re-assert its trigger role.
	ConfigureReviveTriggerCapsuleCollisionForGOInc(ReviveTriggerCapsuleComponent);
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

	ConfigureDeadRagdollMeshCollisionForGOInc(Mesh);
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

	ConfigureAliveCollisionCapsuleCollisionForGOInc(CapsuleComponent);

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

	ConfigureReviveTriggerCapsuleCollisionForGOInc(ReviveTriggerCapsuleComponent);
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

void AGOIncRagdollPawn::ForceDeadRagdollPhysicsEnabled()
{
	RefreshGOIncRagdollPawnComponents();

	if (!Mesh)
	{
		UE_LOG("[GOIncRagdollPawn] ForceDeadRagdollPhysicsEnabled failed. Missing RagdollMeshComponent.");
		return;
	}

	ConfigureDeadRagdollMeshCollisionForGOInc(Mesh);
	Mesh->SetSimulatePhysics(true);
	Mesh->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	Mesh->SetRagdollGravityEnabled(true);
	Mesh->SetRagdollEnabled(true);
	Mesh->SetAllBodiesSimulatePhysics(true);
	Mesh->SetAllBodiesPhysicsBlendWeight(1.0f);
	Mesh->WakeAllRagdollBodies();
	Mesh->ResyncComponentToRagdollBodiesAfterParentMove();
}

void AGOIncRagdollPawn::ForceAliveAnimationPhysicsDisabled()
{
	RefreshGOIncRagdollPawnComponents();

	if (!Mesh)
	{
		return;
	}

	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Mesh->SetRagdollGravityEnabled(false);
	Mesh->SetAllBodiesPhysicsBlendWeight(0.0f);
	Mesh->SetAllBodiesSimulatePhysics(false);
	Mesh->SetRagdollEnabled(false);
	// Mesh->SetSimulatePhysics(false);
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

	StopFleeAnimation();
	ForceDeadRagdollPhysicsEnabled();
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
		Mesh->SetSimulatePhysics(false);
	}
}

void AGOIncRagdollPawn::EnterAliveFleeState()
{
	RefreshGOIncRagdollPawnComponents();

	SetReviveTriggerCapsuleEnabled(false);
	SetAliveCollisionCapsuleEnabled(true);
	ForceAliveAnimationPhysicsDisabled();
	PlayFleeAnimation();
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
	if (CapsuleComponent)
	{
		ConfigureAliveCollisionCapsuleCollisionForGOInc(CapsuleComponent);
	}
	EnsureReviveTriggerCapsuleComponent();
	AttachGOIncSceneComponentsToRoot();
	ConfigureMovementUpdatedComponent();
}

void AGOIncRagdollPawn::SetRagdollId(const FString& InRagdollId)
{
	RagdollId = InRagdollId.empty() ? FString("blue-speedster") : InRagdollId;
	CharacterConfig.RagdollId = RagdollId;
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
	CharacterConfig.SkeletalMeshPath = SkeletalMeshPath;
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

	if (!PhysicsAssetPath.empty() && PhysicsAssetPath != "None")
	{
		if (UPhysicsAsset* PhysicsAsset = FPhysicsAssetManager::Get().Load(PhysicsAssetPath, Asset))
		{
			Asset->SetPhysicsAsset(PhysicsAsset);
		}
		else
		{
			Asset->SetPhysicsAssetPath(PhysicsAssetPath);
			UE_LOG("[GOIncRagdollPawn] Failed to load physics asset: %s", PhysicsAssetPath.c_str());
		}
	}

	Mesh->SetSkeletalMesh(Asset);
}

void AGOIncRagdollPawn::SetPhysicsAssetPath(const FString& InPhysicsAssetPath)
{
	PhysicsAssetPath = InPhysicsAssetPath;
	CharacterConfig.PhysicsAssetPath = PhysicsAssetPath;
	if (!Mesh || !Mesh->GetSkeletalMesh() || PhysicsAssetPath.empty() || PhysicsAssetPath == "None")
	{
		return;
	}

	USkeletalMesh* CurrentMesh = Mesh->GetSkeletalMesh();
	if (UPhysicsAsset* PhysicsAsset = FPhysicsAssetManager::Get().Load(PhysicsAssetPath, CurrentMesh))
	{
		CurrentMesh->SetPhysicsAsset(PhysicsAsset);
	}
	else
	{
		CurrentMesh->SetPhysicsAssetPath(PhysicsAssetPath);
		UE_LOG("[GOIncRagdollPawn] Failed to load physics asset: %s", PhysicsAssetPath.c_str());
	}
}

void AGOIncRagdollPawn::SetFleeAnimationPath(const FString& InFleeAnimationPath)
{
	FleeAnimationPath = InFleeAnimationPath;
	CharacterConfig.FleeAnimationPath = FleeAnimationPath;
}

void AGOIncRagdollPawn::SetMeshRelativeLocation(const FVector& InRelativeLocation)
{
	CharacterConfig.MeshRelativeLocation = InRelativeLocation;
	if (Mesh)
	{
		Mesh->SetRelativeLocation(InRelativeLocation);
	}
}

void AGOIncRagdollPawn::SetMeshRelativeScale(const FVector& InRelativeScale)
{
	CharacterConfig.MeshRelativeScale = InRelativeScale;
	if (Mesh)
	{
		Mesh->SetRelativeScale(InRelativeScale);
	}
}

void AGOIncRagdollPawn::SetAliveCapsuleSize(float Radius, float HalfHeight)
{
	CharacterConfig.AliveCapsuleRadius = Radius;
	CharacterConfig.AliveCapsuleHalfHeight = HalfHeight;
	if (CapsuleComponent)
	{
		CapsuleComponent->SetCapsuleSize(Radius, HalfHeight);
	}
	ConfigureMovementUpdatedComponent();
}

void AGOIncRagdollPawn::SetReviveTriggerCapsuleSize(float Radius, float HalfHeight)
{
	CharacterConfig.ReviveTriggerCapsuleRadius = Radius;
	CharacterConfig.ReviveTriggerCapsuleHalfHeight = HalfHeight;
	EnsureReviveTriggerCapsuleComponent();
	if (ReviveTriggerCapsuleComponent)
	{
		ReviveTriggerCapsuleComponent->SetCapsuleSize(Radius, HalfHeight);
	}
}

void AGOIncRagdollPawn::BeginPlay()
{
	EnsureDefaultComponents();
	RefreshCharacterConfig();
	ApplyInitialRagdollState();
	RefreshGOIncRagdollPawnComponents();
	Super::BeginPlay();
}

void AGOIncRagdollPawn::PostDuplicate()
{
	Super::PostDuplicate();
	EnsureDefaultComponents();
	RefreshCharacterConfig();
	RefreshGOIncRagdollPawnComponents();
}

void AGOIncRagdollPawn::PostEditProperty(const char* PropertyName)
{
	Super::PostEditProperty(PropertyName);
	if (!PropertyName)
	{
		return;
	}

	if (IsCharacterConfigPropertyName(PropertyName))
	{
		ApplyEditableCharacterConfig();
		return;
	}

	if (std::strcmp(PropertyName, "bUseEditableCharacterConfig") == 0
		|| std::strcmp(PropertyName, "Use Editable Character Config") == 0)
	{
		RefreshCharacterConfig();
	}
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
