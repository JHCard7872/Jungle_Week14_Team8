-- ============================================================================
-- GOInc RagdollData — UI / spawn / score / ragdoll mass catalog
--
-- [역할]
--   - UI 표시용 이름, Reference Pose 이미지, 무게, 점수, 부활 가능 여부를 제공한다.
--   - mass는 GOIncRagdollPawn_Test.lua가 SkeletalMesh ragdoll 전체 질량으로 적용한다.
--   - GOIncRagdollSpawnManager가 스폰 후보(id / pawnClass / spawnWeight)를 읽는다.
--
-- [중요]
--   - SkeletalMesh, PhysicsAsset, Animation, Capsule, Movement, Flee 세부값은 여기서 관리하지 않는다.
--   - 실제 런타임 Actor 구성값은 각 GOInc Ragdoll Pawn C++ 클래스가 가진다.
--   - mass는 실제 ragdoll 전체 질량으로도 쓰인다.
--   - reviveSpeed는 아직 카탈로그 표시·밸런스용 값이며 C++ movement speed를 직접 덮어쓰지 않는다.
--
-- [사용법]
--   local Ragdolls = require("Data.RagdollData")
--   Ragdolls["blue-speedster"].baseScore
-- ============================================================================

return {
    ["blue-speedster"] = {
        id             = "blue-speedster",
        displayName    = "파란 고슴도치",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_sonic.png",

        mass           = 35.0,    -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 임시 밸런스
        canRevive      = true,
        reviveSpeed    = 4.0,
        attackPower    = 10,     -- placeholder

        pawnClass      = "AGOIncSonicRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 1,
        uiOrder        = 10,
    },

    ["pink-round"] = {
        id             = "pink-round",
        displayName    = "분홍 동글이",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_kirby.png",

        mass           = 18.0,    -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 수거당 100점 통일 (임시 밸런스)
        canRevive      = true,
        reviveSpeed    = 3.5,
        attackPower    = 8,      -- placeholder

        pawnClass      = "AGOIncKirbyRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 1,
        uiOrder        = 20,
    },

    ["brown-gorilla"] = {
        id             = "brown-gorilla",
        displayName    = "갈색 고릴라",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_sample.png",

        mass           = 160.0,   -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 수거당 100점 통일 (임시 밸런스)
        canRevive      = true,
        reviveSpeed    = 2.0,
        attackPower    = 25,     -- placeholder

        pawnClass      = "AGOIncDonkeyKongRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 1,
        uiOrder        = 30,
    },

    ["yellow-mouse"] = {
        id             = "yellow-mouse",
        displayName    = "노란 전기쥐",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_Pikachu.png",

        mass           = 12.0,    -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 수거당 100점 통일 (임시 밸런스)
        canRevive      = true,
        reviveSpeed    = 4.5,
        attackPower    = 18,     -- placeholder

        pawnClass      = "AGOIncPikachuRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 1,
        uiOrder        = 40,
    },

    ["red-plumber"] = {
        id             = "red-plumber",
        displayName    = "빨간 배관공",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_Mario.png",  -- 파일 입수 전

        mass           = 65.0,   -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 임시 밸런스
        canRevive      = true,
        reviveSpeed    = 2.5,    -- 카탈로그 표시/밸런스용 부활 속도
        attackPower    = 15,     -- placeholder — 적용 규칙 미정

        pawnClass      = "AGOIncMarioRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 1,
        uiOrder        = 50,
    },

    ["spiked-king"] = {
        id             = "spiked-king",
        displayName    = "가시 대왕",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_bowser.png",  -- 파일 입수 전

        mass           = 200.0,   -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 임시 밸런스
        canRevive      = true,
        reviveSpeed    = 2.2,
        attackPower    = 30,     -- placeholder

        pawnClass      = "AGOIncBowserRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 1,
        uiOrder        = 60,
    },

    ["egg-scientist"] = {
        id             = "egg-scientist",
        displayName    = "에그 과학자",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_Eggman.png",  -- 파일 입수 전

        mass           = 120.0,   -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 임시 밸런스
        canRevive      = true,
        reviveSpeed    = 2.8,
        attackPower    = 12,     -- placeholder

        pawnClass      = "AGOIncEggmanRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 1,
        uiOrder        = 70,
    },

    ["green-swordsman"] = {
        id             = "green-swordsman",
        displayName    = "초록 검사",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_Link.png",  -- 파일 입수 전

        mass           = 60.0,   -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 임시 밸런스
        canRevive      = true,
        reviveSpeed    = 3.8,
        attackPower    = 20,     -- placeholder

        pawnClass      = "AGOIncLinkRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 1,
        uiOrder        = 80,
    },

    ["space-chief"] = {
        id             = "space-chief",
        displayName    = "스페이스 치프",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_chief.png",  -- 파일 입수 전

        mass           = 170.0,   -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 임시 밸런스
        canRevive      = true,
        reviveSpeed    = 3.0,
        attackPower    = 22,     -- placeholder

        pawnClass      = "AGOIncChiefRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 1,
        uiOrder        = 100,
    },

    ["adventurer"] = {
        id             = "adventurer",
        displayName    = "모험가",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_sample.png",  -- 파일 입수 전

        mass           = 55.0,    -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 임시 밸런스
        canRevive      = true,
        reviveSpeed    = 3.7,
        attackPower    = 16,     -- placeholder

        pawnClass      = "AGOIncLaraRagdollPawn",
        canSpawn       = true,
        spawnWeight    = 1,
        uiOrder        = 110,
    },

    ["green-slime"] = {
        id             = "green-slime",
        displayName    = "초록 슬라임",
        referenceImage = "../../Sprite/Ragdoll_Image/ragdoll_sample.png",  -- 파일 입수 전

        mass           = 25.0,    -- 실제 ragdoll 전체 질량 / UI 표시용 무게
        baseScore      = 100,    -- 수거당 100점 통일 (임시 밸런스)
        canRevive      = false,
        reviveSpeed    = 0,
        attackPower    = 0,      -- placeholder

        -- Content/Data에 실제 asset 폴더와 전용 Pawn이 없으므로 스폰에서는 제외
        pawnClass      = "",
        canSpawn       = false,
        spawnWeight    = 0,
        uiOrder        = 900,
    },
}
