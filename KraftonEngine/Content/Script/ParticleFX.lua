-- ======================================================
-- ParticleFX — 파티클 스폰 편의 래퍼 (require 모듈)
-- ParticleManager.SpawnAt(C++ 바인딩)에 수명 자동 정리만 얹는다.
-- 주의: 액터 핸들을 모듈/전역에 보관하지 말 것 — 씬 전환 후 dangling.
-- ======================================================
local Timer = require("Manager/TimerManager")

local P = {}

-- 원샷 이펙트: life초 뒤 자동 Destroy. life 생략 시 정리는 호출자 책임.
-- 예: ParticleFX.Burst("Content/Particle/Poof.uasset", pos, 2.0)
function P.Burst(path, pos, life)
    local actor = ParticleManager.SpawnAt(path, pos)
    if actor and life then
        Timer.After(life, function()
            if actor:IsValid() then actor:Destroy() end
        end)
    end
    return actor
end

return P
