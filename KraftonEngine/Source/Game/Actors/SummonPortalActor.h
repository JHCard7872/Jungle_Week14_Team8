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
// 수거(점수/소멸)는 링 안쪽 CollectTrigger + PortalBehavior.lua가 담당.
// ======================================================
UCLASS()
class ASummonPortalActor : public AActor
{
public:
	GENERATED_BODY()
	ASummonPortalActor() = default;
	~ASummonPortalActor() override = default;

	// 에디터 Place Actor / 코드 스폰 직후 호출 — 씬 로드 시에는 직렬화가 복원(이 함수 미호출).
	// 컴포넌트(빛기둥/파티클/트리거/스크립트)를 만들고, 끝에서 ColorIndex로 색을 적용한다.
	void InitDefaultComponents();

	// 색 적용(빛기둥 머티리얼 + "PortalColor{N}" 태그)을 ColorIndex 기준으로 (재)수행.
	// 배치/로드/스폰 경로가 달라도 BeginPlay에서 한 번 더 불러 일관성을 보장한다.
	void ApplyPortalColor();

	// 배치/로드/스폰 무관하게 게임 시작 시 컴포넌트 보강 + 색·태그 적용.
	void BeginPlay() override;
	// 씬 로드(에디터 열기 + PIE) 직후 1회 — 최소 직렬화된 포탈의 컴포넌트를 구성(에디터에도 표시).
	void PostLoadSceneActor() override;
	// 에디터 인스펙터에서 ColorIndex를 바꾸면 즉시 색/태그 반영.
	void PostEditProperty(const char* PropertyName) override;

	// 에디터에서 인스턴스별로 지정하는 포탈 색(쌍 식별). 0=하늘 1=분홍 2=노랑.
	UPROPERTY(Edit, Save, Category="SummonPortal", DisplayName="Color Index", Min=0, Max=2)
	int32 ColorIndex = 0;
};
