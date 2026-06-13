local Modal = require("UI/ModalDialogUIController")

local DEFAULT_Z_ORDER = 270

local M = {}

local function show_popup(options)
    options = options or {}

    Modal.Create({
        zOrder = options.zOrder or DEFAULT_Z_ORDER,
        title = options.title or "",
        message = options.message or "",
        leftText = options.leftText,
        rightText = options.rightText,
        buttonStyle = "image",
        showCursor = options.showCursor ~= false,
        onLeft = options.onLeft,
        onRight = options.onRight,
    })
    Modal.Show()
end

function M.ShowConfirm(options)
    options = options or {}

    show_popup({
        zOrder = options.zOrder,
        title = options.title,
        message = options.message,
        leftText = options.leftText or "YES",
        rightText = options.rightText or "NO",
        showCursor = options.showCursor,
        onLeft = options.onYes,
        onRight = options.onNo,
    })
end


function M.ShowInput(options)
    options = options or {}

    Modal.Create({
        zOrder = options.zOrder or DEFAULT_Z_ORDER,
        title = options.title or "",
        message = options.message or "",
        leftText = options.confirmText or "결정",
        rightText = nil,
        buttonStyle = "image",
        input = true,
        inputRule = options.ruleText or "",
        inputValue = options.defaultValue or "",
        inputError = options.errorText or "",
        showCursor = options.showCursor ~= false,
        onLeft = function()
            if options.onConfirm ~= nil then
                options.onConfirm(Modal.GetInputText())
            end
        end,
    })
    Modal.Show()
end

function M.ShowNotice(options)
    options = options or {}

    show_popup({
        zOrder = options.zOrder,
        title = options.title,
        message = options.message,
        leftText = options.buttonText or "확인",
        rightText = nil,
        showCursor = options.showCursor,
        onLeft = options.onConfirm,
    })
end

function M.Hide()
    Modal.Hide()
end

function M.IsVisible()
    return Modal.IsVisible()
end

function M.UpdateCursor()
    Modal.UpdateCursor()
end

function M.GetInputText()
    return Modal.GetInputText()
end

function M.Destroy()
    Modal.Destroy()
end

return M
