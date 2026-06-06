#pragma once

#include "GameFramework/Pawn/GOIncRagdollPawn.h"

#include "Source/Engine/GameFramework/Pawn/GOIncSonicRagdollPawn.generated.h"

// GOInc Sonic 전용 ragdoll Pawn.
// 공통 동작은 AGOIncRagdollPawn이 담당하고, 이 클래스는 Sonic 기본 캐릭터 설정만 제공한다.
UCLASS()
class AGOIncSonicRagdollPawn : public AGOIncRagdollPawn
{
public:
	GENERATED_BODY()

	AGOIncSonicRagdollPawn() = default;
	~AGOIncSonicRagdollPawn() override = default;

protected:
	FGOIncRagdollCharacterConfig MakeCharacterConfig() const override;
};
