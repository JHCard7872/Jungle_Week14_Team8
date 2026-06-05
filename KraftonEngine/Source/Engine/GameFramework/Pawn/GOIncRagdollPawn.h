#pragma once

#include "GameFramework/Pawn/Pawn.h"

class UCapsuleComponent;
class USkeletalMeshComponent;
class UGOIncRagdollMovementComponent;
class ULuaScriptComponent;

// GOInc 게임 전용 ragdoll NPC Pawn의 기본 컴포넌트 구성.
// UE Character 계열처럼 Capsule(Root) -> Mesh(Child) 구조를 유지하고,
// 게임 상태 전환/AI는 C++이 아니라 Lua에서 처리한다.
#include "Source/Engine/GameFramework/Pawn/GOIncRagdollPawn.generated.h"

UCLASS()
class AGOIncRagdollPawn : public APawn
{
public:
	GENERATED_BODY()
	AGOIncRagdollPawn() = default;
	~AGOIncRagdollPawn() override = default;

	// 기본 컴포넌트를 생성하고 Mario2 mesh를 초기 ragdoll 상태로 준비한다.
	void InitDefaultComponents();
	void InitDefaultComponents(const FString& SkeletalMeshFileName, const FString& ScriptFile = FString());

	void BeginPlay() override;
	void PostDuplicate() override;

	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UCapsuleComponent* GetCapsuleComponent() const { return CapsuleComponent; }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	USkeletalMeshComponent* GetMesh() const { return Mesh; }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UGOIncRagdollMovementComponent* GetRagdollMovementComponent() const { return RagdollMovementComponent; }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	ULuaScriptComponent* GetLuaScriptComponent() const { return LuaScriptComponent; }

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Animation")
	void PlayFleeAnimation();

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Animation")
	void StopFleeAnimation();

protected:
	void OnOwnedComponentRemoved(UActorComponent* Component) override;
	void RefreshGOIncRagdollPawnComponents();
	void ApplyInitialRagdollState();

	UCapsuleComponent* CapsuleComponent = nullptr;
	USkeletalMeshComponent* Mesh = nullptr;
	UGOIncRagdollMovementComponent* RagdollMovementComponent = nullptr;
	ULuaScriptComponent* LuaScriptComponent = nullptr;
};
