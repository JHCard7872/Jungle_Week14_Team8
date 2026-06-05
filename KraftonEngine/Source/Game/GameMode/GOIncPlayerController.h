#pragma once

#include "GameFramework/GameMode/PlayerController.h"

#include "Source/Game/GameMode/GOIncPlayerController.generated.h"

// ============================================================
// AGOIncPlayerController — 플레이어 조종자 + 페이즈별 입력 게이팅
//
// 역할:
//   · 회수 직원 Pawn을 Possess한다 (베이스 APlayerController 기능 그대로).
//   · "게임플레이 입력 허용" 플래그(bGameplayInputEnabled)를 보유한다 —
//     Playing 페이즈에서만 true. 캐릭터 이동/건 입력 콜백이 이 플래그를 검사해
//     Paused/Result 중에는 입력을 무시한다.
//     (아키텍처 문서 §6-A "간단 Input Context" 방식 — 페이즈 enum 한 줄로 게이팅)
//   · 플래그 값은 AGOIncGameMode가 페이즈 전이 시점에 세팅한다. PC는 들고만 있는다.
//
// 참고: 메뉴 네비게이션(타이틀/일시정지 UI)은 이 게이트와 무관하게
//       UIManager / Engine.SetOnEscape 경로로 처리한다(월드 pause 중에도 동작).
// ============================================================
UCLASS()
class AGOIncPlayerController : public APlayerController
{
public:
	GENERATED_BODY()
	AGOIncPlayerController() = default;
	~AGOIncPlayerController() override = default;

	// 게임플레이 입력 허용 여부. 입력 콜백이 진입부에서 검사한다.
	bool IsGameplayInputEnabled() const { return bGameplayInputEnabled; }

	// GameMode가 페이즈 전이 시 호출 (Playing이면 true, 그 외 false).
	void SetGameplayInputEnabled(bool bEnabled) { bGameplayInputEnabled = bEnabled; }

private:
	bool bGameplayInputEnabled = false;
};
