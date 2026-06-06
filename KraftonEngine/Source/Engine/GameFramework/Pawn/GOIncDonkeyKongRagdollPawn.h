#pragma once

#include "GameFramework/Pawn/GOIncRagdollPawn.h"

#include "Source/Engine/GameFramework/Pawn/GOIncDonkeyKongRagdollPawn.generated.h"

// GOInc Donkey Kong 전용 ragdoll Pawn.
// 공통 동작은 AGOIncRagdollPawn이 담당하고, 이 클래스는 Donkey Kong 기본 캐릭터 설정만 제공한다.
UCLASS()
class AGOIncDonkeyKongRagdollPawn : public AGOIncRagdollPawn
{
public:
	GENERATED_BODY()

	AGOIncDonkeyKongRagdollPawn() = default;
	~AGOIncDonkeyKongRagdollPawn() override = default;

protected:
	FGOIncRagdollCharacterConfig MakeCharacterConfig() const override;
};
