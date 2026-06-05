#include "Source/Game/GameMode/GOIncGameMode.h"

#include "Source/Game/GameMode/GOIncGameState.h"
#include "Source/Game/GameMode/GOIncPlayerController.h"

#include "GameFramework/World.h"
#include "Object/Reflection/UClass.h"
#include "Core/Logging/Log.h"

AGOIncGameMode::AGOIncGameMode()
{
	// 베이스 기본값(AGameStateBase / APlayerController)을 GOInc 전용 클래스로 교체.
	// 엔진이 BeginPlay(GameState) / StartMatch(PlayerController) 에서 이 클래스로 spawn한다.
	GameStateClass = AGOIncGameState::StaticClass();
	PlayerControllerClass = AGOIncPlayerController::StaticClass();
}

void AGOIncGameMode::StartMatch()
{
	// 베이스: PlayerController spawn + bAutoPossessPlayer Pawn 자동 Possess.
	AGameModeBase::StartMatch();

	// 게임플레이 씬은 곧장 본 게임으로 진입한다 (Title/Result는 별도 씬).
	SetPhase(EGOIncPhase::Playing);
}

void AGOIncGameMode::SetPhase(EGOIncPhase NewPhase)
{
	if (NewPhase == CurrentPhase)
	{
		return;
	}

	CurrentPhase = NewPhase;
	OnEnterPhase(NewPhase);
}

void AGOIncGameMode::OnEnterPhase(EGOIncPhase Phase)
{
	UWorld* World = GetWorld();
	const bool bPlaying = (Phase == EGOIncPhase::Playing);

	// 월드 정지 — Playing 일 때만 게임플레이 틱이 돈다.
	if (World)
	{
		World->SetPaused(!bPlaying);
	}

	// 입력 게이팅 — Playing 에서만 캐릭터 이동/건 입력 허용.
	if (AGOIncPlayerController* PC = Cast<AGOIncPlayerController>(GetPlayerController()))
	{
		PC->SetGameplayInputEnabled(bPlaying);
	}

	switch (Phase)
	{
	case EGOIncPhase::Playing:
		// 새 판 수치 초기화. 세부 로직(스폰/점수/부하)은 Lua(Game.lua)가 담당.
		if (AGOIncGameState* State = Cast<AGOIncGameState>(GetGameState()))
		{
			State->ResetForNewMatch(MatchTimeLimit);
		}
		UE_LOG("[GOInc] Phase -> Playing (TimeLimit=%.1f)", MatchTimeLimit);
		break;
	case EGOIncPhase::Paused:
		UE_LOG("[GOInc] Phase -> Paused");
		break;
	case EGOIncPhase::Result:
		UE_LOG("[GOInc] Phase -> Result");
		break;
	case EGOIncPhase::Title:
		UE_LOG("[GOInc] Phase -> Title");
		break;
	}
}

void AGOIncGameMode::OnPossessedPawnEnteredTrigger(ATriggerVolumeBase* Trigger, APawn* Pawn)
{
	// TODO: 트럭/포탈 트리거 진입 → 래그돌 수거 판정 → 점수.
	// 세부 규칙은 Lua(Game.lua)로 위임 예정. 지금은 진입점만 확보.
	(void)Trigger;
	(void)Pawn;
}

void AGOIncGameMode::OnPossessedPawnExitedTrigger(ATriggerVolumeBase* Trigger, APawn* Pawn)
{
	(void)Trigger;
	(void)Pawn;
}
