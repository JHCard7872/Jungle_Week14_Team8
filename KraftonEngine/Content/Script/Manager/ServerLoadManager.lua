-- ============================================================================
-- ServerLoadManager — 서버 과부하 규칙 (require 모듈)
-- [역할] 방치된(살아있는) 래그돌 수에 비례해 Session.load를 올린다.
--        한계 도달 판정은 여기가 아니라 PlayScene의 종료 판정 몫.
-- [사용법] PlayScene.BeginPlay에서 Start(), 매 Tick에서 Update(dt) 호출.
-- [특이사항] 래그돌 수를 매 틱 World.FindActorsByTag로 세면 비싸서,
--            0.5초 주기 코루틴으로 집계해 캐시한다 (게이지라 0.5초 지연은 무해).
--            샘플링 코루틴은 씬의 StopAllCoroutines가 정리하므로 매 판 Start 필요.
--            pause 중엔 코루틴 구동 틱이 멈춰서 집계/상승도 같이 멈춘다 (의도된 동작).
-- ============================================================================

local Session = require("GameSession")
local Timer   = require("Manager/TimerManager")

local LOAD_PER_RAGDOLL = 0.5   -- 방치 1마리가 1초당 올리는 부하(%)  -- 임시 밸런스

local M = {}
local abandonedCount = 0   -- 0.5초 주기 샘플링 캐시

function M.Start()
    abandonedCount = 0
    Timer.Every(0.5, function()
        -- 수거된 래그돌은 Destroy되므로, 태그 검색 결과 수 = 방치 수
        local n = 0
        local list = World.FindActorsByTag("Ragdoll")
        if list then
            for _ in pairs(list) do n = n + 1 end
        end
        abandonedCount = n
    end)
end

function M.Update(dt)
    if abandonedCount <= 0 then return end
    Session.load = Session.load + abandonedCount * LOAD_PER_RAGDOLL * dt
end

return M
