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

        -- 아직 GOIncMarioRagdollPawn은 구현하지 않았으므로 스폰에서는 제외
        characterId    = "red-plumber",
        pawnClass      = "",
        canSpawn       = false,
        spawnWeight    = 0,
        uiOrder        = 90,
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

        -- 아직 전용 Pawn이 없으므로 스폰에서는 제외
        characterId    = "green-slime",
        pawnClass      = "",
        canSpawn       = false,
        spawnWeight    = 0,
        uiOrder        = 100,
    },

    ["blue-speedster"] = {
        displayName    = "파란 고슴도치",
        referenceImage = "Content/UI/Images/blue_speedster.png",
        mass           = 8.0,    -- 임시 밸런스
        baseScore      = 100,    -- 임시 밸런스
        scale          = 1.0,
        canRevive      = true,
        reviveSpeed    = 4.0,
        attackPower    = 10,     -- placeholder

        characterId    = "blue-speedster",
        pawnClass      = "AGOIncSonicRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 10,
        uiOrder        = 10,
    },

    ["pink-round"] = {
        displayName    = "분홍 동글이",
        referenceImage = "Content/UI/Images/pink_round.png",
        mass           = 6.5,    -- 임시 밸런스
        baseScore      = 120,    -- 임시 밸런스
        scale          = 1.0,
        canRevive      = true,
        reviveSpeed    = 3.5,
        attackPower    = 8,      -- placeholder

        characterId    = "pink-round",
        pawnClass      = "AGOIncKirbyRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 8,
        uiOrder        = 20,
    },

    ["brown-gorilla"] = {
        displayName    = "갈색 고릴라",
        referenceImage = "Content/UI/Images/brown_gorilla.png",
        mass           = 20.0,   -- 임시 밸런스
        baseScore      = 180,    -- 임시 밸런스
        scale          = 1.0,
        canRevive      = true,
        reviveSpeed    = 2.0,
        attackPower    = 25,     -- placeholder

        characterId    = "brown-gorilla",
        pawnClass      = "AGOIncDonkeyKongRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 3,
        uiOrder        = 30,
    },

    ["yellow-mouse"] = {
        displayName    = "노란 전기쥐",
        referenceImage = "Content/UI/Images/yellow_mouse.png",
        mass           = 5.5,    -- 임시 밸런스
        baseScore      = 140,    -- 임시 밸런스
        scale          = 1.0,
        canRevive      = true,
        reviveSpeed    = 4.5,
        attackPower    = 18,     -- placeholder

        characterId    = "yellow-mouse",
        pawnClass      = "AGOIncPikachuRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 7,
        uiOrder        = 40,
    },
}