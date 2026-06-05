-- ==============================================================================
-- SpawnManager — 래그돌 주기 스폰 (require 모듈) ★ 타 팀원 구현 영역, 지금은 스텁
-- [역할] GameConfig.spawnInterval 주기로 래그돌을 스폰하고 태그를 부여한다.
-- [사용법] PlayScene.BeginPlay에서 Start() 호출 (호출부는 이미 연결돼 있음).
--
-- TODO(스폰 담당): 아래 내용으로 구현해 주세요.
--   1. Start():  TimerManager.Every(require("Data/GameConfig").spawnInterval, SpawnOne)
--      (씬의 StopAllCoroutines가 정리하므로 매 판 Start에서 다시 걸면 됨)
--   2. SpawnOne(): 래그돌 액터 스폰 (클래스/메시 적용 방식은 ragdoll 팀과 협의)
--   3. 태그 부여: "Ragdoll"(공통) + 타입 키(예: "red-plumber" — Data/RagdollData의 키와
--      반드시 일치해야 점수/미션이 동작) + 금/은 추첨(Data/ScoreData의
--      goldChance/silverChance)이면 "Gold"/"Silver" 태그 추가
--   4. RagdollData의 scale/mass 적용
-- ==============================================================================

local M = {}

function M.Start()
    -- TODO(스폰 담당): 구현 전까지 빈 함수 — PlayScene 호출이 에러 없이 지나가게만 함
end

return M
