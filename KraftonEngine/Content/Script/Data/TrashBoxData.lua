-- ============================================================================
-- TrashBoxData — 수거함 튜닝값 (require 모듈, 읽기 전용)
-- [역할] 수거함 수거 파티클 배선값. TrashBoxBehavior.lua가 읽는다.
-- [사용법] local TrashBox = require("Data/TrashBoxData")
-- ============================================================================

return {
    collectFxPath = "Content/Particle/FX_CollectPop.uasset", -- 수거 파티클(뾰로롱 팍)
    collectFxLife = 1.5,                                     -- 파티클 자동 정리 수명(초)
}
