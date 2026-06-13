local AudioData    = require("Data/AudioData")
local HUD          = require("UI/HUDController")
local RagdollData  = require("Data/RagdollData")
local ScoreData    = require("Data/ScoreData")

-- 타겟 정보 패널을 일반 → 실버 → 골드 등급으로 번갈아 띄워 점수 색/배수 UI를 확인한다.
-- (이 테스트 씬은 실제 래그돌 액터를 스폰하지 않으므로, 등급 표시를 패널 데모로 보여준다.)
local TARGET_TIER_CYCLE = {
    { tier = nil,      multiplier = 1.0,                      label = "" },
    { tier = "silver", multiplier = ScoreData.silverMultiplier, label = " · SILVER" },
    { tier = "gold",   multiplier = ScoreData.goldMultiplier,   label = " · GOLD" },
}
local TARGET_TIER_INTERVAL = 2.0  -- 등급 전환 주기(초)

local function is_looping_audio_key(key)
    return key:find("^bgm_") ~= nil or key == "sfx_time_passing"
end

local function show_target_tier(ragdoll_id, entry, variant)
    HUD.ShowTargetInfo({
        ragdollId = ragdoll_id,
        name      = entry.displayName .. variant.label,
        weight    = entry.mass,
        score     = entry.baseScore * variant.multiplier,
        scoreTier = variant.tier,
    })
end

function BeginPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()

    for key, path in pairs(AudioData) do
        AudioManager.Load(key, path, is_looping_audio_key(key))
    end

    HUD.Create({
        showDebugPanel = true,
        wantsMouse = true,
    })

    HUD.SetTimeSeconds(135)
    HUD.SetScore(12850)
    HUD.SetServerLoad(67)
    HUD.SetGunMode("collect")
    HUD.SetGunEnergy(100)
    local testRagdollId = "red-plumber"
    local testRagdoll   = RagdollData[testRagdollId]
    -- 일반/실버/골드 등급을 번갈아 보여줘 점수 색·배수가 등급별로 잘 바뀌는지 확인한다.
    show_target_tier(testRagdollId, testRagdoll, TARGET_TIER_CYCLE[1])
    StartCoroutine(function()
        local index = 1
        while true do
            Wait(TARGET_TIER_INTERVAL)
            index = (index % #TARGET_TIER_CYCLE) + 1
            show_target_tier(testRagdollId, testRagdoll, TARGET_TIER_CYCLE[index])
        end
    end)
    HUD.SetMissionState({
        active = true,
        target = "red-plumber",
        need = 3,
        got = 1,
        text = "빨간 배관공 3체 수거",
    })

    Engine.SetCursorVisible(true)
    Engine.SetOnEscape(function()
        Engine.LoadScene("Title")
    end)
end

function Tick(dt)
    UpdateCoroutines(dt)   -- 코루틴 심장 — 없으면 팝업 등 Wait 기반 연출이 첫 프레임에 멈춰 안 사라진다
    HUD.Update(dt)
end

function EndPlay()
    StopAllCoroutines()
    AudioManager.StopAllLoops()
    HUD.Destroy()
    Engine.SetCursorVisible(true)
end
