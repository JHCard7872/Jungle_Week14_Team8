-- ============================================================================
-- RagdollData — 래그돌 타입별 상수 (require 모듈, 읽기 전용)
-- [역할] 타입(키)별 표시명/이미지/물리/점수 정의.
--        스폰 추첨, ScoreManager 점수 계산, HUD 참조 이미지가 읽는다.
-- [사용법] local Ragdolls = require("Data/RagdollData")
--          Ragdolls["red-plumber"].baseScore
-- [특이사항] displayName은 원작 이름을 직접 쓰지 않는다 ("빨간 배관공"처럼 돌려서).
--            referenceImage는 모든 타입 동일 각도로 촬영된 이미지여야 한다.
--            엔트리는 임시 2종 — 사용할 에셋 확정되면 추가/교체.
-- ============================================================================

return {
    ["red-plumber"] = {
        displayName    = "빨간 배관공",
        referenceImage = "Content/UI/Images/red_plumber.png",  -- 파일 입수 전
        mass           = 12.5,   -- 임시 밸런스 (무거울수록 들기 힘듦)
        baseScore      = 100,    -- 임시 밸런스
        scale          = 1.0,
        canRevive      = true,   -- 살아날 수 있는 타입
        reviveSpeed    = 2.5,    -- 살아났을 때 도망 속도 (canRevive=true일 때만 의미)
        attackPower    = 15,     -- placeholder — 적용 규칙 미정
    },

    ["green-slime"] = {
        displayName    = "초록 슬라임",
        referenceImage = "Content/UI/Images/green_slime.png",  -- 파일 입수 전
        mass           = 6.0,    -- 임시 밸런스
        baseScore      = 80,     -- 임시 밸런스
        scale          = 1.0,
        canRevive      = false,
        reviveSpeed    = 0,
        attackPower    = 0,      -- placeholder
    },
}
