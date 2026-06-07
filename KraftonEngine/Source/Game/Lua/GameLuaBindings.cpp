#include "Game/Lua/GameLuaBindings.h"

#include "sol/sol.hpp"

#include "Component/Movement/GOIncRagdollMovementComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Component/PrimitiveComponent.h"
#include "Component/Script/LuaScriptComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "Component/ShapeComponent.h"
#include "Core/Types/CollisionTypes.h"
#include "Core/Logging/Log.h"
#include "Engine/Runtime/Engine.h"
#include "Engine/Runtime/EngineInitHooks.h"
#include "Game/GOIncRagdollCharacterRegistry.h"
#include "GameFramework/Pawn/GOIncRagdollPawn.h"
#include "GameFramework/World.h"
#include "Lua/LuaScriptManager.h"
#include "Materials/Material.h"
#include "Materials/MaterialManager.h"
#include "Math/Transform.h"

#include <algorithm>
#include <cctype>

// ============================================================
// 게임-특화 Lua 바인딩 등록 위치 — 현재는 비어 있음.
//
// Engine 의 FLuaScriptManager 가 등록하는 일반 binding (AActor / APawn / FVector /
// UWorld / Anim 등) 만으로 동작하지 않는 game-specific usertype (ACarPawn /
// AGameStateXxx / 전용 enum 등) 이 도입되면 여기에 new_usertype 으로 추가한다.
//
// 호출 시점: UEngine::Init() 이 FLuaScriptManager::Initialize() 를 끝낸 직후.
// 등록은 EngineInitHooks 에 자동으로 걸려 GameEngine / EditorEngine 두 엔트리 모두
// 같은 바인딩이 적용된다 (PIE 호환).
// ============================================================
namespace
{
	FString NormalizeLuaName(FString Value)
	{
		Value.erase(
			std::remove_if(Value.begin(), Value.end(), [](unsigned char C)
			{
				return C == '_' || C == '-' || std::isspace(C) != 0;
			}),
			Value.end());

		std::transform(Value.begin(), Value.end(), Value.begin(), [](unsigned char C)
		{
			return static_cast<char>(std::tolower(C));
		});
		return Value;
	}

	ECollisionEnabled CollisionEnabledFromLuaString(const FString& Mode)
	{
		const FString Normalized = NormalizeLuaName(Mode);
		if (Normalized == "nocollision" || Normalized == "none" || Normalized == "off")
		{
			return ECollisionEnabled::NoCollision;
		}
		if (Normalized == "queryonly" || Normalized == "query")
		{
			return ECollisionEnabled::QueryOnly;
		}
		if (Normalized == "physicsonly" || Normalized == "physics")
		{
			return ECollisionEnabled::PhysicsOnly;
		}
		if (Normalized == "queryandphysics" || Normalized == "queryphysics" || Normalized == "all")
		{
			return ECollisionEnabled::QueryAndPhysics;
		}
		if (Normalized == "probeonly" || Normalized == "probe")
		{
			return ECollisionEnabled::ProbeOnly;
		}
		if (Normalized == "queryandprobe" || Normalized == "queryprobe")
		{
			return ECollisionEnabled::QueryAndProbe;
		}

		UE_LOG("[Lua] Unknown CollisionEnabled mode '%s'. Falling back to NoCollision.", Mode.c_str());
		return ECollisionEnabled::NoCollision;
	}

	FString CollisionEnabledToLuaString(ECollisionEnabled Mode)
	{
		switch (Mode)
		{
		case ECollisionEnabled::NoCollision: return "NoCollision";
		case ECollisionEnabled::QueryOnly: return "QueryOnly";
		case ECollisionEnabled::PhysicsOnly: return "PhysicsOnly";
		case ECollisionEnabled::QueryAndPhysics: return "QueryAndPhysics";
		case ECollisionEnabled::ProbeOnly: return "ProbeOnly";
		case ECollisionEnabled::QueryAndProbe: return "QueryAndProbe";
		default: return "Unknown";
		}
	}

	sol::object MakeNil(sol::this_state State)
	{
		return sol::make_object(State, sol::nil);
	}

	sol::table MakeTransformTable(sol::this_state State, const FTransform& Transform)
	{
		sol::state_view L(State);
		sol::table Result = L.create_table();
		Result["Location"] = Transform.Location;
		Result["Rotation"] = Transform.GetRotator().ToVector();
		Result["Scale"] = Transform.Scale;
		return Result;
	}

	sol::object MakeOptionalTransform(sol::this_state State, bool bSuccess, const FTransform& Transform)
	{
		if (!bSuccess)
		{
			return MakeNil(State);
		}
		return sol::make_object(State, MakeTransformTable(State, Transform));
	}

	sol::object MakeOptionalVector(sol::this_state State, bool bSuccess, const FVector& Vector)
	{
		if (!bSuccess)
		{
			return MakeNil(State);
		}
		return sol::make_object(State, Vector);
	}
}

void RegisterGameLuaBindings(sol::state& Lua)
{

	// GOInc game-level helpers. Keep game-specific spawn policy out of Engine/Lua bindings,
	// but still guarantee GOIncRagdollPawn receives its RagdollId before BeginPlay.
	{
		sol::object ExistingGOInc = Lua["GOInc"];
		sol::table GOInc = (ExistingGOInc.valid() && ExistingGOInc.get_type() == sol::type::table)
			? ExistingGOInc.as<sol::table>()
			: Lua.create_named_table("GOInc");

		GOInc.set_function("SpawnRagdollPawn", [](const FString& RagdollId, const FVector& Location) -> AGOIncRagdollPawn*
		{
			if (!GEngine)
			{
				UE_LOG("[GOInc] SpawnRagdollPawn failed. Missing GEngine.");
				return nullptr;
			}

			UWorld* World = GEngine->GetWorld();
			if (!World)
			{
				UE_LOG("[GOInc] SpawnRagdollPawn failed. Missing World.");
				return nullptr;
			}

			AGOIncRagdollPawn* SpawnedPawn = World->SpawnActorWithInitializer<AGOIncRagdollPawn>(
				[&](AGOIncRagdollPawn* Pawn)
				{
					if (!Pawn)
					{
						return;
					}

					Pawn->SetRagdollId(RagdollId);
					Pawn->InitDefaultComponents();
					Pawn->SetActorLocation(Location);
				});

			if (!SpawnedPawn)
			{
				UE_LOG("[GOInc] SpawnRagdollPawn failed. RagdollId=%s", RagdollId.c_str());
				return nullptr;
			}

			UE_LOG("[GOInc] Spawned legacy ragdoll pawn. RagdollId=%s Location=(%.2f, %.2f, %.2f)",
				SpawnedPawn->GetRagdollId().c_str(), Location.X, Location.Y, Location.Z);
			return SpawnedPawn;
		});

		GOInc.set_function("IsRagdollCharacterRegistered", [](const FString& CharacterId) -> bool
		{
			return IsGOIncRagdollCharacterRegistered(CharacterId);
		});

		GOInc.set_function("SpawnRagdollCharacter", [](const FString& CharacterId, const FVector& Location) -> AGOIncRagdollPawn*
		{
			if (!GEngine)
			{
				UE_LOG("[GOInc] SpawnRagdollCharacter failed. Missing GEngine.");
				return nullptr;
			}

			UWorld* World = GEngine->GetWorld();
			if (!World)
			{
				UE_LOG("[GOInc] SpawnRagdollCharacter failed. Missing World.");
				return nullptr;
			}

			AGOIncRagdollPawn* SpawnedPawn = SpawnGOIncRagdollCharacter(World, CharacterId, Location);
			if (!SpawnedPawn)
			{
				UE_LOG("[GOInc] Unknown ragdoll character id '%s'. Falling back to AGOIncRagdollPawn.", CharacterId.c_str());

				SpawnedPawn = World->SpawnActorWithInitializer<AGOIncRagdollPawn>(
					[&](AGOIncRagdollPawn* Pawn)
					{
						if (!Pawn)
						{
							return;
						}

						Pawn->SetRagdollId(CharacterId);
						Pawn->InitDefaultComponents();
						Pawn->SetActorLocation(Location);
					});
			}

			if (!SpawnedPawn)
			{
				UE_LOG("[GOInc] SpawnRagdollCharacter failed. CharacterId=%s", CharacterId.c_str());
				return nullptr;
			}

			UE_LOG("[GOInc] Spawned ragdoll character. CharacterId=%s ActualRagdollId=%s Location=(%.2f, %.2f, %.2f)",
				CharacterId.c_str(), SpawnedPawn->GetRagdollId().c_str(), Location.X, Location.Y, Location.Z);
			return SpawnedPawn;
		});

		// 금/은 래그돌 비주얼 — 스폰 추첨(GOIncRagdollSpawnManager.lua)이 Gold/Silver 태그와
		// 함께 호출한다. 머티리얼은 FMaterialManager 캐시를 타므로 반복 호출 비용 없음.
		GOInc.set_function("SetRagdollOverrideMaterial", [](AGOIncRagdollPawn* Pawn, const FString& MatPath) -> bool
		{
			if (!Pawn)
			{
				UE_LOG("[GOInc] SetRagdollOverrideMaterial failed. Missing pawn.");
				return false;
			}

			USkeletalMeshComponent* Mesh = Pawn->GetRagdollMeshComponent();
			if (!Mesh)
			{
				UE_LOG("[GOInc] SetRagdollOverrideMaterial failed. Pawn has no ragdoll mesh. RagdollId=%s",
					Pawn->GetRagdollId().c_str());
				return false;
			}

			UMaterial* Material = FMaterialManager::Get().GetOrCreateMaterial(MatPath);
			if (!Material)
			{
				UE_LOG("[GOInc] SetRagdollOverrideMaterial failed. Material load failed. Path=%s", MatPath.c_str());
				return false;
			}

			const int32 SlotCount = static_cast<int32>(Mesh->GetOverrideMaterials().size());
			for (int32 Index = 0; Index < SlotCount; ++Index)
			{
				Mesh->SetMaterial(Index, Material);
			}
			return true;
		});
	}

	// 이미 엔진 공통 바인딩에서 등록된 usertype에 게임 테스트용 convenience API만 덧붙인다.
	// 문자열 기반 collision mode를 노출해 Lua 스크립트에서 enum 숫자에 의존하지 않게 한다.
	{
		sol::table PrimitiveComponentType = Lua["PrimitiveComponent"];
		if (PrimitiveComponentType.valid())
		{
			PrimitiveComponentType.set_function("SetCollisionEnabled", [](UPrimitiveComponent& Component, const FString& Mode)
			{
				Component.SetCollisionEnabled(CollisionEnabledFromLuaString(Mode));
			});
			PrimitiveComponentType.set_function("GetCollisionEnabled", [](UPrimitiveComponent& Component)
			{
				return CollisionEnabledToLuaString(Component.GetCollisionEnabled());
			});
			PrimitiveComponentType.set_function("SetGenerateOverlapEvents", &UPrimitiveComponent::SetGenerateOverlapEvents);
			PrimitiveComponentType.set_function("GetGenerateOverlapEvents", &UPrimitiveComponent::GetGenerateOverlapEvents);
			PrimitiveComponentType.set_function("SetKinematicPhysics", &UPrimitiveComponent::SetKinematicPhysics);
			PrimitiveComponentType.set_function("GetKinematicPhysics", &UPrimitiveComponent::GetKinematicPhysics);
			PrimitiveComponentType.set_function("IsCollisionEnabled", &UPrimitiveComponent::IsCollisionEnabled);
			PrimitiveComponentType.set_function("IsQueryCollisionEnabled", &UPrimitiveComponent::IsQueryCollisionEnabled);
			PrimitiveComponentType.set_function("IsPhysicsCollisionEnabled", &UPrimitiveComponent::IsPhysicsCollisionEnabled);
		}
	}

	// CapsuleComponent는 GOIncRagdollPawn getter가 직접 반환하므로 Lua usertype이 필요하다.
	Lua.new_usertype<UShapeComponent>("ShapeComponent",
		sol::base_classes,
		sol::bases<UPrimitiveComponent, USceneComponent, UActorComponent, UObject>());

	Lua.new_usertype<UCapsuleComponent>("CapsuleComponent",
		sol::base_classes,
		sol::bases<UShapeComponent, UPrimitiveComponent, USceneComponent, UActorComponent, UObject>(),
		"SetCapsuleSize", &UCapsuleComponent::SetCapsuleSize,
		"GetScaledCapsuleRadius", &UCapsuleComponent::GetScaledCapsuleRadius,
		"GetScaledCapsuleHalfHeight", &UCapsuleComponent::GetScaledCapsuleHalfHeight,
		"GetUnscaledCapsuleRadius", &UCapsuleComponent::GetUnscaledCapsuleRadius,
		"GetUnscaledCapsuleHalfHeight", &UCapsuleComponent::GetUnscaledCapsuleHalfHeight);

	Lua.new_usertype<ULuaScriptComponent>("LuaScriptComponent",
		sol::base_classes,
		sol::bases<UActorComponent, UObject>(),
		"ReloadScript", &ULuaScriptComponent::ReloadScript,
		"CallFunction", &ULuaScriptComponent::CallFunction,
		"CallFunctionString", &ULuaScriptComponent::CallFunctionString,
		"GetScriptFile", &ULuaScriptComponent::GetScriptFile,
		"SetScriptFile", &ULuaScriptComponent::SetScriptFile);

	Lua.new_usertype<UGOIncRagdollMovementComponent>("GOIncRagdollMovementComponent",
		sol::base_classes,
		sol::bases<UActorComponent, UObject>(),
		"AddInputVector", &UGOIncRagdollMovementComponent::AddInputVector,
		"ConsumeInputVector", &UGOIncRagdollMovementComponent::ConsumeInputVector,
		"StopMovementImmediately", &UGOIncRagdollMovementComponent::StopMovementImmediately,
		"SetMovementEnabled", &UGOIncRagdollMovementComponent::SetMovementEnabled,
		"IsMovementEnabled", &UGOIncRagdollMovementComponent::IsMovementEnabled,
		"SetMaxSpeed", &UGOIncRagdollMovementComponent::SetMaxSpeed,
		"SetAcceleration", &UGOIncRagdollMovementComponent::SetAcceleration,
		"SetBrakingDeceleration", &UGOIncRagdollMovementComponent::SetBrakingDeceleration,
		"SetFloorRaycastEnabled", &UGOIncRagdollMovementComponent::SetFloorRaycastEnabled,
		"IsFloorRaycastEnabled", &UGOIncRagdollMovementComponent::IsFloorRaycastEnabled,
		"SetGravityEnabled", &UGOIncRagdollMovementComponent::SetGravityEnabled,
		"IsGravityEnabled", &UGOIncRagdollMovementComponent::IsGravityEnabled,
		"SetSweepMovementEnabled", &UGOIncRagdollMovementComponent::SetSweepMovementEnabled,
		"IsSweepMovementEnabled", &UGOIncRagdollMovementComponent::IsSweepMovementEnabled,
		"SetMovementCollisionCapsule", &UGOIncRagdollMovementComponent::SetMovementCollisionCapsule,
		"ClearMovementCollisionCapsule", &UGOIncRagdollMovementComponent::ClearMovementCollisionCapsule,
		"SnapUpdatedComponentToFloor", &UGOIncRagdollMovementComponent::SnapUpdatedComponentToFloor,
		"IsGrounded", &UGOIncRagdollMovementComponent::IsGrounded,
		"GetVelocity", &UGOIncRagdollMovementComponent::GetVelocity);

	Lua.new_usertype<USkeletalMeshComponent>("SkeletalMeshComponent",
		sol::base_classes,
		sol::bases<UPrimitiveComponent, USceneComponent, UActorComponent, UObject>(),
		"SetRagdollEnabled", &USkeletalMeshComponent::SetRagdollEnabled,
		"IsRagdollEnabled", &USkeletalMeshComponent::IsRagdollEnabled,
		"SetPlayRate", &USkeletalMeshComponent::SetPlayRate,
		"IsRagdollRecovering", &USkeletalMeshComponent::IsRagdollRecovering,
		"WakeAllRagdollBodies", &USkeletalMeshComponent::WakeAllRagdollBodies,
		"GetRagdollRecoveryDuration", &USkeletalMeshComponent::GetRagdollRecoveryDuration,
		"SetRagdollRecoveryDuration", &USkeletalMeshComponent::SetRagdollRecoveryDuration,
		"AddImpulseToBone", [](USkeletalMeshComponent& Component, const FString& BoneName, const FVector& Impulse)
		{
			Component.AddImpulseToBone(FName(BoneName), Impulse);
		},
		"AddRandomImpulseToAllRagdollBodies", &USkeletalMeshComponent::AddRandomImpulseToAllRagdollBodies,
		"BeginRagdollJitterAnchor", &USkeletalMeshComponent::BeginRagdollJitterAnchor,
		"EndRagdollJitterAnchor", &USkeletalMeshComponent::EndRagdollJitterAnchor,
		"IsRagdollJitterAnchorEnabled", &USkeletalMeshComponent::IsRagdollJitterAnchorEnabled,
		"AddJitterImpulseToAllRagdollBodies", &USkeletalMeshComponent::AddJitterImpulseToAllRagdollBodies,
		"SetAllBodiesPhysicsBlendWeight", &USkeletalMeshComponent::SetAllBodiesPhysicsBlendWeight,
		"SetAllBodiesBelowPhysicsBlendWeight", [](USkeletalMeshComponent& Component, const FString& BoneName, float Weight, sol::optional<bool> bIncludeSelf)
		{
			Component.SetAllBodiesBelowPhysicsBlendWeight(FName(BoneName), Weight, bIncludeSelf.value_or(true));
		},
		"SetAllBodiesSimulatePhysics", &USkeletalMeshComponent::SetAllBodiesSimulatePhysics,
		"SetAllBodiesBelowSimulatePhysics", [](USkeletalMeshComponent& Component, const FString& BoneName, bool bSimulate, sol::optional<bool> bIncludeSelf)
		{
			Component.SetAllBodiesBelowSimulatePhysics(FName(BoneName), bSimulate, bIncludeSelf.value_or(true));
		},
		"SetRagdollGravityEnabled", &USkeletalMeshComponent::SetRagdollGravityEnabled,
		"IsRagdollGravityEnabled", &USkeletalMeshComponent::IsRagdollGravityEnabled,
		"GetRagdollBodyWorldTransform", [](USkeletalMeshComponent& Component, const FString& BoneName, sol::this_state State) -> sol::object
		{
			FTransform Transform;
			return MakeOptionalTransform(State, Component.GetRagdollBodyWorldTransform(FName(BoneName), Transform), Transform);
		},
		"GetRagdollBodyWorldLocation", [](USkeletalMeshComponent& Component, const FString& BoneName, sol::this_state State) -> sol::object
		{
			FVector Location;
			return MakeOptionalVector(State, Component.GetRagdollBodyWorldLocation(FName(BoneName), Location), Location);
		},
		"GetRagdollComponentSyncWorldTransform", [](USkeletalMeshComponent& Component, sol::this_state State) -> sol::object
		{
			FTransform Transform;
			return MakeOptionalTransform(State, Component.GetRagdollComponentSyncWorldTransform(Transform), Transform);
		},
		"GetRagdollComponentSyncWorldLocation", [](USkeletalMeshComponent& Component, sol::this_state State) -> sol::object
		{
			FVector Location;
			return MakeOptionalVector(State, Component.GetRagdollComponentSyncWorldLocation(Location), Location);
		});

	Lua.new_usertype<AGOIncRagdollPawn>("GOIncRagdollPawn",
		sol::base_classes,
		sol::bases<APawn, AActor, UObject>(),
		"GetAliveCapsuleComponent", &AGOIncRagdollPawn::GetAliveCapsuleComponent,
		"GetCapsuleComponent", &AGOIncRagdollPawn::GetCapsuleComponent,
		"GetAliveCollisionCapsuleComponent", &AGOIncRagdollPawn::GetAliveCollisionCapsuleComponent,
		"GetReviveTriggerCapsuleComponent", &AGOIncRagdollPawn::GetReviveTriggerCapsuleComponent,
		"GetRagdollMeshComponent", &AGOIncRagdollPawn::GetRagdollMeshComponent,
		"GetMesh", &AGOIncRagdollPawn::GetMesh,
		"GetGOIncMovementComponent", &AGOIncRagdollPawn::GetGOIncMovementComponent,
		"GetRagdollMovementComponent", &AGOIncRagdollPawn::GetRagdollMovementComponent,
		"GetLuaScriptComponent", &AGOIncRagdollPawn::GetLuaScriptComponent,
		"GetGOIncRootComponent", &AGOIncRagdollPawn::GetGOIncRootComponent,
		"EnsureDefaultComponents", &AGOIncRagdollPawn::EnsureDefaultComponents,
		"RefreshCharacterConfig", &AGOIncRagdollPawn::RefreshCharacterConfig,
		"ApplyEditableCharacterConfig", &AGOIncRagdollPawn::ApplyEditableCharacterConfig,
		"ResetCharacterConfigToClassDefaults", &AGOIncRagdollPawn::ResetCharacterConfigToClassDefaults,
		"SetUseEditableCharacterConfig", &AGOIncRagdollPawn::SetUseEditableCharacterConfig,
		"GetUseEditableCharacterConfig", &AGOIncRagdollPawn::GetUseEditableCharacterConfig,
		"SetRagdollId", &AGOIncRagdollPawn::SetRagdollId,
		"GetRagdollId", &AGOIncRagdollPawn::GetRagdollId,
		"GetDisplayName", &AGOIncRagdollPawn::GetDisplayName,
		"SetSkeletalMeshPath", &AGOIncRagdollPawn::SetSkeletalMeshPath,
		"GetSkeletalMeshPath", &AGOIncRagdollPawn::GetSkeletalMeshPath,
		"SetPhysicsAssetPath", &AGOIncRagdollPawn::SetPhysicsAssetPath,
		"GetPhysicsAssetPath", &AGOIncRagdollPawn::GetPhysicsAssetPath,
		"SetFleeAnimationPath", &AGOIncRagdollPawn::SetFleeAnimationPath,
		"GetFleeAnimationPath", &AGOIncRagdollPawn::GetFleeAnimationPath,
		"SetMeshRelativeLocation", &AGOIncRagdollPawn::SetMeshRelativeLocation,
		"GetMeshRelativeLocation", &AGOIncRagdollPawn::GetMeshRelativeLocation,
		"SetMeshRelativeScale", &AGOIncRagdollPawn::SetMeshRelativeScale,
		"GetMeshRelativeScale", &AGOIncRagdollPawn::GetMeshRelativeScale,
		"SetAliveCapsuleSize", &AGOIncRagdollPawn::SetAliveCapsuleSize,
		"GetAliveCapsuleRadius", &AGOIncRagdollPawn::GetAliveCapsuleRadius,
		"GetAliveCapsuleHalfHeight", &AGOIncRagdollPawn::GetAliveCapsuleHalfHeight,
		"SetReviveTriggerCapsuleSize", &AGOIncRagdollPawn::SetReviveTriggerCapsuleSize,
		"GetReviveTriggerCapsuleRadius", &AGOIncRagdollPawn::GetReviveTriggerCapsuleRadius,
		"GetReviveTriggerCapsuleHalfHeight", &AGOIncRagdollPawn::GetReviveTriggerCapsuleHalfHeight,
		"CanRevive", &AGOIncRagdollPawn::CanRevive,
		"GetReviveBlendDuration", &AGOIncRagdollPawn::GetReviveBlendDuration,
		"GetFleeSpeed", &AGOIncRagdollPawn::GetFleeSpeed,
		"GetFleeAcceleration", &AGOIncRagdollPawn::GetFleeAcceleration,
		"GetFleeBrakingDeceleration", &AGOIncRagdollPawn::GetFleeBrakingDeceleration,
		"GetFleeEndDistance", &AGOIncRagdollPawn::GetFleeEndDistance,
		"GetFleeStopDuration", &AGOIncRagdollPawn::GetFleeStopDuration,
		"GetFleeStopMinBrakingDeceleration", &AGOIncRagdollPawn::GetFleeStopMinBrakingDeceleration,
		"GetFleeRotationYawOffsetDegrees", &AGOIncRagdollPawn::GetFleeRotationYawOffsetDegrees,
		"GetFleeAnimationBaseSpeed", &AGOIncRagdollPawn::GetFleeAnimationBaseSpeed,
		"GetFleeAnimationMinPlayRate", &AGOIncRagdollPawn::GetFleeAnimationMinPlayRate,
		"GetFleeAnimationMaxPlayRate", &AGOIncRagdollPawn::GetFleeAnimationMaxPlayRate,
		"GetFleeStopStartPlayRate", &AGOIncRagdollPawn::GetFleeStopStartPlayRate,
		"GetFleeStopEndPlayRate", &AGOIncRagdollPawn::GetFleeStopEndPlayRate,
		"UpdateDeadRootFromRagdollSafe", &AGOIncRagdollPawn::UpdateDeadRootFromRagdollSafe,
		"PrepareReviveFromRagdoll", &AGOIncRagdollPawn::PrepareReviveFromRagdoll,
		"EnterDeadRagdollState", &AGOIncRagdollPawn::EnterDeadRagdollState,
		"EnterRevivingState", &AGOIncRagdollPawn::EnterRevivingState,
		"EnterAliveFleeState", &AGOIncRagdollPawn::EnterAliveFleeState,
		"RequestDeadRagdoll", &AGOIncRagdollPawn::RequestDeadRagdoll,
		"ShowAliveExclamation", &AGOIncRagdollPawn::ShowAliveExclamation,
		"PlayFleeAnimation", &AGOIncRagdollPawn::PlayFleeAnimation,
		"StopFleeAnimation", &AGOIncRagdollPawn::StopFleeAnimation);

	{
		sol::table ActorType = Lua["Actor"];
		if (ActorType.valid())
		{
			ActorType.set_function("AsGOIncRagdollPawn", [](AActor& Actor) -> AGOIncRagdollPawn*
			{
				return Cast<AGOIncRagdollPawn>(&Actor);
			});
		}
	}
}

// 자기-등록 — Editor / Game 측이 RegisterGameLuaBindings 함수명을 모르고도
// FEngineInitHooks::RunAll() 한 번이면 호출되도록 static initializer 로 등록.
namespace
{
	void RunRegisterGameLuaBindings()
	{
		RegisterGameLuaBindings(FLuaScriptManager::GetState());
	}

	struct GameLuaBindingsAutoReg
	{
		GameLuaBindingsAutoReg() { FEngineInitHooks::Register(&RunRegisterGameLuaBindings); }
	};

	static GameLuaBindingsAutoReg gAutoReg;
}
