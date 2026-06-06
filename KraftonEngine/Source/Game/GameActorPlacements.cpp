#include "Game/GameActorPlacements.h"

#include "Engine/Runtime/ActorPlacementRegistry.h"
#include "Engine/Runtime/EngineInitHooks.h"
#include "Game/Actors/GOIncTruck.h"
#include "GameFramework/Actor/4WVehicleActor.h"
#include "GameFramework/Actor/PhysicalAnimationActor.h"
#include "GameFramework/Actor/RagdollActor.h"
#include "GameFramework/Pawn/GOIncRagdollPawn.h"
#include "GameFramework/Pawn/GOIncDonkeyKongRagdollPawn.h"
#include "GameFramework/Pawn/GOIncKirbyRagdollPawn.h"
#include "GameFramework/Pawn/GOIncPikachuRagdollPawn.h"
#include "GameFramework/Pawn/GOIncSonicRagdollPawn.h"
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

	FActorPlacementRegistry::Get().RegisterEntry(
		"GOInc Sonic Ragdoll Pawn",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			AGOIncSonicRagdollPawn* Pawn = World ? World->SpawnActor<AGOIncSonicRagdollPawn>() : nullptr;
			if (Pawn)
			{
				Pawn->InitDefaultComponents();
				Pawn->SetActorLocation(Location);
			}
			return Pawn;
		});

	FActorPlacementRegistry::Get().RegisterEntry(
		"GOInc Kirby Ragdoll Pawn",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			AGOIncKirbyRagdollPawn* Pawn = World ? World->SpawnActor<AGOIncKirbyRagdollPawn>() : nullptr;
			if (Pawn)
			{
				Pawn->InitDefaultComponents();
				Pawn->SetActorLocation(Location);
			}
			return Pawn;
		});

	FActorPlacementRegistry::Get().RegisterEntry(
		"GOInc Donkey Kong Ragdoll Pawn",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			AGOIncDonkeyKongRagdollPawn* Pawn = World ? World->SpawnActor<AGOIncDonkeyKongRagdollPawn>() : nullptr;
			if (Pawn)
			{
				Pawn->InitDefaultComponents();
				Pawn->SetActorLocation(Location);
			}
			return Pawn;
		});

	FActorPlacementRegistry::Get().RegisterEntry(
		"GOInc Pikachu Ragdoll Pawn",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			AGOIncPikachuRagdollPawn* Pawn = World ? World->SpawnActor<AGOIncPikachuRagdollPawn>() : nullptr;
			if (Pawn)
			{
				Pawn->InitDefaultComponents();
				Pawn->SetActorLocation(Location);
			}
			return Pawn;
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
