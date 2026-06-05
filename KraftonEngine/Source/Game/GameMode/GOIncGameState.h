#pragma once

#include "GameFramework/GameMode/GameStateBase.h"

#include "Source/Game/GameMode/GOIncGameState.generated.h"

// ============================================================
// AGOIncGameState — "게임오버 주식회사(GOInc)"의 런타임 상태(데이터) 보유
//
// 역할:
//   · 한 판(match) 동안의 수치 상태만 들고 있는다 — 점수 / 남은 시간 / 서버 부하.
//   · 로직은 없다. 갱신은 AGOIncGameMode(C++) 또는 Lua(Game.lua)가 한다.
//   · 모든 필드가 UPROPERTY(reflected)라 UI(RmlUi)/Lua가 Reflection으로 읽는다.
//       예) Lua: World.FindFirstActorByClass("AGOIncGameState"):GetProperty("Score")
//   · 월드 종속이라 씬 전환 시 소멸한다 — 씬을 넘겨야 하는 "최종 점수"는 별도의 Lua 모듈(require)에 둔다.
// ============================================================
UCLASS()
class AGOIncGameState : public AGameStateBase
{
public:
	GENERATED_BODY()
	AGOIncGameState() = default;
	~AGOIncGameState() override = default;

	// 새 판 시작 시 GameMode가 호출 — 수치를 초기화한다.
	void ResetForNewMatch(float InTimeLimit)
	{
		Score = 0;
		ServerLoad = 0.0f;
		RemainingTime = InTimeLimit;
	}

	// 현재 점수. 래그돌 수거/미션 완료 시 누적.
	UPROPERTY(Transient, Category="GOInc", DisplayName="Score")
	int32 Score = 0;

	// 남은 제한 시간(초). 0이 되면 GameMode가 Result로 전이.
	UPROPERTY(Transient, Category="GOInc", DisplayName="Remaining Time")
	float RemainingTime = 0.0f;

	// 서버 과부하 게이지(0~100). 100이면 GameMode가 Result로 전이.
	UPROPERTY(Transient, Category="GOInc", DisplayName="Server Load")
	float ServerLoad = 0.0f;
};
