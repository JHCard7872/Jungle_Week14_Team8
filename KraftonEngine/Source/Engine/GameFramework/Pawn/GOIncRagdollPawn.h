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

	// Alive 상태에서 이동/중력/바닥 충돌을 담당하는 Capsule.
	// 현재 1차 패치에서는 기존 Scene 호환을 위해 Root Capsule을 그대로 AliveCapsule로 사용한다.
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UCapsuleComponent* GetAliveCapsuleComponent() const { return CapsuleComponent; }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UCapsuleComponent* GetCapsuleComponent() const { return GetAliveCapsuleComponent(); }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UCapsuleComponent* GetAliveCollisionCapsuleComponent() const { return GetAliveCapsuleComponent(); }

	// DeadRagdoll 상태에서 Player overlap revive 감지만 담당하는 Trigger Capsule.
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UCapsuleComponent* GetReviveTriggerCapsuleComponent() const { return ReviveTriggerCapsuleComponent; }

	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	USkeletalMeshComponent* GetRagdollMeshComponent() const { return Mesh; }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	USkeletalMeshComponent* GetMesh() const { return GetRagdollMeshComponent(); }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UGOIncRagdollMovementComponent* GetGOIncMovementComponent() const { return RagdollMovementComponent; }
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	UGOIncRagdollMovementComponent* GetRagdollMovementComponent() const { return GetGOIncMovementComponent(); }
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

	// Dead ragdoll 결과를 기준으로 Reviving 시작 전에 Actor/AliveCapsule을 안전한 위치로 한 번만 정렬한다.
	// 상태 전환 판단은 Lua가 담당하고, 이 함수는 위치 정렬 helper 역할만 한다.
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|State")
	bool PrepareReviveFromRagdoll();

	// 상태 판단은 Lua가 담당하지만, 상태별 컴포넌트 on/off 조합은 Actor helper로 모아둔다.
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|State")
	void EnterDeadRagdollState();
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|State")
	void EnterRevivingState();
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|State")
	void EnterAliveFleeState();

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
	void SetAliveCollisionCapsuleEnabled(bool bEnabled);
	void SetReviveTriggerCapsuleEnabled(bool bEnabled);
	void SetMovementRuntimeEnabled(bool bEnabled, bool bUseFloorAndGravity);
	bool GetRagdollMeshSyncWorldLocation(FVector& OutLocation) const;
	bool ProjectAliveCapsuleLocationToGround(const FVector& ActorTargetLocation, float SourceZ, FVector& OutProjectedLocation) const;

	UCapsuleComponent* CapsuleComponent = nullptr;
	UCapsuleComponent* ReviveTriggerCapsuleComponent = nullptr;
	USkeletalMeshComponent* Mesh = nullptr;
	UGOIncRagdollMovementComponent* RagdollMovementComponent = nullptr;
	ULuaScriptComponent* LuaScriptComponent = nullptr;

	FString RagdollId = "blue-speedster";
	FString SkeletalMeshPath;
	FString FleeAnimationPath;
};
