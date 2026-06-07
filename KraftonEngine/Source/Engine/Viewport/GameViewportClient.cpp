#include "Viewport/GameViewportClient.h"
#include "Viewport/Viewport.h"

#include "Component/Camera/CameraComponent.h"
#include "Engine/Input/InputSystem.h"
#include "Math/MathUtils.h"
#include "UI/UIManager.h"
#include "Core/Logging/Log.h"

#include <windows.h>

// 패드 우스틱 메뉴 커서 이동 속도 (풀기울임 px/s) — 느리면 이 값만 키우면 된다
static constexpr float GAMEPAD_CURSOR_SPEED = 1600.0f;

void UGameViewportClient::BeginGameSession(FViewport* InViewport)
{
	Viewport = InViewport;
	ResetInputState();
}

void UGameViewportClient::EndGameSession()
{
	SetInputPossessed(false);
	ResetInputState();
	bHasCursorClipRect = false;
	SetCursorCaptured(false);
	SetCursorVisible(true);
	Viewport = nullptr;
}

void UGameViewportClient::ProcessInput(const FInputSystemSnapshot& Snapshot, float DeltaTime)
{
	SetGameInputSnapshot(Snapshot);

	if (!Snapshot.bWindowFocused)
	{
		InputSystem::Get().SetUseRawMouse(false);
		InputSystem::Get().SetGamepadCursorEmulation(false);
		SetCursorCaptured(false);
		ResetInputState();
		return;
	}

	if (!bInputPossessed)
	{
		InputSystem::Get().SetUseRawMouse(false);
		InputSystem::Get().SetGamepadCursorEmulation(false);
		SetCursorCaptured(false);
		return;
	}

	// UI가 마우스를 원하는 상태(타이틀/결과/일시정지 메뉴) — 커서가 자유로우므로
	// 패드 우스틱으로 OS 커서를 움직이고 A를 왼클릭으로 합성한다 (게임플레이 캡처 중엔 비활성)
	if (UUIManager::Get().AnyViewportWidgetWantsMouse())
	{
		InputSystem::Get().SetUseRawMouse(false);
		InputSystem::Get().SetGamepadCursorEmulation(true);
		SetCursorCaptured(false);
		UpdateGamepadCursor(DeltaTime);
		return;
	}

	InputSystem::Get().SetUseRawMouse(true);
	InputSystem::Get().SetGamepadCursorEmulation(false);
	SetCursorCaptured(true);
	LockCursorToViewportCenter();
}

void UGameViewportClient::SetInputPossessed(bool bPossessed)
{
	if (bInputPossessed == bPossessed)
	{
		return;
	}

	bInputPossessed = bPossessed;
	ResetInputState();

	if (!bPossessed)
	{
		ClearGameInputSnapshot();
	}
}

void UGameViewportClient::SetCursorClipRect(const FRect& InViewportScreenRect)
{
	if (InViewportScreenRect.Width <= 1.0f || InViewportScreenRect.Height <= 1.0f)
	{
		bHasCursorClipRect = false;
		if (bCursorCaptured)
		{
			ApplyCursorClip();
		}
		return;
	}

	CursorClipClientRect.left = static_cast<LONG>(InViewportScreenRect.X);
	CursorClipClientRect.top = static_cast<LONG>(InViewportScreenRect.Y);
	CursorClipClientRect.right = static_cast<LONG>(InViewportScreenRect.X + InViewportScreenRect.Width);
	CursorClipClientRect.bottom = static_cast<LONG>(InViewportScreenRect.Y + InViewportScreenRect.Height);
	bHasCursorClipRect = CursorClipClientRect.right > CursorClipClientRect.left
		&& CursorClipClientRect.bottom > CursorClipClientRect.top;

	if (bCursorCaptured)
	{
		ApplyCursorClip();
	}
}

void UGameViewportClient::ResetInputState()
{
	InputSystem::Get().ResetMouseDelta();
	InputSystem::Get().ResetWheelDelta();
}

void UGameViewportClient::SetCursorCaptured(bool bCaptured)
{
	if (bCursorCaptured == bCaptured)
	{
		if (bCaptured)
		{
			ApplyCursorClip();
		}
		return;
	}

	bCursorCaptured = bCaptured;
	if (bCursorCaptured)
	{
		while (::ShowCursor(FALSE) >= 0) {}
		ApplyCursorClip();
		LockCursorToViewportCenter();
		return;
	}

	if (bCursorVisible)
	{
		while (::ShowCursor(TRUE) < 0) {}
	}
	else
	{
		while (::ShowCursor(FALSE) >= 0) {}
	}
	::ClipCursor(nullptr);
}

void UGameViewportClient::SetCursorVisible(bool bVisible)
{
	if (bCursorVisible == bVisible)
	{
		return;
	}

	bCursorVisible = bVisible;
	if (bCursorCaptured)
	{
		return;
	}

	if (bCursorVisible)
	{
		while (::ShowCursor(TRUE) < 0) {}
	}
	else
	{
		while (::ShowCursor(FALSE) >= 0) {}
	}
}

bool UGameViewportClient::GetMouseViewportPosition(POINT& OutMousePos) const
{
	FRect ViewportScreenRect{};
	if (bHasCursorClipRect)
	{
		ViewportScreenRect.X = static_cast<float>(CursorClipClientRect.left);
		ViewportScreenRect.Y = static_cast<float>(CursorClipClientRect.top);
		ViewportScreenRect.Width = static_cast<float>(CursorClipClientRect.right - CursorClipClientRect.left);
		ViewportScreenRect.Height = static_cast<float>(CursorClipClientRect.bottom - CursorClipClientRect.top);
	}
	else
	{
		if (!OwnerHWnd)
		{
			return false;
		}

		RECT ClientRect = {};
		if (!::GetClientRect(OwnerHWnd, &ClientRect))
		{
			return false;
		}

		ViewportScreenRect.X = static_cast<float>(ClientRect.left);
		ViewportScreenRect.Y = static_cast<float>(ClientRect.top);
		ViewportScreenRect.Width = static_cast<float>(ClientRect.right - ClientRect.left);
		ViewportScreenRect.Height = static_cast<float>(ClientRect.bottom - ClientRect.top);
	}

	const float ViewportWidth = Viewport ? static_cast<float>(Viewport->GetWidth()) : ViewportScreenRect.Width;
	const float ViewportHeight = Viewport ? static_cast<float>(Viewport->GetHeight()) : ViewportScreenRect.Height;
	if (ViewportScreenRect.Width <= 0.0f || ViewportScreenRect.Height <= 0.0f || ViewportWidth <= 0.0f || ViewportHeight <= 0.0f)
	{
		return false;
	}

	const POINT MouseClientPos = InputSystem::Get().GetMouseClientPos();
	const float NormalizedX = (static_cast<float>(MouseClientPos.x) - ViewportScreenRect.X) / ViewportScreenRect.Width;
	const float NormalizedY = (static_cast<float>(MouseClientPos.y) - ViewportScreenRect.Y) / ViewportScreenRect.Height;

	OutMousePos.x = static_cast<LONG>(NormalizedX * ViewportWidth);
	OutMousePos.y = static_cast<LONG>(NormalizedY * ViewportHeight);
	return true;
}

void UGameViewportClient::ApplyCursorClip()
{
	if (!OwnerHWnd)
	{
		return;
	}

	RECT ClientRect = {};
	if (!GetEffectiveCursorClientRect(ClientRect))
	{
		return;
	}

	POINT TopLeft = { ClientRect.left, ClientRect.top };
	POINT BottomRight = { ClientRect.right, ClientRect.bottom };
	if (!::ClientToScreen(OwnerHWnd, &TopLeft) || !::ClientToScreen(OwnerHWnd, &BottomRight))
	{
		return;
	}

	RECT ScreenRect = { TopLeft.x, TopLeft.y, BottomRight.x, BottomRight.y };
	if (ScreenRect.right > ScreenRect.left && ScreenRect.bottom > ScreenRect.top)
	{
		::ClipCursor(&ScreenRect);
	}
}

bool UGameViewportClient::GetEffectiveCursorClientRect(RECT& OutClientRect) const
{
	if (!OwnerHWnd)
	{
		return false;
	}

	if (bHasCursorClipRect)
	{
		OutClientRect = CursorClipClientRect;
	}
	else if (!::GetClientRect(OwnerHWnd, &OutClientRect))
	{
		return false;
	}

	return OutClientRect.right > OutClientRect.left
		&& OutClientRect.bottom > OutClientRect.top;
}

void UGameViewportClient::LockCursorToViewportCenter()
{
	if (!bCursorCaptured || !OwnerHWnd)
	{
		return;
	}

	RECT ClientRect = {};
	if (!GetEffectiveCursorClientRect(ClientRect))
	{
		return;
	}

	POINT CenterClient = {
		ClientRect.left + (ClientRect.right - ClientRect.left) / 2,
		ClientRect.top + (ClientRect.bottom - ClientRect.top) / 2
	};

	POINT CenterScreen = CenterClient;
	if (!::ClientToScreen(OwnerHWnd, &CenterScreen))
	{
		return;
	}

	POINT CurrentScreen = {};
	if (::GetCursorPos(&CurrentScreen) &&
		CurrentScreen.x == CenterScreen.x &&
		CurrentScreen.y == CenterScreen.y)
	{
		return;
	}

	::SetCursorPos(CenterScreen.x, CenterScreen.y);
}

// 패드 우스틱으로 OS 커서를 이동 (메뉴 전용 — ProcessInput의 wants-mouse 분기에서만 호출).
// 실제 SetCursorPos를 쓰므로 RmlUi hover/click이 마우스와 완전히 같은 경로로 동작한다.
// 고FPS에선 프레임당 이동량이 1px 미만이라 정수 절삭하면 안 움직인다(특히 대각) —
// 소수점 잔여를 멤버에 누적했다가 정수가 모이면 옮긴다.
void UGameViewportClient::UpdateGamepadCursor(float DeltaTime)
{
	InputSystem& Input = InputSystem::Get();
	const float StickX = Input.GetGamepadAxis(EGamepadAxis::RightX);
	const float StickY = Input.GetGamepadAxis(EGamepadAxis::RightY);
	if (StickX == 0.0f && StickY == 0.0f)
	{
		GamepadCursorRemainderX = 0.0f;
		GamepadCursorRemainderY = 0.0f;
		return;
	}

	POINT Cursor = {};
	if (!::GetCursorPos(&Cursor))
	{
		return;
	}

	const float Delta = GAMEPAD_CURSOR_SPEED * (DeltaTime > 0.0f ? DeltaTime : 0.0f);
	GamepadCursorRemainderX += StickX * Delta;
	GamepadCursorRemainderY -= StickY * Delta;   // 스틱 위(+)가 화면 위(y 감소)

	const LONG MoveX = static_cast<LONG>(GamepadCursorRemainderX);
	const LONG MoveY = static_cast<LONG>(GamepadCursorRemainderY);
	GamepadCursorRemainderX -= static_cast<float>(MoveX);
	GamepadCursorRemainderY -= static_cast<float>(MoveY);
	if (MoveX == 0 && MoveY == 0)
	{
		return;
	}

	Cursor.x += MoveX;
	Cursor.y += MoveY;

	// 게임 창 클라이언트 영역 밖으로 나가지 않게 클램프
	RECT ClientRect = {};
	if (GetEffectiveCursorClientRect(ClientRect) && OwnerHWnd)
	{
		POINT TopLeft = { ClientRect.left, ClientRect.top };
		POINT BottomRight = { ClientRect.right, ClientRect.bottom };
		if (::ClientToScreen(OwnerHWnd, &TopLeft) && ::ClientToScreen(OwnerHWnd, &BottomRight))
		{
			if (Cursor.x < TopLeft.x) { Cursor.x = TopLeft.x; }
			if (Cursor.x > BottomRight.x - 1) { Cursor.x = BottomRight.x - 1; }
			if (Cursor.y < TopLeft.y) { Cursor.y = TopLeft.y; }
			if (Cursor.y > BottomRight.y - 1) { Cursor.y = BottomRight.y - 1; }
		}
	}

	::SetCursorPos(Cursor.x, Cursor.y);
}

void UGameViewportClient::SetGameInputSnapshot(const FInputSystemSnapshot& Snapshot)
{
	GameInputSnapshot = Snapshot;
	POINT MouseViewportPos = {};
	if (GetMouseViewportPosition(MouseViewportPos))
	{
		GameInputSnapshot.MousePos = MouseViewportPos;
	}
	bHasGameInputSnapshot = true;
}

void UGameViewportClient::ClearGameInputSnapshot()
{
	GameInputSnapshot = FInputSystemSnapshot{};
	bHasGameInputSnapshot = false;
}
