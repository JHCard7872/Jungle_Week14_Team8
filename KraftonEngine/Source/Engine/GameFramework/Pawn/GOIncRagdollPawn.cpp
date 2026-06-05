#include "GameFramework/Pawn/GOIncRagdollPawn.h"

#include "Animation/AnimationManager.h"
#include "Component/Movement/GOIncRagdollMovementComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Component/Script/LuaScriptComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "Core/Logging/Log.h"
#include "Mesh/MeshManager.h"
#include "Runtime/Engine.h"

namespace
{
	const FString DefaultGOIncRagdollSkeletalMeshFileName = "Content/Data/Sonic/sc_dash_loop_anm_hkx_SkeletalMesh.uasset";
	const FString DefaultGOIncRagdollLuaScriptFileName = "GOIncRagdollPawn_Test.lua";
	const FString DefaultGOIncRagdollRunAnimationFileName = "Content/Data/Sonic/sc_dash_loop_anm_hkx_sc_dash_loop.uasset";
}

void AGOIncRagdollPawn::InitDefaultComponents()
{
	InitDefaultComponents(DefaultGOIncRagdollSkeletalMeshFileName, DefaultGOIncRagdollLuaScriptFileName);
}

void AGOIncRagdollPawn::InitDefaultComponents(const FString& SkeletalMeshFileName, const FString& ScriptFile)
{
	// NPC Pawn이므로 PlayerController 자동 possess 대상이 되지 않게 둔다.
	SetAutoPossessPlayer(false);

	// 1) Capsule — Root. 살아있는 상태에서 UGOIncRagdollMovementComponent의 UpdatedComponent가 된다.
	CapsuleComponent = AddComponent<UCapsuleComponent>();
	SetRootComponent(CapsuleComponent);

	// 2) SkeletalMesh — Capsule의 자식. Animation/ragdoll 표현 담당.
	Mesh = AddComponent<USkeletalMeshComponent>();
	Mesh->AttachToComponent(CapsuleComponent);

	const FString SelectedSkeletalMeshFileName = SkeletalMeshFileName.empty()
		? DefaultGOIncRagdollSkeletalMeshFileName
		: SkeletalMeshFileName;

	if (!SelectedSkeletalMeshFileName.empty() && GEngine)
	{
		ID3D11Device* Device = GEngine->GetRenderer().GetFD3DDevice().GetDevice();
		USkeletalMesh* Asset = FMeshManager::LoadSkeletalMesh(SelectedSkeletalMeshFileName, Device);
		Mesh->SetSkeletalMesh(Asset);
	}

	ApplyInitialRagdollState();

	// 3) GOIncRagdollMovement — non-scene. UpdatedComponent만 직접 이동한다.
	RagdollMovementComponent = AddComponent<UGOIncRagdollMovementComponent>();
	RagdollMovementComponent->SetUpdatedComponent(CapsuleComponent);

	// 4) LuaScript — 상태 판단/컴포넌트 API 조합은 Lua에서 처리한다.
	LuaScriptComponent = AddComponent<ULuaScriptComponent>();
	if (!ScriptFile.empty())
	{
		LuaScriptComponent->SetScriptFile(ScriptFile);
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
	Mesh = GetComponentByClass<USkeletalMeshComponent>();
	RagdollMovementComponent = GetComponentByClass<UGOIncRagdollMovementComponent>();
	LuaScriptComponent = GetComponentByClass<ULuaScriptComponent>();

	if (RagdollMovementComponent && CapsuleComponent)
	{
		RagdollMovementComponent->SetUpdatedComponent(CapsuleComponent);
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

	UAnimSequenceBase* RunAnim = FAnimationManager::Get().LoadAnimation(DefaultGOIncRagdollRunAnimationFileName);

	if (!RunAnim)
	{
		UE_LOG("[GOIncRagdollPawn] Failed to load flee animation: %s",
			DefaultGOIncRagdollRunAnimationFileName.c_str());
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
