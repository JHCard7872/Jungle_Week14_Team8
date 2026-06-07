#pragma once

#include "GameFramework/Pawn/GOIncRagdollPawn.h"

#include "Source/Engine/GameFramework/Pawn/GOIncBowserRagdollPawn.generated.h"

// GOInc Bowser 전용 ragdoll Pawn.
// 공통 동작은 AGOIncRagdollPawn이 담당하고, 이 클래스는 Bowser 기본 캐릭터 설정만 제공한다.
UCLASS()
class AGOIncBowserRagdollPawn : public AGOIncRagdollPawn
{
public:
	GENERATED_BODY()

	AGOIncBowserRagdollPawn() = default;
	~AGOIncBowserRagdollPawn() override = default;

protected:
	FGOIncRagdollCharacterConfig MakeCharacterConfig() const override;
};
