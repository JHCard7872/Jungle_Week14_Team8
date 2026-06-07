#include "Engine/Input/InputSystem.h"
#include <cmath>
#include <Xinput.h>
#pragma comment(lib, "xinput9_1_0.lib")

// VK_GAMEPAD_* 는 Windows 10 SDK 매크로 — 구버전 SDK 빌드 환경 대비 가드
#ifndef VK_GAMEPAD_A
#define VK_GAMEPAD_A                        0xC3
#define VK_GAMEPAD_B                        0xC4
#define VK_GAMEPAD_X                        0xC5
#define VK_GAMEPAD_Y                        0xC6
#define VK_GAMEPAD_RIGHT_SHOULDER           0xC7
#define VK_GAMEPAD_LEFT_SHOULDER            0xC8
#define VK_GAMEPAD_LEFT_TRIGGER             0xC9
#define VK_GAMEPAD_RIGHT_TRIGGER            0xCA
#define VK_GAMEPAD_DPAD_UP                  0xCB
#define VK_GAMEPAD_DPAD_DOWN                0xCC
#define VK_GAMEPAD_DPAD_LEFT                0xCD
#define VK_GAMEPAD_DPAD_RIGHT               0xCE
#define VK_GAMEPAD_MENU                     0xCF
#define VK_GAMEPAD_VIEW                     0xD0
#define VK_GAMEPAD_LEFT_THUMBSTICK_BUTTON   0xD1
#define VK_GAMEPAD_RIGHT_THUMBSTICK_BUTTON  0xD2
#endif

// 스틱 원시값(-32768~32767)에 데드존을 적용하고 -1~1로 정규화.
// 데드존 경계에서 0부터 부드럽게 시작하도록 남은 구간을 다시 늘인다.
static float ApplyStickDeadzone(SHORT Value, int Deadzone)
{
    const int Abs = Value >= 0 ? Value : -static_cast<int>(Value);
    if (Abs <= Deadzone)
    {
        return 0.0f;
    }

    const float Magnitude = static_cast<float>(Abs - Deadzone) / static_cast<float>(32767 - Deadzone);
    const float Clamped = Magnitude > 1.0f ? 1.0f : Magnitude;
    return Value >= 0 ? Clamped : -Clamped;
}

// 트리거 원시값(0~255)에 데드존을 적용하고 0~1로 정규화
static float ApplyTriggerDeadzone(BYTE Value, int Deadzone)
{
    if (Value <= Deadzone)
    {
        return 0.0f;
    }
    return static_cast<float>(Value - Deadzone) / static_cast<float>(255 - Deadzone);
}

void InputSystem::Tick()
{
    // 윈도우 포커스가 없으면 모든 입력 상태 해제
    bWindowFocused = !OwnerHWnd || GetForegroundWindow() == OwnerHWnd;
    if (!bWindowFocused)
    {
        ClearGamepadAxes();
        ResetAllKeyStates();
        ResetTransientState();
        UpdateCurrentSnapshot();
        return;
    }

    for (int i = 0; i < 256; ++i)
    {
        PrevStates[i] = CurrentStates[i];
        CurrentStates[i] = (GetAsyncKeyState(i) & 0x8000) != 0;
    }

    // 위 루프가 VK_GAMEPAD_* 슬롯을 false로 깔아둔 뒤 패드 상태로 덮어쓴다
    PollGamepad();

    bLeftDragJustStarted = false;
    bRightDragJustStarted = false;
    bLeftDragJustEnded = false;
    bRightDragJustEnded = false;

    PrevScrollDelta = ScrollDelta;
    ScrollDelta = 0;

    PrevMousePos = MousePos;
    GetCursorPos(&MousePos);
    FrameMouseDeltaX = MousePos.x - PrevMousePos.x;
    FrameMouseDeltaY = MousePos.y - PrevMousePos.y;
    if (bUseRawMouse)
    {
        FrameMouseDeltaX = RawMouseDeltaAccumX;
        FrameMouseDeltaY = RawMouseDeltaAccumY;
    }
    RawMouseDeltaAccumX = 0;
    RawMouseDeltaAccumY = 0;

    if (GetKeyDown(VK_LBUTTON))
    {
        bLeftDragCandidate = true;
        LeftMouseDownPos = MousePos;
    }
    if (GetKeyDown(VK_RBUTTON))
    {
        bRightDragCandidate = true;
        RightMouseDownPos = MousePos;
    }

    // Left drag
    if (!bLeftDragging && IsDraggingLeft())
    {
        FilterDragThreshold(bLeftDragCandidate, bLeftDragging, bLeftDragJustStarted,
            LeftMouseDownPos, LeftDragStartPos);
    }
    else if (GetKeyUp(VK_LBUTTON))
    {
        if (bLeftDragging) bLeftDragJustEnded = true;
        bLeftDragging = false;
        bLeftDragCandidate = false;
    }

    // Right drag
    if (!bRightDragging && IsDraggingRight())
    {
        FilterDragThreshold(bRightDragCandidate, bRightDragging, bRightDragJustStarted,
            RightMouseDownPos, RightDragStartPos);
    }
    else if (GetKeyUp(VK_RBUTTON))
    {
        if (bRightDragging) bRightDragJustEnded = true;
        bRightDragging = false;
        bRightDragCandidate = false;
    }

    UpdateCurrentSnapshot();
}

FInputSystemSnapshot InputSystem::TickAndMakeSnapshot()
{
    Tick();
    return MakeSnapshot();
}

FInputSystemSnapshot InputSystem::MakeSnapshot() const
{
    return CurrentSnapshot;
}

void InputSystem::RefreshSnapshot()
{
    UpdateCurrentSnapshot();
}

void InputSystem::SetUseRawMouse(bool bEnable)
{
    if (bUseRawMouse == bEnable)
    {
        return;
    }

    bUseRawMouse = bEnable;
    ResetMouseDelta();
    UpdateCurrentSnapshot();
}

void InputSystem::AddRawMouseDelta(int DeltaX, int DeltaY)
{
    RawMouseDeltaAccumX += DeltaX;
    RawMouseDeltaAccumY += DeltaY;
}

void InputSystem::ResetTransientState()
{
    bLeftDragJustStarted = false;
    bRightDragJustStarted = false;
    bLeftDragJustEnded = false;
    bRightDragJustEnded = false;
    ResetDragState();
    ResetMouseDelta();
    ResetWheelDelta();
    UpdateCurrentSnapshot();
}

void InputSystem::ResetAllKeyStates()
{
    for (int VK = 0; VK < 256; ++VK)
    {
        CurrentStates[VK] = false;
        PrevStates[VK] = false;
    }
    UpdateCurrentSnapshot();
}

void InputSystem::ResetMouseDelta()
{
    GetCursorPos(&MousePos);
    PrevMousePos = MousePos;
    FrameMouseDeltaX = 0;
    FrameMouseDeltaY = 0;
    RawMouseDeltaAccumX = 0;
    RawMouseDeltaAccumY = 0;
    UpdateCurrentSnapshot();
}

void InputSystem::ResetWheelDelta()
{
    ScrollDelta = 0;
    PrevScrollDelta = 0;
    UpdateCurrentSnapshot();
}

void InputSystem::ResetCaptureStateForPIEEnd()
{
    SetUseRawMouse(false);
    ResetAllKeyStates();
    ResetTransientState();
    GuiState.bUsingMouse = false;
    GuiState.bUsingKeyboard = false;
    GuiState.bUsingTextInput = false;
    UpdateCurrentSnapshot();
}

void InputSystem::UpdateCurrentSnapshot()
{
    FInputSystemSnapshot Snapshot{};
    for (int VK = 0; VK < 256; ++VK)
    {
        Snapshot.KeyDown[VK] = CurrentStates[VK];
        Snapshot.KeyPressed[VK] = CurrentStates[VK] && !PrevStates[VK];
        Snapshot.KeyReleased[VK] = !CurrentStates[VK] && PrevStates[VK];
    }

    Snapshot.bLeftMouseDown = Snapshot.KeyDown[VK_LBUTTON];
    Snapshot.bLeftMousePressed = Snapshot.KeyPressed[VK_LBUTTON];
    Snapshot.bLeftMouseReleased = Snapshot.KeyReleased[VK_LBUTTON];
    Snapshot.bRightMouseDown = Snapshot.KeyDown[VK_RBUTTON];
    Snapshot.bRightMousePressed = Snapshot.KeyPressed[VK_RBUTTON];
    Snapshot.bRightMouseReleased = Snapshot.KeyReleased[VK_RBUTTON];
    Snapshot.bMiddleMouseDown = Snapshot.KeyDown[VK_MBUTTON];
    Snapshot.bMiddleMousePressed = Snapshot.KeyPressed[VK_MBUTTON];
    Snapshot.bMiddleMouseReleased = Snapshot.KeyReleased[VK_MBUTTON];
    Snapshot.bXButton1Down = Snapshot.KeyDown[VK_XBUTTON1];
    Snapshot.bXButton1Pressed = Snapshot.KeyPressed[VK_XBUTTON1];
    Snapshot.bXButton1Released = Snapshot.KeyReleased[VK_XBUTTON1];
    Snapshot.bXButton2Down = Snapshot.KeyDown[VK_XBUTTON2];
    Snapshot.bXButton2Pressed = Snapshot.KeyPressed[VK_XBUTTON2];
    Snapshot.bXButton2Released = Snapshot.KeyReleased[VK_XBUTTON2];

    Snapshot.MousePos = MousePos;
    Snapshot.MouseDeltaX = FrameMouseDeltaX;
    Snapshot.MouseDeltaY = FrameMouseDeltaY;
    Snapshot.ScrollDelta = PrevScrollDelta;

    Snapshot.bLeftDragStarted = bLeftDragJustStarted;
    Snapshot.bLeftDragging = bLeftDragging;
    Snapshot.bLeftDragEnded = bLeftDragJustEnded;
    Snapshot.LeftDragVector = GetLeftDragVector();

    Snapshot.bRightDragStarted = bRightDragJustStarted;
    Snapshot.bRightDragging = bRightDragging;
    Snapshot.bRightDragEnded = bRightDragJustEnded;
    Snapshot.RightDragVector = GetRightDragVector();

    Snapshot.bUsingRawMouse = bUseRawMouse;
    Snapshot.bGuiUsingMouse = GuiState.bUsingMouse;
    Snapshot.bGuiUsingKeyboard = GuiState.bUsingKeyboard;
    Snapshot.bGuiUsingTextInput = GuiState.bUsingTextInput;
    Snapshot.bWindowFocused = bWindowFocused;

    for (int Axis = 0; Axis < static_cast<int>(EGamepadAxis::Count); ++Axis)
    {
        Snapshot.GamepadAxes[Axis] = GamepadAxes[Axis];
    }
    Snapshot.bGamepadConnected = bGamepadConnected;

    CurrentSnapshot = Snapshot;
}

// XInput 패드 0번을 폴링해서 디지털 버튼은 VK_GAMEPAD_* 키 슬롯에,
// 아날로그 스틱/트리거는 GamepadAxes에 넣는다. Tick의 256키 루프 직후 호출 전제
// (루프가 Prev 스냅샷을 이미 떠놔서 GetKeyDown/Up 에지가 그대로 동작한다).
void InputSystem::PollGamepad()
{
    // 미연결 상태의 XInputGetState는 내부 장치 열거 때문에 비싸다 — 간격을 두고 재시도
    if (!bGamepadConnected && GamepadReconnectCooldown > 0)
    {
        --GamepadReconnectCooldown;
        return;
    }

    XINPUT_STATE State = {};
    if (XInputGetState(0, &State) != ERROR_SUCCESS)
    {
        bGamepadConnected = false;
        GamepadReconnectCooldown = 120;
        ClearGamepadAxes();
        return;
    }
    bGamepadConnected = true;

    const WORD Buttons = State.Gamepad.wButtons;
    CurrentStates[VK_GAMEPAD_A] = (Buttons & XINPUT_GAMEPAD_A) != 0;
    CurrentStates[VK_GAMEPAD_B] = (Buttons & XINPUT_GAMEPAD_B) != 0;
    CurrentStates[VK_GAMEPAD_X] = (Buttons & XINPUT_GAMEPAD_X) != 0;
    CurrentStates[VK_GAMEPAD_Y] = (Buttons & XINPUT_GAMEPAD_Y) != 0;
    CurrentStates[VK_GAMEPAD_LEFT_SHOULDER] = (Buttons & XINPUT_GAMEPAD_LEFT_SHOULDER) != 0;
    CurrentStates[VK_GAMEPAD_RIGHT_SHOULDER] = (Buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0;
    CurrentStates[VK_GAMEPAD_DPAD_UP] = (Buttons & XINPUT_GAMEPAD_DPAD_UP) != 0;
    CurrentStates[VK_GAMEPAD_DPAD_DOWN] = (Buttons & XINPUT_GAMEPAD_DPAD_DOWN) != 0;
    CurrentStates[VK_GAMEPAD_DPAD_LEFT] = (Buttons & XINPUT_GAMEPAD_DPAD_LEFT) != 0;
    CurrentStates[VK_GAMEPAD_DPAD_RIGHT] = (Buttons & XINPUT_GAMEPAD_DPAD_RIGHT) != 0;
    CurrentStates[VK_GAMEPAD_MENU] = (Buttons & XINPUT_GAMEPAD_START) != 0;
    CurrentStates[VK_GAMEPAD_VIEW] = (Buttons & XINPUT_GAMEPAD_BACK) != 0;
    CurrentStates[VK_GAMEPAD_LEFT_THUMBSTICK_BUTTON] = (Buttons & XINPUT_GAMEPAD_LEFT_THUMB) != 0;
    CurrentStates[VK_GAMEPAD_RIGHT_THUMBSTICK_BUTTON] = (Buttons & XINPUT_GAMEPAD_RIGHT_THUMB) != 0;

    // 트리거는 아날로그지만 임계값을 넘으면 디지털 버튼으로도 노출 (Lua GetKey* 호환)
    CurrentStates[VK_GAMEPAD_LEFT_TRIGGER] = State.Gamepad.bLeftTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD;
    CurrentStates[VK_GAMEPAD_RIGHT_TRIGGER] = State.Gamepad.bRightTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD;

    GamepadAxes[static_cast<int>(EGamepadAxis::LeftX)] = ApplyStickDeadzone(State.Gamepad.sThumbLX, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);
    GamepadAxes[static_cast<int>(EGamepadAxis::LeftY)] = ApplyStickDeadzone(State.Gamepad.sThumbLY, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);
    GamepadAxes[static_cast<int>(EGamepadAxis::RightX)] = ApplyStickDeadzone(State.Gamepad.sThumbRX, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE);
    GamepadAxes[static_cast<int>(EGamepadAxis::RightY)] = ApplyStickDeadzone(State.Gamepad.sThumbRY, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE);
    GamepadAxes[static_cast<int>(EGamepadAxis::LeftTrigger)] = ApplyTriggerDeadzone(State.Gamepad.bLeftTrigger, XINPUT_GAMEPAD_TRIGGER_THRESHOLD);
    GamepadAxes[static_cast<int>(EGamepadAxis::RightTrigger)] = ApplyTriggerDeadzone(State.Gamepad.bRightTrigger, XINPUT_GAMEPAD_TRIGGER_THRESHOLD);
}

void InputSystem::ClearGamepadAxes()
{
    for (int Axis = 0; Axis < static_cast<int>(EGamepadAxis::Count); ++Axis)
    {
        GamepadAxes[Axis] = 0.0f;
    }
}

void InputSystem::ResetDragState()
{
    bLeftDragCandidate = false;
    bRightDragCandidate = false;
    bLeftDragging = false;
    bRightDragging = false;
    bLeftDragJustStarted = false;
    bRightDragJustStarted = false;
    bLeftDragJustEnded = false;
    bRightDragJustEnded = false;
    LeftDragStartPos = MousePos;
    LeftMouseDownPos = MousePos;
    RightDragStartPos = MousePos;
    RightMouseDownPos = MousePos;
}

void InputSystem::FilterDragThreshold(
    bool& bCandidate, bool& bDragging, bool& bJustStarted,
    const POINT& MouseDownPos, POINT& DragStartPos)
{
    if (bCandidate && !bDragging)
    {
        int DX = MousePos.x - MouseDownPos.x;
        int DY = MousePos.y - MouseDownPos.y;
        int DistSq = DX * DX + DY * DY;

        if (DistSq >= DRAG_THRESHOLD * DRAG_THRESHOLD)
        {
            bJustStarted = true;
            bDragging = true;
            DragStartPos = MouseDownPos;
        }
    }
}

POINT InputSystem::GetLeftDragVector() const
{
    POINT V;
    V.x = MousePos.x - LeftDragStartPos.x;
    V.y = MousePos.y - LeftDragStartPos.y;
    return V;
}

POINT InputSystem::GetRightDragVector() const
{
    POINT V;
    V.x = MousePos.x - RightDragStartPos.x;
    V.y = MousePos.y - RightDragStartPos.y;
    return V;
}

float InputSystem::GetLeftDragDistance() const
{
    POINT V = GetLeftDragVector();
    return std::sqrt((float)(V.x * V.x + V.y * V.y));
}

float InputSystem::GetRightDragDistance() const
{
    POINT V = GetRightDragVector();
    return std::sqrt((float)(V.x * V.x + V.y * V.y));
}
