-- ======================================================
-- TimerManager — 코루틴 래핑 타이머 유틸 (require 모듈)
-- fire-and-forget·반복·취소용. 순차 흐름("A하고 2초 뒤 B")은
-- 그냥 StartCoroutine + Wait 를 직접 쓸 것 (보완 관계).
-- 씬 전환 시 FireWorldReset 이 pending 코루틴을 비워주고,
-- pause 중엔 구동 틱(UpdateCoroutines)이 멈춰서 타이머도 같이 멈춘다.
-- ======================================================
local T = {}

function T.After(sec, fn)              -- N초 뒤 1회
    return StartCoroutine(function() Wait(sec); fn() end)
end

function T.Every(sec, fn)              -- N초마다 반복
    return StartCoroutine(function()
        while true do Wait(sec); fn() end
    end)
end

T.Cancel = StopCoroutine               -- 핸들로 취소

return T
