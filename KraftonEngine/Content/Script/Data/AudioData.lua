-- =============================================================================
-- AudioData — 사운드 키 → 파일 매핑 (require 모듈, 읽기 전용)
-- [역할] 게임 로직이 파일 경로 대신 키("SfxCollect")로 소리를 다루게 하는 한 겹.
--        파일이 바뀌어도 이 파일만 고치면 된다.
-- [사용법] 각 씬 BeginPlay에서 일괄 등록 (Bgm 접두 키는 루프 재생이라 loop=true 필수
--          — FMOD는 루프 여부가 Load 시점에 고정되고 PlayBGM이 다시 박아주지 않는다):
--            for key, path in pairs(require("Data/AudioData")) do
--                AudioManager.Load(key, path, key:find("^Bgm") ~= nil)
--            end
--          재생은 AudioManager.Play(key, volume) — volume 인자 필수.
-- [특이사항] 경로는 Content/Audio/ 기준 상대경로 (LoadAudio가 알아서 합친다).
--            사운드 파일은 아직 입수 전 — 없는 파일은 Load 실패 로그만 찍히고 무해함.
--            담당자가 mp3 이름에 맞게 수정. 아래는 예시
-- =============================================================================

return {
    -- 배경음 (loop=true로 등록됨)
    BgmTitle    = "BgmTitle.mp3",     -- 타이틀 화면
    BgmGameplay = "BgmGameplay.mp3",  -- 게임플레이
    BgmResult   = "BgmResult.mp3",    -- 결과 화면
    BgmTruck    = "BgmCollectorTruck.mp3",  -- 수거 차량 순회음 (PlayLoop로 재생, 차량 담당)

    -- 효과음
    SfxShock    = "SfxShock.mp3",     -- 전기 빔 공격
    SfxBeamGrab = "SfxBeamGrab.mp3",  -- 빔으로 잡기
    SfxCollect  = "SfxCollect.mp3",   -- 수거 성공
    SfxHit      = "SfxHit.mp3",       -- 충돌/타격
    SfxUiClick  = "SfxUiClick.mp3",   -- UI 버튼
    SfxGameOver = "SfxGameOver.mp3",  -- 게임오버
    SfxRevive   = "SfxRevive.mp3",    -- 래그돌 부활
}
