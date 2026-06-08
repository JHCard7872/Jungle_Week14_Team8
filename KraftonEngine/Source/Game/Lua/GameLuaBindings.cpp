#include "Game/Lua/GameLuaBindings.h"

#include "sol/sol.hpp"

#include "Component/Movement/GOIncRagdollMovementComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Component/PrimitiveComponent.h"
#include "Component/Script/LuaScriptComponent.h"
#include "Component/Shape/BoxComponent.h"
#include "Component/Shape/CapsuleComponent.h"
#include "Component/ShapeComponent.h"
#include "Core/Types/CollisionTypes.h"
#include "Core/Logging/Log.h"
#include "Engine/Runtime/Engine.h"
#include "Engine/Runtime/EngineInitHooks.h"
#include "Game/Actors/SummonPortalActor.h"
#include "Game/GOIncRagdollCharacterRegistry.h"
#include "GameFramework/AActor.h"
#include "GameFramework/GameMode/GameplayStatics.h"
#include "GameFramework/Pawn/GOIncRagdollPawn.h"
#include "GameFramework/World.h"
#include "Lua/LuaScriptManager.h"
#include "Materials/Material.h"
#include "Materials/MaterialManager.h"
#include "Math/Transform.h"
#include "Particles/ParticleSystem.h"
#include "Particles/ParticleSystemManager.h"
#include "Particles/ParticleEmitter.h"
#include "Particles/ParticleLODLevel.h"
#include "Particles/ParticleModuleRequired.h"
#include "Particles/Spawn/ParticleModuleSpawn.h"
#include "Particles/Lifetime/ParticleModuleLifetime.h"
#include "Particles/Velocity/ParticleModuleVelocity.h"
#include "Particles/Size/ParticleModuleSize.h"
#include "Particles/Size/ParticleModuleSizeOverLife.h"
#include "Particles/Color/ParticleModuleColor.h"
#include "Distributions/DistributionVector.h"
#include "Distributions/DistributionFloat.h"

#include <algorithm>
#include <cctype>
#include <random>

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
	// ===== 파티클 베이커 헬퍼 (수거 FX_CollectPop 생성용, 개발 1회용) =====
	// 기본 스프라이트 이미터가 만들어 둔 모듈을 찾아 in-place로 다듬기 위한 헬퍼들.
	template<typename T>
	T* FindParticleModule(UParticleLODLevel* LOD)
	{
		for (auto& Module : LOD->Modules)
		{
			if (T* Typed = Cast<T>(Module)) return Typed;
		}
		return nullptr;
	}

	void SetVecUniform(FRawDistributionVector& Dist, UObject* Owner, const FVector& Min, const FVector& Max)
	{
		UDistributionVectorUniform* U = UObjectManager::Get().CreateObject<UDistributionVectorUniform>(Owner);
		U->Min = Min;
		U->Max = Max;
		Dist.Distribution = U;
	}

	void SetVecConstant(FRawDistributionVector& Dist, UObject* Owner, const FVector& Value)
	{
		UDistributionVectorConstant* K = UObjectManager::Get().CreateObject<UDistributionVectorConstant>(Owner);
		K->Constant = Value;
		Dist.Distribution = K;
	}

	void SetFloatConstant(FRawDistributionFloat& Dist, UObject* Owner, float Value)
	{
		UDistributionFloatConstant* K = UObjectManager::Get().CreateObject<UDistributionFloatConstant>(Owner);
		K->Constant = Value;
		Dist.Distribution = K;
	}

	// 기본 스프라이트 이미터를 만든 뒤 t=0 버스트 단발로 바꾸고 속도/크기/색/수명을 다듬어
	// 한 emitter를 구성한다. SizeOverLife로 수명에 따른 축소 페이드를 더한다.
	UParticleEmitter* BuildCollectPopEmitter(
		UParticleSystem* System, const char* Name,
		int32 BurstCount, float LifeMin, float LifeMax,
		const FVector& VelMin, const FVector& VelMax, float VelRadial,
		const FVector& SizeMin, const FVector& SizeMax,
		float ScaleStart, float ScaleEnd,
		const FVector& Color, float Alpha)
	{
		UParticleEmitter* Emitter = UObjectManager::Get().CreateObject<UParticleEmitter>(System);
		Emitter->InitializeDefaultSpriteEmitter();   // Required/Spawn/Lifetime/Location/Velocity/Size/Color 생성
		Emitter->EmitterName = FName(Name);

		UParticleLODLevel* LOD = Emitter->GetLODLevel(0);
		if (!LOD) return Emitter;

		// Required: 1초 단발(one-shot). 기본은 무한 루프(0)라 버스트가 1초마다 재발사됨
		if (LOD->RequiredModule)
		{
			LOD->RequiredModule->EmitterDuration = 1.0f;
			LOD->RequiredModule->EmitterLoops    = 1;
		}

		// Spawn: 연속 분사 끄고 t=0 버스트로 한 번에 "팍"
		if (LOD->SpawnModule)
		{
			LOD->SpawnModule->SpawnRate = 0.0f;
			FParticleBurst Burst;
			Burst.Count    = BurstCount;
			Burst.CountLow = -1;
			Burst.Time     = 0.0f;
			LOD->SpawnModule->BurstList.push_back(Burst);
		}

		if (UParticleModuleLifetime* Lifetime = FindParticleModule<UParticleModuleLifetime>(LOD))
		{
			Lifetime->LifetimeMin = LifeMin;
			Lifetime->LifetimeMax = LifeMax;
		}
		if (UParticleModuleVelocity* Velocity = FindParticleModule<UParticleModuleVelocity>(LOD))
		{
			SetVecUniform(Velocity->StartVelocity, Velocity, VelMin, VelMax);
			SetFloatConstant(Velocity->StartVelocityRadial, Velocity, VelRadial);
		}
		if (UParticleModuleSize* Size = FindParticleModule<UParticleModuleSize>(LOD))
		{
			SetVecUniform(Size->StartSize, Size, SizeMin, SizeMax);
		}
		if (UParticleModuleColor* ColorMod = FindParticleModule<UParticleModuleColor>(LOD))
		{
			SetVecConstant(ColorMod->StartColor, ColorMod, Color);
			SetFloatConstant(ColorMod->StartAlpha, ColorMod, Alpha);
		}

		// 수명에 따라 크기 축소(반짝→사라짐, 팍→수축) — 기본 이미터엔 없어서 추가
		UParticleModuleSizeOverLife* SizeOverLife = UObjectManager::Get().CreateObject<UParticleModuleSizeOverLife>(LOD);
		SizeOverLife->bEnabled   = true;
		SizeOverLife->ScaleStart = ScaleStart;
		SizeOverLife->ScaleEnd   = ScaleEnd;
		LOD->Modules.push_back(SizeOverLife);

		LOD->UpdateModuleLists();        // 구조 변경(모듈 추가) 후 필수
		Emitter->CacheEmitterModuleInfo();   // 페이로드 오프셋 재계산

		System->GetEmitters().push_back(Emitter);   // 완성된 emitter를 시스템에 등록 — 빠지면 빈 에셋이 저장됨
		return Emitter;
	}

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

	float RandomFloatInRange(float MinValue, float MaxValue)
	{
		static thread_local std::mt19937 Generator(std::random_device{}());
		std::uniform_real_distribution<float> Distribution(MinValue, MaxValue);
		return Distribution(Generator);
	}

	FVector MakeRandomPointInBoxComponent(const UBoxComponent& BoxComponent)
	{
		const FVector Extent = BoxComponent.GetUnscaledBoxExtent();
		// SpawnArea Box는 XY 범위 마커로 사용한다. Z는 Box 중심 높이를 그대로 쓴다.
		const FVector LocalPoint(
			RandomFloatInRange(-Extent.X, Extent.X),
			RandomFloatInRange(-Extent.Y, Extent.Y),
			0.0f);

		return BoxComponent.GetWorldMatrix().TransformPositionWithW(LocalPoint);
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

		// 소환 포탈 코드 스폰 — 판 시작 시 PlayScene이 1회 호출. 위치는 스폰하지 않고
		// PortalBehavior.lua BeginPlay가 PortalData 좌표로 잡는다(미션마다 재배치).
		// InitDefaultComponents가 BeginPlay보다 먼저 돌도록 Initializer 형태로 스폰한다.
		GOInc.set_function("SpawnSummonPortal", []() -> ASummonPortalActor*
		{
			if (!GEngine)
			{
				UE_LOG("[GOInc] SpawnSummonPortal failed. Missing GEngine.");
				return nullptr;
			}

			UWorld* World = GEngine->GetWorld();
			if (!World)
			{
				UE_LOG("[GOInc] SpawnSummonPortal failed. Missing World.");
				return nullptr;
			}

			ASummonPortalActor* Portal = World->SpawnActorWithInitializer<ASummonPortalActor>(
				[](ASummonPortalActor* P)
				{
					if (P)
					{
						P->InitDefaultComponents();
					}
				});

			if (!Portal)
			{
				UE_LOG("[GOInc] SpawnSummonPortal failed.");
				return nullptr;
			}

			UE_LOG("[GOInc] Spawned summon portal.");
			return Portal;
		});

		// 수거 "뾰로롱 팍" 파티클을 코드로 구워 Content/Particle/FX_CollectPop.uasset 생성.
		// 개발 1회용 — 콘솔에서 한 번 호출해 에셋을 만든 뒤 에디터에서 미세조정·커밋한다.
		// Sparkle(부드러운 반짝) + Burst(방사형 폭발) 2-emitter 구성.
		GOInc.set_function("BakeCollectPopFX", []() -> bool
		{
			UParticleSystem* System = UObjectManager::Get().CreateObject<UParticleSystem>();
			if (!System)
			{
				UE_LOG("[GOInc] BakeCollectPopFX failed. CreateObject<UParticleSystem> null.");
				return false;
			}

			// Sparkle(뾰로롱): 약한 상향 드리프트 + 작은 크기 + 따뜻한 흰색, 반짝 사라짐
			BuildCollectPopEmitter(System, "Sparkle",
				14, 0.45f, 0.60f,
				FVector(-0.6f, -0.6f, 0.8f), FVector(0.6f, 0.6f, 2.0f), 0.5f,
				FVector(8.0f, 8.0f, 8.0f), FVector(18.0f, 18.0f, 18.0f),
				1.0f, 0.0f,
				FVector(1.0f, 0.95f, 0.6f), 1.0f);

			// Burst(팍): 강한 방사형 외향 속도 + 살짝 큰 크기 + 짧은 수명, 확장 후 수축
			BuildCollectPopEmitter(System, "Burst",
				28, 0.40f, 0.50f,
				FVector(-2.5f, -2.5f, 0.0f), FVector(2.5f, 2.5f, 1.2f), 4.0f,
				FVector(14.0f, 14.0f, 14.0f), FVector(26.0f, 26.0f, 26.0f),
				1.2f, 0.0f,
				FVector(1.0f, 0.85f, 0.4f), 1.0f);

			System->SetSourcePath("Content/Particle/FX_CollectPop.uasset");
			const bool bSaved = FParticleSystemManager::Get().Save(System);

			UObjectManager::Get().DestroyObject(System);   // 베이커가 소유 — 저장 후 해제

			if (!bSaved)
			{
				UE_LOG("[GOInc] BakeCollectPopFX: Save failed.");
				return false;
			}
			UE_LOG("[GOInc] BakeCollectPopFX: saved Content/Particle/FX_CollectPop.uasset");
			return true;
		});

		GOInc.set_function("IsRagdollCharacterRegistered", [](const FString& CharacterId) -> bool
		{
			return IsGOIncRagdollCharacterRegistered(CharacterId);
		});

		// SpawnArea는 별도 C++ Actor를 만들지 않고, 일반 Actor Tag + 하위 BoxComponent로 찾는다.
		// SpawnManager Lua가 BeginPlay에서 한 번만 호출해 캐싱하고 Tick에서는 월드 검색하지 않는다.
		GOInc.set_function("FindSpawnAreaBoxes", [](const FString& TagName, sol::this_state State) -> sol::table
		{
			sol::state_view L(State);
			sol::table Result = L.create_table();

			UWorld* World = GEngine ? GEngine->GetWorld() : nullptr;
			if (!World)
			{
				UE_LOG("[GOInc] FindSpawnAreaBoxes failed. Missing World. Tag=%s", TagName.c_str());
				return Result;
			}

			const TArray<AActor*> AreaActors = FGameplayStatics::FindActorsByTag(World, FName(TagName));
			int32 ResultIndex = 1;
			int32 BoxCount = 0;

			for (AActor* Actor : AreaActors)
			{
				if (!IsValid(Actor))
				{
					continue;
				}

				for (UPrimitiveComponent* PrimitiveComponent : Actor->GetPrimitiveComponents())
				{
					UBoxComponent* BoxComponent = Cast<UBoxComponent>(PrimitiveComponent);
					if (!IsValid(BoxComponent))
					{
						continue;
					}

					Result[ResultIndex++] = BoxComponent;
					++BoxCount;
				}
			}

			UE_LOG("[GOInc] FindSpawnAreaBoxes Tag=%s Actors=%d Boxes=%d",
				TagName.c_str(),
				static_cast<int32>(AreaActors.size()),
				BoxCount);
			return Result;
		});

		GOInc.set_function("GetRandomPointInSpawnAreaBox", [](UBoxComponent* BoxComponent, sol::this_state State) -> sol::object
		{
			if (!IsValid(BoxComponent))
			{
				return MakeNil(State);
			}

			return sol::make_object(State, MakeRandomPointInBoxComponent(*BoxComponent));
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

	Lua.new_usertype<UBoxComponent>("BoxComponent",
		sol::base_classes,
		sol::bases<UShapeComponent, UPrimitiveComponent, USceneComponent, UActorComponent, UObject>(),
		"SetBoxExtent", &UBoxComponent::SetBoxExtent,
		"GetScaledBoxExtent", &UBoxComponent::GetScaledBoxExtent,
		"GetUnscaledBoxExtent", &UBoxComponent::GetUnscaledBoxExtent);

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
		"SetWallAvoidanceEnabled", &UGOIncRagdollMovementComponent::SetWallAvoidanceEnabled,
		"IsWallAvoidanceEnabled", &UGOIncRagdollMovementComponent::IsWallAvoidanceEnabled,
		"HasLastWallAvoidanceDirection", &UGOIncRagdollMovementComponent::HasLastWallAvoidanceDirection,
		"GetLastWallAvoidanceDirection", &UGOIncRagdollMovementComponent::GetLastWallAvoidanceDirection,
		"ClearLastWallAvoidanceDirection", &UGOIncRagdollMovementComponent::ClearLastWallAvoidanceDirection,
		"SetStepUpEnabled", &UGOIncRagdollMovementComponent::SetStepUpEnabled,
		"IsStepUpEnabled", &UGOIncRagdollMovementComponent::IsStepUpEnabled,
		"SetMaxStepHeight", &UGOIncRagdollMovementComponent::SetMaxStepHeight,
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
		"SetRagdollMassScale", &USkeletalMeshComponent::SetRagdollMassScale,
		"GetRagdollMassScale", &USkeletalMeshComponent::GetRagdollMassScale,
		"SetRagdollTotalMass", &USkeletalMeshComponent::SetRagdollTotalMass,
		"GetRagdollTotalMass", &USkeletalMeshComponent::GetRagdollTotalMass,
		"AddImpulseToBone", [](USkeletalMeshComponent& Component, const FString& BoneName, const FVector& Impulse)
		{
			Component.AddImpulseToBone(FName(BoneName), Impulse);
		},
		"AddRandomImpulseToAllRagdollBodies", &USkeletalMeshComponent::AddRandomImpulseToAllRagdollBodies,
		"AddDirectionalImpulseToAllRagdollBodies", &USkeletalMeshComponent::AddDirectionalImpulseToAllRagdollBodies,
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
