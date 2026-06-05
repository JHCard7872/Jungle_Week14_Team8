#include "GameFramework/Pawn/GOIncRagdollPawn.h"

#include "Animation/AnimationManager.h"
#include "Component/Movement/GOIncRagdollMovementComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Component/Script/LuaScriptComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "Core/Logging/Log.h"
#include "Core/Types/CollisionTypes.h"
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

	// 1) Capsule — Root. Alive 상태에서 UGOIncRagdollMovementComponent의 UpdatedComponent가 된다.
	// Dead 상태에서는 Lua가 이 Capsule collision을 끄고, ragdoll sync 위치로 Root를 이동시킨다.
	CapsuleComponent = AddComponent<UCapsuleComponent>();
	SetRootComponent(CapsuleComponent);
	ConfigureAliveCollisionCapsuleDefaults();

	// 2) ReviveTriggerCapsule — Capsule의 자식. DeadRagdoll 상태에서 Player overlap revive 감지만 담당한다.
	ReviveTriggerCapsuleComponent = AddComponent<UCapsuleComponent>();
	ReviveTriggerCapsuleComponent->AttachToComponent(CapsuleComponent);
	ConfigureReviveTriggerCapsuleDefaults();

	// 3) SkeletalMesh — Capsule의 자식. Animation/ragdoll 표현 담당.
	Mesh = AddComponent<USkeletalMeshComponent>();
	Mesh->AttachToComponent(CapsuleComponent);

	SkeletalMeshPath = SkeletalMeshFileName.empty()
		? DefaultGOIncRagdollSkeletalMeshFileName
		: SkeletalMeshFileName;
	FleeAnimationPath = DefaultGOIncRagdollRunAnimationFileName;

	SetSkeletalMeshPath(SkeletalMeshPath);

	ApplyInitialRagdollState();

	// 4) GOIncRagdollMovement — non-scene. Alive collision capsule만 직접 이동한다.
	RagdollMovementComponent = AddComponent<UGOIncRagdollMovementComponent>();
	RagdollMovementComponent->SetUpdatedComponent(CapsuleComponent);

	// 5) LuaScript — 상태 판단/컴포넌트 API 조합은 Lua에서 처리한다.
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

	if (CapsuleComponent && ReviveTriggerCapsuleComponent->GetParent() != CapsuleComponent)
	{
		ReviveTriggerCapsuleComponent->AttachToComponent(CapsuleComponent);
	}
}

void AGOIncRagdollPawn::EnsureReviveTriggerCapsuleComponent()
{
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
	else if (ReviveTriggerCapsuleComponent->GetParent() != CapsuleComponent)
	{
		ReviveTriggerCapsuleComponent->AttachToComponent(CapsuleComponent);
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

void AGOIncRagdollPawn::RefreshGOIncRagdollPawnComponents()
{
	CapsuleComponent = Cast<UCapsuleComponent>(GetRootComponent());
	ReviveTriggerCapsuleComponent = nullptr;
	EnsureReviveTriggerCapsuleComponent();

	Mesh = GetComponentByClass<USkeletalMeshComponent>();
	RagdollMovementComponent = GetComponentByClass<UGOIncRagdollMovementComponent>();
	LuaScriptComponent = GetComponentByClass<ULuaScriptComponent>();

	if (RagdollMovementComponent && CapsuleComponent)
	{
		RagdollMovementComponent->SetUpdatedComponent(CapsuleComponent);
	}
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
