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

	// Alive 상태에서 이동/중력/바닥 충돌을 담당하는 Root Capsule.
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UCapsuleComponent* GetCapsuleComponent() const { return CapsuleComponent; }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UCapsuleComponent* GetAliveCollisionCapsuleComponent() const { return CapsuleComponent; }

	// DeadRagdoll 상태에서 Player overlap revive 감지만 담당하는 Trigger Capsule.
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UCapsuleComponent* GetReviveTriggerCapsuleComponent() const { return ReviveTriggerCapsuleComponent; }

	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	USkeletalMeshComponent* GetMesh() const { return Mesh; }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UGOIncRagdollMovementComponent* GetRagdollMovementComponent() const { return RagdollMovementComponent; }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	ULuaScriptComponent* GetLuaScriptComponent() const { return LuaScriptComponent; }

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetRagdollId(const FString& InRagdollId);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	FString GetRagdollId() const { return RagdollId; }

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetSkeletalMeshPath(const FString& InSkeletalMeshPath);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	FString GetSkeletalMeshPath() const { return SkeletalMeshPath; }

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetFleeAnimationPath(const FString& InFleeAnimationPath);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	FString GetFleeAnimationPath() const { return FleeAnimationPath; }

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetMeshRelativeLocation(const FVector& InRelativeLocation);
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetMeshRelativeScale(const FVector& InRelativeScale);
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetAliveCapsuleSize(float Radius, float HalfHeight);
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetReviveTriggerCapsuleSize(float Radius, float HalfHeight);

	// 외부 시스템(Player beam, trap 등)은 Lua 상태값을 직접 만지지 않고 이 API만 호출한다.
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|State")
	void RequestDeadRagdoll(const FString& Reason);

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Animation")
	void PlayFleeAnimation();

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Animation")
	void StopFleeAnimation();

protected:
	void OnOwnedComponentRemoved(UActorComponent* Component) override;
	void RefreshGOIncRagdollPawnComponents();
	void EnsureReviveTriggerCapsuleComponent();
	void ConfigureAliveCollisionCapsuleDefaults();
	void ConfigureReviveTriggerCapsuleDefaults();
	void ApplyInitialRagdollState();

	UCapsuleComponent* CapsuleComponent = nullptr;
	UCapsuleComponent* ReviveTriggerCapsuleComponent = nullptr;
	USkeletalMeshComponent* Mesh = nullptr;
	UGOIncRagdollMovementComponent* RagdollMovementComponent = nullptr;
	ULuaScriptComponent* LuaScriptComponent = nullptr;

	FString RagdollId = "blue-speedster";
	FString SkeletalMeshPath;
	FString FleeAnimationPath;
};
