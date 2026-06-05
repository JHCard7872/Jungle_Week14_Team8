#include "GameFramework/Pawn/RespawnRagdollPawn.h"

#include "Component/Movement/PawnMovementComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Component/Script/LuaScriptComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "Mesh/MeshManager.h"
#include "Runtime/Engine.h"

void ARespawnRagdollPawn::InitDefaultComponents()
{
	InitDefaultComponents(FString(), FString());
}

void ARespawnRagdollPawn::InitDefaultComponents(const FString& SkeletalMeshFileName, const FString& ScriptFile)
{
	// NPC Pawn이므로 PlayerController 자동 possess 대상이 되지 않게 둔다.
	SetAutoPossessPlayer(false);

	// 1) Capsule — Root. 살아있는 상태에서 PawnMovementComponent의 UpdatedComponent가 된다.
	CapsuleComponent = AddComponent<UCapsuleComponent>();
	SetRootComponent(CapsuleComponent);

	// 2) SkeletalMesh — Capsule의 자식. Animation/ragdoll 표현 담당.
	Mesh = AddComponent<USkeletalMeshComponent>();
	Mesh->AttachToComponent(CapsuleComponent);

	if (!SkeletalMeshFileName.empty())
	{
		ID3D11Device* Device = GEngine->GetRenderer().GetFD3DDevice().GetDevice();
		USkeletalMesh* Asset = FMeshManager::LoadSkeletalMesh(SkeletalMeshFileName, Device);
		Mesh->SetSkeletalMesh(Asset);
	}

	// 3) PawnMovement — non-scene. 실제 이동 로직은 후속 패치에서 확장한다.
	PawnMovementComponent = AddComponent<UPawnMovementComponent>();
	PawnMovementComponent->SetUpdatedComponent(CapsuleComponent);

	// 4) LuaScript — 상태 판단/컴포넌트 API 조합은 Lua에서 처리한다.
	LuaScriptComponent = AddComponent<ULuaScriptComponent>();
	if (!ScriptFile.empty())
	{
		LuaScriptComponent->SetScriptFile(ScriptFile);
	}
}

void ARespawnRagdollPawn::RefreshRespawnRagdollPawnComponents()
{
	CapsuleComponent = Cast<UCapsuleComponent>(GetRootComponent());
	Mesh = GetComponentByClass<USkeletalMeshComponent>();
	PawnMovementComponent = GetComponentByClass<UPawnMovementComponent>();
	LuaScriptComponent = GetComponentByClass<ULuaScriptComponent>();

	if (PawnMovementComponent && CapsuleComponent)
	{
		PawnMovementComponent->SetUpdatedComponent(CapsuleComponent);
	}
}

void ARespawnRagdollPawn::BeginPlay()
{
	RefreshRespawnRagdollPawnComponents();
	Super::BeginPlay();
}

void ARespawnRagdollPawn::PostDuplicate()
{
	Super::PostDuplicate();
	RefreshRespawnRagdollPawnComponents();
}

void ARespawnRagdollPawn::OnOwnedComponentRemoved(UActorComponent* Component)
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
	if (Component == PawnMovementComponent)
	{
		PawnMovementComponent = nullptr;
	}
	if (Component == LuaScriptComponent)
	{
		LuaScriptComponent = nullptr;
	}
}
