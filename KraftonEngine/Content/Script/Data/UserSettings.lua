-- =============================================================================
-- UserSettings — 옵션 메뉴에서 조정한 사용자 설정값 공유 모듈
-- [역할] 씬을 넘어 SFX/BGM/Input Mode 설정을 유지한다.
-- [값 범위] UI 볼륨은 0~10, 실제 AudioManager에 넘기는 값은 0.0~1.0
-- =============================================================================

local M = {
    sfxVolume = 8,
    bgmVolume = 8,
    inputMode = "mouse_key",
}

local function clamp_volume(value)
    local number_value = tonumber(value) or 0

    if number_value < 0 then
        return 0
    end

    if number_value > 10 then
        return 10
    end

    return math.floor(number_value + 0.5)
end

function M.VolumeToScalar(value)
    return clamp_volume(value) / 10.0
end

function M.GetSfxVolumeScalar()
    return M.VolumeToScalar(M.sfxVolume)
end

function M.GetBgmVolumeScalar()
    return M.VolumeToScalar(M.bgmVolume)
end

function M.GetSettings()
    return {
        sfxVolume = M.sfxVolume,
        bgmVolume = M.bgmVolume,
        inputMode = M.inputMode,
    }
end

function M.Apply(settings)
    if settings == nil then
        return M.GetSettings()
    end

    if settings.sfxVolume ~= nil then
        M.sfxVolume = clamp_volume(settings.sfxVolume)
    end

    if settings.bgmVolume ~= nil then
        M.bgmVolume = clamp_volume(settings.bgmVolume)
    end

    if settings.inputMode == "mouse_key" or settings.inputMode == "gamepad" then
        M.inputMode = settings.inputMode
    end

    if Engine ~= nil and Engine.SetInputMode ~= nil then
        Engine.SetInputMode(M.inputMode)
    end

    return M.GetSettings()
end

function M.ApplyCurrentBgmVolume(bgm_key)
    local volume = M.GetBgmVolumeScalar()

    if AudioManager == nil then
        return false
    end

    if AudioManager.SetBGMVolume ~= nil then
        AudioManager.SetBGMVolume(volume)
        return true
    end

    if AudioManager.SetBgmVolume ~= nil then
        AudioManager.SetBgmVolume(volume)
        return true
    end

    if AudioManager.SetMusicVolume ~= nil then
        AudioManager.SetMusicVolume(volume)
        return true
    end

    if bgm_key ~= nil and AudioManager.SetVolume ~= nil then
        AudioManager.SetVolume(bgm_key, volume)
        return true
    end

    -- 볼륨 변경 API가 없는 엔진 빌드에서는 같은 BGM을 다시 PlayBGM 해서
    -- 이미 재생 중인 BGM 인스턴스의 볼륨을 갱신한다.
    if bgm_key ~= nil and AudioManager.PlayBGM ~= nil then
        AudioManager.PlayBGM(bgm_key, volume)
        return true
    end

    return false
end

return M
