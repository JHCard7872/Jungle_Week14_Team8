#pragma once

#include "GameFramework/GameMode/GameModeBase.h"

#include "Source/Game/GameMode/GOIncGameMode.generated.h"

class ATriggerVolumeBase;
class APawn;

// GOInc 게임플레이 씬의 진행 단계.
// 3-씬 구성(Title / Gameplay / GameOver)에서 이 GameMode는 "게임플레이 씬"용이므로
// 실질적으로 Playing ↔ Paused 를 오간다. Title/Result는 페이즈 값으로도 들고 있지만
// 화면 자체는 별도 씬이 담당한다.
enum class EGOIncPhase : uint8
{
	Title,    // 타이틀 — Start 입력 대기 (보통 별도 Title 씬)
	Playing,  // 본 게임 — 타이머/스폰/부하/점수 가동, 입력 허용
	Paused,   // ESC 일시정지 오버레이 — 월드 정지, 게임플레이 입력 차단
	Result,   // 결과 — 점수 정산 (보통 GameOver 씬으로 전환)
};

// ============================================================
// AGOIncGameMode — GOInc 게임플레이 씬의 두뇌(룰 / 페이즈 FSM)
//
// 역할:
//   · 게임 페이즈 FSM(EGOIncPhase)을 소유하고 전이한다(SetPhase → OnEnterPhase).
//     페이즈 진입 시 월드 pause 토글 + PlayerController 입력 게이팅을 처리.
//   · 자기 전용 GameState/PlayerController 클래스를 지정해 엔진이 spawn하게 한다
//     (생성자에서 GameStateClass / PlayerControllerClass 세팅).
//   · 트럭/포탈 등 트리거 이벤트(OnPossessedPawnEnteredTrigger)를 받아
//     점수/페이즈 로직으로 변환하는 진입점이 된다.
//   · 세부 게임플레이(스폰/점수/미션/부하 규칙)는 Lua(Game.lua 모듈)가 담당한다.
//     이 클래스는 엔진 프레임워크와 Lua를 잇는 "골격"만 들고 있는다.
//
// 활성화 방법:
//   Scene의 WorldSettings.GameModeClassName 또는 ProjectSettings.GameModeClassName 을
//   "AGOIncGameMode" 로 지정. (우선순위: Scene → ProjectSettings → AGameModeBase fallback)
// ============================================================
UCLASS()
class AGOIncGameMode : public AGameModeBase
{
public:
	GENERATED_BODY()
	AGOIncGameMode();
	~AGOIncGameMode() override = default;

	// AGameModeBase — 모든 액터 BeginPlay 이후 World가 호출. PC spawn/Possess(베이스) 후
	// 게임플레이 씬을 Playing 페이즈로 진입시킨다.
	void StartMatch() override;

	// 트럭/포탈 트리거에 possessed Pawn이 진입/이탈. 수거·페이즈 로직의 진입점.
	void OnPossessedPawnEnteredTrigger(ATriggerVolumeBase* Trigger, APawn* Pawn) override;
	void OnPossessedPawnExitedTrigger(ATriggerVolumeBase* Trigger, APawn* Pawn) override;

	// --- Phase FSM ---
	void SetPhase(EGOIncPhase NewPhase);
	EGOIncPhase GetCurrentPhase() const { return CurrentPhase; }

	// 제한 시간(초). 에디터에서 조정 가능. Playing 진입 시 GameState에 복사된다.
	UPROPERTY(Edit, Save, Category="GOInc", DisplayName="Match Time Limit", Min=10.0f, Max=600.0f, Speed=1.0f)
	float MatchTimeLimit = 90.0f;

private:
	// 페이즈 진입 처리 — 월드 pause / 입력 게이팅 / GameState 리셋.
	void OnEnterPhase(EGOIncPhase Phase);

	EGOIncPhase CurrentPhase = EGOIncPhase::Title;
};
