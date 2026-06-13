#include "Game/GameActorPlacements.h"

#include "Engine/Runtime/ActorPlacementRegistry.h"
#include "Engine/Runtime/EngineInitHooks.h"
#include "Game/Actors/GOIncBasket.h"
#include "Game/Actors/GOIncIdCard.h"
#include "Game/Actors/GOIncTrashBox.h"
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

	// 순간이동 포탈 — 색상별로 배치 메뉴를 분리(0=하늘 1=분홍 2=노랑). 같은 색끼리 한 쌍이
	// 서로의 목적지가 된다. 색은 인스펙터의 Color Index로도 바꿀 수 있다(즉시 반영).
	{
		struct FPortalColorEntry { const char* Label; int32 ColorIndex; };
		static const FPortalColorEntry PortalEntries[] = {
			{ "Summon Portal (Cyan)",   0 },
			{ "Summon Portal (Pink)",   1 },
			{ "Summon Portal (Yellow)", 2 },
		};
		for (const FPortalColorEntry& E : PortalEntries)
		{
			const int32 Color = E.ColorIndex;
			FActorPlacementRegistry::Get().RegisterEntry(
				E.Label,
				[Color](UWorld* World, const FVector& Location) -> AActor*
				{
					ASummonPortalActor* Portal = World ? World->SpawnActor<ASummonPortalActor>() : nullptr;
					if (Portal)
					{
						Portal->ColorIndex = Color;       // InitDefaultComponents가 이 값으로 색 적용
						Portal->InitDefaultComponents();
						Portal->SetActorLocation(Location);
					}
					return Portal;
				});
		}
	}

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
		"GOInc TrashBox",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			AGOIncTrashBox* TrashBox = World ? World->SpawnActor<AGOIncTrashBox>() : nullptr;
			if (TrashBox)
			{
				TrashBox->InitDefaultComponents();
				TrashBox->SetActorLocation(Location);
			}
			return TrashBox;
		});

	FActorPlacementRegistry::Get().RegisterEntry(
		"GOInc Basket",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			AGOIncBasket* Basket = World ? World->SpawnActor<AGOIncBasket>() : nullptr;
			if (Basket)
			{
				Basket->InitDefaultComponents();
				Basket->SetActorLocation(Location);
			}
			return Basket;
		});

	FActorPlacementRegistry::Get().RegisterEntry(
		"GOInc IdCard",
		[](UWorld* World, const FVector& Location) -> AActor*
		{
			AGOIncIdCard* IdCard = World ? World->SpawnActor<AGOIncIdCard>() : nullptr;
			if (IdCard)
			{
				IdCard->InitDefaultComponents();
				IdCard->SetActorLocation(Location);
			}
			return IdCard;
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
