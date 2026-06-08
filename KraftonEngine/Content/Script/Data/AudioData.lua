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
    sfx_foot = "SfxFootstep.mp3",
    sfx_result_high = "SfxResultHigh.mp3",
    sfx_result_medium = "SfxResultMedium.mp3",
    sfx_result_low = "SfxResultLow.mp3",
    sfx_printer_print = "SfxPrinterPrint.mp3",
    sfx_clipboard_sliding = "SfxClipboardSliding.mp3",
    sfx_stamp_impact = "SfxStampImpact.mp3",
    sfx_gun_shoot = "SfxGunCollectShoot.mp3",
    sfx_gun_attack_shoot = "SfxGunAttackShoot.mp3",
    sfx_gun_mode_change = "SfxGunModeChange.mp3",
    sfx_beam_grab = "SfxBeamGrab.mp3",
    sfx_collect = "SfxUiClick.mp3",            -- TODO: 임시 매핑 — SfxCollect.mp3 입수 시 교체
    sfx_hit = "SfxHit.mp3",
    sfx_ui_click = "SfxUiClick.mp3",
    sfx_ui_hover = "SfxUiHover.mp3",
    sfx_game_start = "SfxGameStart.mp3",
    sfx_countdown_321_go = "SfxCountdown321Go.mp3",
    sfx_game_over = "SfxGameOver.mp3",
    sfx_revive = "SfxRevivedRagdoll.mp3",
    sfx_popup_alert = "SfxPlayPopupAlert.mp3",
    sfx_popup_info = "SfxPlayPopupInfo.mp3",
    sfx_popup_success = "SfxPlayPopupSuccess.mp3",
    sfx_popup_warning = "SfxPlayPopupWarning.mp3",
    sfx_time_passing = "SfxTimePassing.mp3",
    sfx_10_seconds = "Sfx10seconds.mp3",
}
