-- =============================================================================
-- AudioData - sound key to file mapping (require module, read-only)
-- [Role] Gameplay code uses stable keys like "sfx_collect" instead of file paths.
--        If files change later, this file is the single place to update.
-- [Usage] Register everything once in scene BeginPlay. Keys with the `bgm_` prefix
--         must be loaded with loop=true because FMOD loop mode is fixed at load time:
--           for key, path in pairs(require("Data/AudioData")) do
--               AudioManager.Load(key, path, key:find("^bgm_") ~= nil)
--           end
--         Playback uses AudioManager.Play(key, volume).
-- [Note] Paths are relative to Content/Audio/. Missing files are harmless and only
--        produce a load failure log.
-- =============================================================================

return {
    -- Background music
    bgm_title_0 = "BgmTitle_0.mp3",
    bgm_title_1 = "BgmTitle_1.mp3",
    bgm_gameplay_0 = "BgmGameplay_0.mp3",
    bgm_gameplay_1 = "BgmGameplay_1.mp3",
    bgm_main_0 = "BgmMain_0.mp3",
    bgm_cutscene = "BgmCutScene.mp3",
    bgm_collector_truck = "BgmCollectorTruck.mp3",

    -- Sound effects
    sfx_foot = "SfxFoot.mp3",
    sfx_result_high = "SfxResultHigh.mp3",
    sfx_result_medium = "SfxResultMedium.mp3",
    sfx_result_low = "SfxResultLow.mp3",
    sfx_gun_shoot = "SfxGunShoot.mp3",
    sfx_beam_grab = "SfxBeamGrab.mp3",
    sfx_collect = "SfxUiClick.mp3",          -- TODO: 임시 매핑 — SfxCollect.mp3 입수 시 교체
    sfx_hit = "SfxHit.mp3",
    sfx_ui_click = "SfxUiClick.mp3",
    sfx_ui_hover = "SfxUiHover.mp3",
    sfx_game_over = "SfxTitleGameOver.mp3",  -- TODO: 임시 매핑 — SfxGameOver.mp3 입수 시 교체
    sfx_revive = "SfxRevive.mp3",
}
