#pragma once

#include "Core/Types/CoreTypes.h"

struct FVector;
class UWorld;
class AGOIncRagdollPawn;

// GOInc ragdoll 캐릭터 id와 실제 C++ Pawn spawn 함수를 연결하는 중앙 registry.
// RagdollData.lua, Lua spawn binding, Editor Place Actor UI가 같은 id 목록을 공유하게 만든다.
struct FGOIncRagdollCharacterSpawnEntry
{
	FString CharacterId;
	FString PlacementLabel;
	AGOIncRagdollPawn* (*SpawnFn)(UWorld* World, const FVector& Location);
};

const TArray<FGOIncRagdollCharacterSpawnEntry>& GetGOIncRagdollCharacterSpawnEntries();
const FGOIncRagdollCharacterSpawnEntry* FindGOIncRagdollCharacterSpawnEntry(const FString& CharacterId);
bool IsGOIncRagdollCharacterRegistered(const FString& CharacterId);
AGOIncRagdollPawn* SpawnGOIncRagdollCharacter(UWorld* World, const FString& CharacterId, const FVector& Location);
