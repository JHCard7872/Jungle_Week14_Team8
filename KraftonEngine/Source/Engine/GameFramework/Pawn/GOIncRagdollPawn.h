#pragma once

#include "GameFramework/Pawn/Pawn.h"
#include "Object/Ptr/SoftObjectPtr.h"
#include "Object/Reflection/UStruct.h"

class UCapsuleComponent;
class USceneComponent;
class USkeletalMeshComponent;
class UGOIncRagdollMovementComponent;
class ULuaScriptComponent;

// GOInc 게임 전용 ragdoll NPC Pawn의 기본 컴포넌트 구성.
// Root는 collision/physics가 없는 SceneComponent로 두고, AliveCapsule / ReviveTrigger / Mesh를 형제로 분리한다.
// 게임 상태 전환/AI는 C++이 아니라 Lua에서 처리한다.
#include "Source/Engine/GameFramework/Pawn/GOIncRagdollPawn.generated.h"

USTRUCT()
struct FGOIncRagdollCharacterConfig
{
	GENERATED_BODY()

	UPROPERTY(Edit, Save, Category = "GOInc|Identity", DisplayName = "Ragdoll Id")
	FString RagdollId = "blue-speedster";
	UPROPERTY(Edit, Save, Category = "GOInc|Identity", DisplayName = "Display Name")
	FString DisplayName = "파란 고슴도치";

	UPROPERTY(Edit, Save, Category = "GOInc|Assets", DisplayName = "Skeletal Mesh", AssetType = "SkeletalMesh")
	FSoftObjectPtr SkeletalMeshPath = "Content/Data/Sonic/sc_dash_loop_anm_hkx_SkeletalMesh.uasset";
	UPROPERTY(Edit, Save, Category = "GOInc|Assets", DisplayName = "Physics Asset")
	FString PhysicsAssetPath = "Content/Data/Sonic/sc_dash_loop_anm_hkx_PhysicsAsset.uasset";
	UPROPERTY(Edit, Save, Category = "GOInc|Assets", DisplayName = "Flee Animation", AssetType = "UAnimSequence")
	FSoftObjectPtr FleeAnimationPath = "Content/Data/Sonic/sc_dash_loop_anm_hkx_sc_dash_loop.uasset";
	UPROPERTY(Edit, Save, Category = "GOInc|Assets", DisplayName = "Lua Script", AssetType = "Script")
	FString LuaScriptFile = "GOIncRagdollPawn_Test.lua";

	UPROPERTY(Edit, Save, Category = "GOInc|Mesh", DisplayName = "Mesh Relative Location")
	FVector MeshRelativeLocation = FVector(0.0f, 0.0f, 0.0f);
	UPROPERTY(Edit, Save, Category = "GOInc|Mesh", DisplayName = "Mesh Relative Scale")
	FVector MeshRelativeScale = FVector(1.0f, 1.0f, 1.0f);

	UPROPERTY(Edit, Save, Category = "GOInc|Capsule", DisplayName = "Alive Capsule Radius", Min = 0.01f, Speed = 0.1f)
	float AliveCapsuleRadius = 1.8f;
	UPROPERTY(Edit, Save, Category = "GOInc|Capsule", DisplayName = "Alive Capsule Half Height", Min = 0.01f, Speed = 0.1f)
	float AliveCapsuleHalfHeight = 3.0f;
	UPROPERTY(Edit, Save, Category = "GOInc|Capsule", DisplayName = "Revive Trigger Radius", Min = 0.01f, Speed = 0.1f)
	float ReviveTriggerCapsuleRadius = 2.4f;
	UPROPERTY(Edit, Save, Category = "GOInc|Capsule", DisplayName = "Revive Trigger Half Height", Min = 0.01f, Speed = 0.1f)
	float ReviveTriggerCapsuleHalfHeight = 3.4f;

	UPROPERTY(Edit, Save, Category = "GOInc|Revive", DisplayName = "Can Revive")
	bool bCanRevive = true;
	UPROPERTY(Edit, Save, Category = "GOInc|Revive", DisplayName = "Revive Blend Duration", Min = 0.0f, Speed = 0.01f)
	float ReviveBlendDuration = 0.8f;

	UPROPERTY(Edit, Save, Category = "GOInc|Flee", DisplayName = "Flee Speed", Min = 0.0f, Speed = 0.1f)
	float FleeSpeed = 4.0f;
	UPROPERTY(Edit, Save, Category = "GOInc|Flee", DisplayName = "Flee Acceleration", Min = 0.0f, Speed = 0.1f)
	float FleeAcceleration = 15.0f;
	UPROPERTY(Edit, Save, Category = "GOInc|Flee", DisplayName = "Flee Braking Deceleration", Min = 0.0f, Speed = 0.1f)
	float FleeBrakingDeceleration = 10.0f;
	UPROPERTY(Edit, Save, Category = "GOInc|Flee", DisplayName = "Flee End Distance", Min = 0.0f, Speed = 0.1f)
	float FleeEndDistance = 10.0f;
	UPROPERTY(Edit, Save, Category = "GOInc|Flee", DisplayName = "Flee Stop Duration", Min = 0.0f, Speed = 0.01f)
	float FleeStopDuration = 1.0f;
	UPROPERTY(Edit, Save, Category = "GOInc|Flee", DisplayName = "Flee Stop Min Braking", Min = 0.0f, Speed = 0.01f)
	float FleeStopMinBrakingDeceleration = 0.1f;
	UPROPERTY(Edit, Save, Category = "GOInc|Flee", DisplayName = "Flee Rotation Yaw Offset", Speed = 0.5f)
	float FleeRotationYawOffsetDegrees = 0.0f;

	UPROPERTY(Edit, Save, Category = "GOInc|Animation", DisplayName = "Animation Base Speed", Min = 0.0f, Speed = 0.1f)
	float FleeAnimationBaseSpeed = 4.0f;
	UPROPERTY(Edit, Save, Category = "GOInc|Animation", DisplayName = "Animation Min Play Rate", Min = 0.0f, Speed = 0.01f)
	float FleeAnimationMinPlayRate = 0.0f;
	UPROPERTY(Edit, Save, Category = "GOInc|Animation", DisplayName = "Animation Max Play Rate", Min = 0.0f, Speed = 0.01f)
	float FleeAnimationMaxPlayRate = 1.0f;
	UPROPERTY(Edit, Save, Category = "GOInc|Animation", DisplayName = "Flee Stop Start Play Rate", Min = 0.0f, Speed = 0.01f)
	float FleeStopStartPlayRate = 1.0f;
	UPROPERTY(Edit, Save, Category = "GOInc|Animation", DisplayName = "Flee Stop End Play Rate", Min = 0.0f, Speed = 0.01f)
	float FleeStopEndPlayRate = 0.0f;
};

UCLASS()
class AGOIncRagdollPawn : public APawn
{
public:
	GENERATED_BODY()
	AGOIncRagdollPawn() = default;
	~AGOIncRagdollPawn() override = default;

	// 기본 컴포넌트를 생성하고 캐릭터 설정을 적용한다.
	// 하위 호환용 entry point로 유지하며, 내부에서는 EnsureDefaultComponents + RefreshCharacterConfig를 사용한다.
	void InitDefaultComponents();
	void InitDefaultComponents(const FString& SkeletalMeshFileName, const FString& ScriptFile = FString());

	// 컴포넌트 생성/조립만 담당한다. 이미 생성된 컴포넌트는 재사용한다.
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void EnsureDefaultComponents();

	// 현재 Pawn class의 캐릭터 기본값을 다시 만들고 컴포넌트에 적용한다.
	// 런타임 hot refresh용 진입점으로 두되, 상태별 안전 처리는 이후 패치에서 확장한다.
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void RefreshCharacterConfig();

	// 에디터에서 노출된 CharacterConfig 값을 현재 Pawn에 즉시 적용한다.
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void ApplyEditableCharacterConfig();

	// 하위 클래스가 제공하는 기본 config로 되돌린다.
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void ResetCharacterConfigToClassDefaults();

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetUseEditableCharacterConfig(bool bEnabled);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	bool GetUseEditableCharacterConfig() const { return bUseEditableCharacterConfig; }

	void BeginPlay() override;
	void PostDuplicate() override;
	void PostEditProperty(const char* PropertyName) override;

	// Alive 상태에서 이동/중력/바닥 충돌을 담당하는 Capsule.
	// 기존 API 호환을 위해 이름은 CapsuleComponent를 유지하지만, 의미는 AliveCapsule이다.
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
	UFUNCTION(Pure, Category="GOIncRagdollPawn|Components")
	USceneComponent* GetGOIncRootComponent() const { return GOIncRootComponent; }

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetRagdollId(const FString& InRagdollId);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	FString GetRagdollId() const { return RagdollId; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	FString GetDisplayName() const { return CharacterConfig.DisplayName; }

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetSkeletalMeshPath(const FString& InSkeletalMeshPath);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	FString GetSkeletalMeshPath() const { return SkeletalMeshPath; }

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetPhysicsAssetPath(const FString& InPhysicsAssetPath);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	FString GetPhysicsAssetPath() const { return PhysicsAssetPath; }

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetFleeAnimationPath(const FString& InFleeAnimationPath);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	FString GetFleeAnimationPath() const { return FleeAnimationPath; }

	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetMeshRelativeLocation(const FVector& InRelativeLocation);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	FVector GetMeshRelativeLocation() const { return CharacterConfig.MeshRelativeLocation; }
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetMeshRelativeScale(const FVector& InRelativeScale);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	FVector GetMeshRelativeScale() const { return CharacterConfig.MeshRelativeScale; }
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetAliveCapsuleSize(float Radius, float HalfHeight);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	float GetAliveCapsuleRadius() const { return CharacterConfig.AliveCapsuleRadius; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	float GetAliveCapsuleHalfHeight() const { return CharacterConfig.AliveCapsuleHalfHeight; }
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|Config")
	void SetReviveTriggerCapsuleSize(float Radius, float HalfHeight);
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	float GetReviveTriggerCapsuleRadius() const { return CharacterConfig.ReviveTriggerCapsuleRadius; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	float GetReviveTriggerCapsuleHalfHeight() const { return CharacterConfig.ReviveTriggerCapsuleHalfHeight; }

	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	bool CanRevive() const { return CharacterConfig.bCanRevive; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Config")
	float GetReviveBlendDuration() const { return CharacterConfig.ReviveBlendDuration; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeSpeed() const { return CharacterConfig.FleeSpeed; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeAcceleration() const { return CharacterConfig.FleeAcceleration; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeBrakingDeceleration() const { return CharacterConfig.FleeBrakingDeceleration; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeEndDistance() const { return CharacterConfig.FleeEndDistance; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeStopDuration() const { return CharacterConfig.FleeStopDuration; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeStopMinBrakingDeceleration() const { return CharacterConfig.FleeStopMinBrakingDeceleration; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeRotationYawOffsetDegrees() const { return CharacterConfig.FleeRotationYawOffsetDegrees; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeAnimationBaseSpeed() const { return CharacterConfig.FleeAnimationBaseSpeed; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeAnimationMinPlayRate() const { return CharacterConfig.FleeAnimationMinPlayRate; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeAnimationMaxPlayRate() const { return CharacterConfig.FleeAnimationMaxPlayRate; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeStopStartPlayRate() const { return CharacterConfig.FleeStopStartPlayRate; }
	UFUNCTION(Pure, Category = "GOIncRagdollPawn|Flee")
	float GetFleeStopEndPlayRate() const { return CharacterConfig.FleeStopEndPlayRate; }

	// Dead 상태에서 ragdoll physics 결과 위치를 따라 GOIncRoot/AliveCapsule의 논리 위치를 안전하게 갱신한다.
	// XY는 ragdoll sync 위치를 따라가고, Z는 AliveCapsule이 바닥 위에 서도록 보정한다.
	// Mesh ragdoll body는 이동시키지 않고 기존 SkeletalMeshComponent sync 로직으로 다시 맞춘다.
	UFUNCTION(Callable, Category = "GOIncRagdollPawn|State")
	bool UpdateDeadRootFromRagdollSafe();

	// Dead ragdoll 결과를 기준으로 Reviving 시작 전에 Actor/AliveCapsule을 안전한 위치로 최종 보정한다.
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
	virtual FGOIncRagdollCharacterConfig MakeCharacterConfig() const;
	void ApplyCharacterConfig(const FGOIncRagdollCharacterConfig& InCharacterConfig);
	bool IsCharacterConfigPropertyName(const char* PropertyName) const;
	void RefreshGOIncRagdollPawnComponents();
	void EnsureGOIncRootComponent();
	void EnsureReviveTriggerCapsuleComponent();
	void AttachGOIncSceneComponentsToRoot();
	void ConfigureMovementUpdatedComponent();
	void ConfigureAliveCollisionCapsuleDefaults();
	void ConfigureReviveTriggerCapsuleDefaults();
	void ApplyInitialRagdollState();
	void SetAliveCollisionCapsuleEnabled(bool bEnabled);
	void SetReviveTriggerCapsuleEnabled(bool bEnabled);
	void SetMovementRuntimeEnabled(bool bEnabled, bool bUseFloorAndGravity);
	void ForceDeadRagdollPhysicsEnabled();
	void ForceAliveAnimationPhysicsDisabled();
	bool GetRagdollMeshSyncWorldLocation(FVector& OutLocation) const;
	bool ProjectAliveCapsuleLocationToGround(const FVector& ActorTargetLocation, float SourceZ, FVector& OutProjectedLocation) const;
	void ResyncMeshComponentToCurrentRagdollBodies();

	USceneComponent* GOIncRootComponent = nullptr;
	UCapsuleComponent* CapsuleComponent = nullptr;
	UCapsuleComponent* ReviveTriggerCapsuleComponent = nullptr;
	USkeletalMeshComponent* Mesh = nullptr;
	UGOIncRagdollMovementComponent* RagdollMovementComponent = nullptr;
	ULuaScriptComponent* LuaScriptComponent = nullptr;

	// false면 MakeCharacterConfig()가 제공하는 class 기본값을 사용한다.
	// true면 아래 CharacterConfig를 에디터/씬 저장값으로 보고 그대로 적용한다.
	UPROPERTY(Edit, Save, Category = "GOInc|Config", DisplayName = "Use Editable Character Config")
	bool bUseEditableCharacterConfig = false;

	UPROPERTY(Edit, Save, Category = "GOInc|Config", DisplayName = "Character Config")
	FGOIncRagdollCharacterConfig CharacterConfig;
	FString RagdollId = "blue-speedster";
	FString SkeletalMeshPath;
	FString PhysicsAssetPath;
	FString FleeAnimationPath;
};
