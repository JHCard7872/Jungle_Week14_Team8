#pragma once

#include "GameFramework/Pawn/GOIncRagdollPawn.h"

#include "Source/Engine/GameFramework/Pawn/GOIncLaraRagdollPawn.generated.h"

// GOInc Lara 전용 ragdoll Pawn.
// 공통 동작은 AGOIncRagdollPawn이 담당하고, 이 클래스는 Lara 기본 캐릭터 설정만 제공한다.
UCLASS()
class AGOIncLaraRagdollPawn : public AGOIncRagdollPawn
{
public:
	GENERATED_BODY()

	AGOIncLaraRagdollPawn() = default;
	~AGOIncLaraRagdollPawn() override = default;

protected:
	FGOIncRagdollCharacterConfig MakeCharacterConfig() const override;
};
