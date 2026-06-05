#pragma once

#include "GameFramework/Pawn/Pawn.h"

class UCapsuleComponent;
class USkeletalMeshComponent;
class UPawnMovementComponent;
class ULuaScriptComponent;

// 리스폰 회수 게임용 ragdoll NPC Pawn의 최소 컴포넌트 구성.
// UE Character 계열처럼 Capsule(Root) -> Mesh(Child) 구조를 유지하고,
// 게임 상태 전환/AI/ragdoll on-off 조합은 C++이 아니라 Lua에서 처리한다.
#include "Source/Engine/GameFramework/Pawn/RespawnRagdollPawn.generated.h"

UCLASS()
class ARespawnRagdollPawn : public APawn
{
public:
	GENERATED_BODY()
	ARespawnRagdollPawn() = default;
	~ARespawnRagdollPawn() override = default;

	// 기본 컴포넌트만 생성한다. 상태 전환, AI, ragdoll 제어는 의도적으로 넣지 않는다.
	void InitDefaultComponents();
	void InitDefaultComponents(const FString& SkeletalMeshFileName, const FString& ScriptFile = FString());

	void BeginPlay() override;
	void PostDuplicate() override;

	UFUNCTION(Pure, Category="RespawnRagdollPawn|Components")
	UCapsuleComponent* GetCapsuleComponent() const { return CapsuleComponent; }
	UFUNCTION(Pure, Category="RespawnRagdollPawn|Components")
	USkeletalMeshComponent* GetMesh() const { return Mesh; }
	UFUNCTION(Pure, Category="RespawnRagdollPawn|Components")
	UPawnMovementComponent* GetPawnMovementComponent() const { return PawnMovementComponent; }
	UFUNCTION(Pure, Category="RespawnRagdollPawn|Components")
	ULuaScriptComponent* GetLuaScriptComponent() const { return LuaScriptComponent; }

protected:
	void OnOwnedComponentRemoved(UActorComponent* Component) override;
	void RefreshRespawnRagdollPawnComponents();

	UCapsuleComponent* CapsuleComponent = nullptr;
	USkeletalMeshComponent* Mesh = nullptr;
	UPawnMovementComponent* PawnMovementComponent = nullptr;
	ULuaScriptComponent* LuaScriptComponent = nullptr;
};
