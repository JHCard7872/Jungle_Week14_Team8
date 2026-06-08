#pragma once

#include "GameFramework/AActor.h"

#include "Source/Game/Actors/GOIncIdCard.generated.h"

// ======================================================
// AGOIncIdCard — 떠다니는 신분증(id_card) 아이템 액터
// Root(SceneComponent) 아래 Billboard(id_card 머티리얼) + PortalFX(StrangePortal)
// + GrabBox 형제 구조. Bobbing이 Root를 Z축으로 위아래 왕복시킨다.
// GrabBox는 Gun 조준 레이캐스트(PrimitiveRaycast)에 걸리는 콜라이더 —
// QueryOnly·Kinematic으로 두고 채널/extent/물리 세부는 배치 후 에디터에서 튜닝한다.
// ======================================================
UCLASS()
class AGOIncIdCard : public AActor
{
public:
	GENERATED_BODY()
	AGOIncIdCard() = default;
	~AGOIncIdCard() override = default;

	// 에디터 Place Actor / 코드 스폰 직후 호출 — 씬 로드 시에는 직렬화가 복원
	void InitDefaultComponents();
};
