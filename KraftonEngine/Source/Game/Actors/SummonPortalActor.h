#pragma once

#include "GameFramework/AActor.h"

#include "Source/Game/Actors/SummonPortalActor.generated.h"

// ======================================================
// ASummonPortalActor — 소환진 이펙트 + 래그돌 수거함 액터 (WannabePortal_2)
// 빛기둥은 파티클이 아니라 메시로 만든다 — Root 아래에
// 가산(additive) 쿼드 20개를 링 둘레에 13도 기울여 세우고,
// RotatingMovementComponent가 Root를 Z축으로 돌린다.
// (회전은 PIE/게임에서만 — 에디터 배치 상태는 정지)
// 바닥은 FX_StrangePortal 파티클이 담당.
// 수거(점수/소멸)는 링 안쪽 CollectTrigger + CollectorBehavior.lua가 담당.
// ======================================================
UCLASS()
class ASummonPortalActor : public AActor
{
public:
	GENERATED_BODY()
	ASummonPortalActor() = default;
	~ASummonPortalActor() override = default;

	// 에디터 Place Actor / 코드 스폰 직후 호출 — 씬 로드 시에는 직렬화가 복원
	void InitDefaultComponents();
};
