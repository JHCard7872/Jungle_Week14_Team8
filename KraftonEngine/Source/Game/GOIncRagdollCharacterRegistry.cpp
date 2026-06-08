#include "Game/GOIncRagdollCharacterRegistry.h"

#include "GameFramework/Pawn/GOIncBowserRagdollPawn.h"
#include "GameFramework/Pawn/GOIncChiefRagdollPawn.h"
#include "GameFramework/Pawn/GOIncEggmanRagdollPawn.h"
#include "GameFramework/Pawn/GOIncKirbyRagdollPawn.h"
#include "GameFramework/Pawn/GOIncLaraRagdollPawn.h"
#include "GameFramework/Pawn/GOIncLinkRagdollPawn.h"
#include "GameFramework/Pawn/GOIncMarioRagdollPawn.h"
#include "GameFramework/Pawn/GOIncPikachuRagdollPawn.h"
#include "GameFramework/Pawn/GOIncRagdollPawn.h"
#include "GameFramework/Pawn/GOIncSonicRagdollPawn.h"
#include "GameFramework/World.h"

namespace
{
	template <typename TPawn>
	AGOIncRagdollPawn* SpawnTypedGOIncRagdollPawn(UWorld* World, const FVector& Location)
	{
		if (!World)
		{
			return nullptr;
		}

		return World->SpawnActorWithInitializer<TPawn>(
			[&](TPawn* Pawn)
			{
				if (!Pawn)
				{
					return;
				}

				Pawn->InitDefaultComponents();
				Pawn->SetActorLocation(Location);
			});
	}
}

const TArray<FGOIncRagdollCharacterSpawnEntry>& GetGOIncRagdollCharacterSpawnEntries()
{
	static const TArray<FGOIncRagdollCharacterSpawnEntry> Entries =
	{
		{ "red-plumber", "GOInc Mario Ragdoll Pawn", &SpawnTypedGOIncRagdollPawn<AGOIncMarioRagdollPawn> },
		{ "blue-speedster", "GOInc Sonic Ragdoll Pawn", &SpawnTypedGOIncRagdollPawn<AGOIncSonicRagdollPawn> },
		{ "pink-round", "GOInc Kirby Ragdoll Pawn", &SpawnTypedGOIncRagdollPawn<AGOIncKirbyRagdollPawn> },
		{ "yellow-mouse", "GOInc Pikachu Ragdoll Pawn", &SpawnTypedGOIncRagdollPawn<AGOIncPikachuRagdollPawn> },
		{ "spiked-king", "GOInc Bowser Ragdoll Pawn", &SpawnTypedGOIncRagdollPawn<AGOIncBowserRagdollPawn> },
		{ "egg-scientist", "GOInc Eggman Ragdoll Pawn", &SpawnTypedGOIncRagdollPawn<AGOIncEggmanRagdollPawn> },
		{ "green-swordsman", "GOInc Link Ragdoll Pawn", &SpawnTypedGOIncRagdollPawn<AGOIncLinkRagdollPawn> },
		{ "space-chief", "GOInc Chief Ragdoll Pawn", &SpawnTypedGOIncRagdollPawn<AGOIncChiefRagdollPawn> },
		{ "adventurer", "GOInc Lara Ragdoll Pawn", &SpawnTypedGOIncRagdollPawn<AGOIncLaraRagdollPawn> },
	};

	return Entries;
}

const FGOIncRagdollCharacterSpawnEntry* FindGOIncRagdollCharacterSpawnEntry(const FString& CharacterId)
{
	for (const FGOIncRagdollCharacterSpawnEntry& Entry : GetGOIncRagdollCharacterSpawnEntries())
	{
		if (Entry.CharacterId == CharacterId)
		{
			return &Entry;
		}
	}

	return nullptr;
}

bool IsGOIncRagdollCharacterRegistered(const FString& CharacterId)
{
	return FindGOIncRagdollCharacterSpawnEntry(CharacterId) != nullptr;
}

AGOIncRagdollPawn* SpawnGOIncRagdollCharacter(UWorld* World, const FString& CharacterId, const FVector& Location)
{
	const FGOIncRagdollCharacterSpawnEntry* Entry = FindGOIncRagdollCharacterSpawnEntry(CharacterId);
	if (!Entry || !Entry->SpawnFn)
	{
		return nullptr;
	}

	return Entry->SpawnFn(World, Location);
}
