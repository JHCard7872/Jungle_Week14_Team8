#include "Game/GameActorPlacements.h"

#include "Engine/Runtime/ActorPlacementRegistry.h"
#include "Engine/Runtime/EngineInitHooks.h"
#include "Game/Actors/GOIncTruck.h"
#include "Game/Actors/SummonPortalActor.h"
#include "Game/GOIncRagdollCharacterRegistry.h"
#include "GameFramework/Actor/4WVehicleActor.h"
#include "GameFramework/Actor/PhysicalAnimationActor.h"
#include "GameFramework/Actor/RagdollActor.h"
#include "GameFramework/Pawn/GOIncRagdollPawn.h"
#include "GameFramework/World.h"

void RegisterGameActorPlacements()
{
	FActorPlacementRegistry::Get().RegisterEntry(
		"Ragdoll Actor",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			ARagdollActor* Actor = World ? World->SpawnActor<ARagdollActor>() : nullptr;
			if (Actor)
			{
				Actor->InitDefaultComponents();
				Actor->SetActorLocation(Location);
			}
			return Actor;
		});

	FActorPlacementRegistry::Get().RegisterEntry(
		"Physical Animation Actor",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			APhysicalAnimationActor* Actor = World ? World->SpawnActor<APhysicalAnimationActor>() : nullptr;
			if (Actor)
			{
				Actor->InitDefaultComponents();
				Actor->SetActorLocation(Location);
			}
			return Actor;
		});

	FActorPlacementRegistry::Get().RegisterEntry(
		"GOInc Ragdoll Pawn",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			AGOIncRagdollPawn* Pawn = World ? World->SpawnActor<AGOIncRagdollPawn>() : nullptr;
			if (Pawn)
			{
				Pawn->InitDefaultComponents();
				Pawn->SetActorLocation(Location);
			}
			return Pawn;
		});

	// GOInc 전용 Ragdoll Pawn들은 중앙 registry를 기준으로 등록한다.
	// 이렇게 해두면 Lua SpawnRagdollCharacter와 Editor Place Actor 메뉴의 id/class 매핑이 어긋나지 않는다.
	for (const FGOIncRagdollCharacterSpawnEntry& Entry : GetGOIncRagdollCharacterSpawnEntries())
	{
		auto SpawnFn = Entry.SpawnFn;
		FActorPlacementRegistry::Get().RegisterEntry(
			Entry.PlacementLabel,
			[SpawnFn](UWorld* World, const FVector& Location) -> AActor*
			{
				return SpawnFn ? SpawnFn(World, Location) : nullptr;
			});
	}

	FActorPlacementRegistry::Get().RegisterEntry(
		"Summon Portal",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			ASummonPortalActor* Portal = World ? World->SpawnActor<ASummonPortalActor>() : nullptr;
			if (Portal)
			{
				Portal->InitDefaultComponents();
				Portal->SetActorLocation(Location);
			}
			return Portal;
		});

	FActorPlacementRegistry::Get().RegisterEntry(
		"GOInc Truck",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			AGOIncTruck* Truck = World ? World->SpawnActor<AGOIncTruck>() : nullptr;
			if (Truck)
			{
				Truck->InitDefaultComponents();
				Truck->SetActorLocation(Location);
			}
			return Truck;
		});

	FActorPlacementRegistry::Get().RegisterEntry(
		"4W Vehicle",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			A4WVehicleActor* Vehicle = World ? World->SpawnActor<A4WVehicleActor>() : nullptr;
			if (Vehicle)
			{
				Vehicle->InitDefaultComponents();
				Vehicle->SetActorLocation(Location);
			}
			return Vehicle;
		});
}

namespace
{
	struct GameActorPlacementsAutoReg
	{
		GameActorPlacementsAutoReg() { FEngineInitHooks::Register(&RegisterGameActorPlacements); }
	};

	static GameActorPlacementsAutoReg gAutoReg;
}
