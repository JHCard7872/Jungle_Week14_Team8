-- =============================================================================
-- PauseUIController — 일시정지 메뉴 UI 컨트롤러
-- [역할] 공통 ModalDialogUIController를 사용해서 화면을 어둡게 덮고
--        Continue 버튼을 띄운다.
-- [주의] pause 중에도 마우스 입력이 살아야 하므로 Show 시점에 WantsMouse를 먼저 켠다.
-- =============================================================================

local Modal = require("UI/ModalDialogUIController")

local PAUSE_Z_ORDER = 220

local M = {}

local visible = false
-- Continue 버튼 클릭 시 호출할 콜백 (보통 togglePause)
local on_continue = nil

-- 일시정지 메뉴 UI 생성 진입점
function M.Create(options)
    options = options or {}
    on_continue = options.onContinue

    Modal.Create({
        zOrder = PAUSE_Z_ORDER,
        title = "Paused",
        message = "",
        leftText = "Continue",
        onLeft = function()
            if on_continue ~= nil then
                on_continue()
            end
        end,
    })

    return true
end

-- 메뉴를 띄운다 (어둡게 덮기 + Continue 버튼)
function M.Show()
    visible = true

    Modal.Create({
        zOrder = PAUSE_Z_ORDER,
        title = "Paused",
        message = "",
        leftText = "Continue",
        onLeft = function()
            if on_continue ~= nil then
                on_continue()
            end
        end,
    })

    Modal.Show()
end

-- 메뉴를 닫는다
function M.Hide()
    visible = false
    Modal.Hide()
end

function M.IsVisible()
    return visible
end

-- UI 제거 및 내부 상태 초기화
function M.Destroy()
    Modal.Destroy()
    visible = false
    on_continue = nil
end

return M
