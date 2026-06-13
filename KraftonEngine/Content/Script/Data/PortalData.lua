-- ============================================================================
-- PortalData — 순간이동 포탈 튜닝값 (require 모듈, 읽기 전용)
-- [역할] 포탈은 "같은 색 짝 포탈로 순간이동"한다. 색상별(0=하늘 1=분홍 2=노랑) 한 쌍씩
--        총 6개를 에디터에 직접 배치한다(ASummonPortalActor + Color Index). 위치는 고정.
--        여기엔 색/연출값만 둔다 — PortalBehavior/PortalTeleport가 짝 찾기·이동 연출에 읽는다.
-- [사용법] local Portal = require("Data/PortalData")
-- [특이사항] 포탈 위치는 더 이상 여기서 정하지 않는다(에디터 배치). colorIndex가 같은 두
--            포탈이 한 쌍이며 서로의 목적지가 된다.
--            colors는 C++ 빛기둥 머티리얼 Tint(FX_LightShaftMesh_*.mat)와 맞춰 비네팅에 쓴다.
-- ============================================================================

return {
    -- 색상별 비네팅 RGB (C++ 머티리얼 Tint와 일치 — 이동 시 화면 가장자리 색)
    colors = {
        [0] = { r = 0.10, g = 0.55, b = 1.00 },  -- 하늘
        [1] = { r = 1.00, g = 0.08, b = 0.55 },  -- 분홍
        [2] = { r = 1.00, g = 0.62, b = 0.00 },  -- 노랑
    },

    sfxMoveKey = "sfx_portal_move",   -- 이동 사운드(AudioData에 등록)

    -- 이동 연출 타이밍/세기 (PortalTeleport FSM이 읽음)
    fx = {
        flashOutDuration  = 0.10,  -- 흰색으로 점멸(화면→흰색 페이드 아웃)
        fadeInDuration    = 0.45,  -- 도착 위치에서 서서히 fade in(흰색→원래화면)
        blurStrength      = 0.85,  -- 풀스크린 블러 강도(0..1)
        vignetteIntensity = 1.0,   -- 색상 비네팅 강도
        vignetteRadius    = 0.55,
        vignetteSoftness  = 0.45,
        cooldown          = 1.0,   -- 도착 직후 재이동 방지(초) — 짝 위에 떨어져도 즉시 되튕기지 않게
    },
}
