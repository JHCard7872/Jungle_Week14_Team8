#pragma once

#include "GameFramework/Pawn/GOIncRagdollPawn.h"

#include "Source/Engine/GameFramework/Pawn/GOIncChiefRagdollPawn.generated.h"

// GOInc Chief 전용 ragdoll Pawn.
// 공통 동작은 AGOIncRagdollPawn이 담당하고, 이 클래스는 Chief 기본 캐릭터 설정만 제공한다.
UCLASS()
class AGOIncChiefRagdollPawn : public AGOIncRagdollPawn
{
public:
	GENERATED_BODY()

	AGOIncChiefRagdollPawn() = default;
	~AGOIncChiefRagdollPawn() override = default;

protected:
	FGOIncRagdollCharacterConfig MakeCharacterConfig() const override;
};
