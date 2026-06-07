-- =========================================================================================
-- GameSession — 세션 값 홀더 (require 모듈, 단일 진실원천)
-- [역할] 게임 중 변하는 공유 값만 보관. 계산/규칙 없음. 필드마다 쓰는 주체는 1명이다:
--        score·result.collectedCount·result.baseScore·result.urgentScore = ScoreManager
--        load = ServerLoadManager
--        timeRemaining·result.gameOverReason = PlayScene / inputEnabled = PlayScene ESC 토글
--        gun.* = GunBehavior / mission.* = MissionManager
-- [사용법] local Session = require("GameSession") 후 필드 직독. 쓰기는 위 담당만.
--          결과 화면 점수는 별도 필드 없이 Session.score를 그대로 읽는다 (모듈은 씬을 넘어 생존).
-- [특이사항] require 모듈은 씬 전환에서 살아남는다 — PlayScene.BeginPlay의 Reset() 호출이 의무.
--            순수 값만 보관할 것 (액터/위젯 핸들 금지 — 씬 전환 후 죽은 참조가 됨).
-- 
--        ****플레이 중 이 파일을 저장하지 말 것 — 핫리로드가 모듈 캐시를 비워서*****
-- 
--            이미 require해둔 쪽과 새로 require한 쪽이 서로 다른 테이블을 보게 된다.
-- =========================================================================================

local S = {
    score         = 0,     -- 현재 점수
    load          = 0,     -- 서버 과부하 게이지(%) — GameConfig.maxServerLoad 도달 시 게임오버
    timeRemaining = 0,     -- 남은 시간(초)
    inputEnabled  = true,  -- 게임플레이 입력 허용 여부 (pause 중 false — 입력 콜백 진입부에서 검사)

    gun = {
        mode   = "collect",  -- "collect" 수거 / "attack" 공격(전기 빔)
        energy = 100,        -- placeholder — 남은 전기(W). 소모/회복 규칙은 기획 후순위라 미정
        crosshair = {
            visible = true,
            hold = false,
            rotation = 0.0,
        },
    },

    target = {
        visible = false,
        ragdollId = "",
        actorName = "",
        bodyName = "",
        distanceText = "",
        name = "",
        weightText = "",
        scoreText = "",
        imagePath = "../../Sprite/ragdoll/ragdoll_sample.png",
    },

    mission = {
        active = false,  -- 발급된 미션 존재 여부 (래그돌이 없으면 발급 보류로 false)
        target = "",     -- 목표 타입 id (RagdollData 키)
        need   = 0,      -- 목표 수
        got    = 0,      -- 현재 수거 수
        text   = "",     -- HUD 표시 문구 ("xxx N체 수거")
    },

    result = {
        collectedCount = 0,   -- 총 수거 수
        baseScore      = 0,   -- 기본 회수 실적 — 수거 점수 누계 (결과 화면 표시용)
        urgentScore    = 0,   -- 긴급 요청 처리 실적 — 미션 보너스 누계 (결과 화면 표시용)
        gameOverReason = "",  -- "시간 초과" / "서버 과부하"
        gradeText      = "",  -- 평가 문구 ("정규직 전환 실패" 등) — 3차 폴리시
    },
}

-- 매 판 시작(PlayScene.BeginPlay)에서 호출. 이전 판 값 잔류 방지.
function S.Reset(timeLimit)
    S.score, S.load, S.timeRemaining, S.inputEnabled = 0, 0, timeLimit, true
    S.gun    = { mode = "collect", energy = 100, crosshair = { visible = true, hold = false, rotation = 0.0 } }
    S.target = {
        visible = false,
        ragdollId = "",
        actorName = "",
        bodyName = "",
        distanceText = "",
        name = "",
        weightText = "",
        scoreText = "",
        imagePath = "../../Sprite/ragdoll/ragdoll_sample.png",
    }
    S.mission = { active = false, target = "", need = 0, got = 0, text = "" }
    -- 주의: 위 초기 result 테이블과 필드를 똑같이 유지할 것 —
    -- baseScore/urgentScore가 빠지면 ScoreManager가 첫 수거부터 nil 산술로 죽는다 (편집 유실 사고 이력 있음)
    S.result = { collectedCount = 0, baseScore = 0, urgentScore = 0, gameOverReason = "", gradeText = "" }
end

return S
