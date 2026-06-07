#pragma once

#include "GameFramework/Pawn/GOIncRagdollPawn.h"

#include "Source/Engine/GameFramework/Pawn/GOIncEggmanRagdollPawn.generated.h"

// GOInc Eggman 전용 ragdoll Pawn.
// 공통 동작은 AGOIncRagdollPawn이 담당하고, 이 클래스는 Eggman 기본 캐릭터 설정만 제공한다.
UCLASS()
class AGOIncEggmanRagdollPawn : public AGOIncRagdollPawn
{
public:
	GENERATED_BODY()

	AGOIncEggmanRagdollPawn() = default;
	~AGOIncEggmanRagdollPawn() override = default;

protected:
	FGOIncRagdollCharacterConfig MakeCharacterConfig() const override;
};
