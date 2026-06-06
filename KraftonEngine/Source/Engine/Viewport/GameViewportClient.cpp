#include "Viewport/GameViewportClient.h"
#include "Viewport/Viewport.h"

#include "Component/Camera/CameraComponent.h"
#include "Engine/Input/InputSystem.h"
#include "Math/MathUtils.h"
#include "UI/UIManager.h"
#include "Core/Logging/Log.h"

#include <windows.h>

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

void UGameViewportClient::ProcessInput(const FInputSystemSnapshot& Snapshot, float /*DeltaTime*/)
{
	SetGameInputSnapshot(Snapshot);

	if (!Snapshot.bWindowFocused)
	{
		InputSystem::Get().SetUseRawMouse(false);
		SetCursorCaptured(false);
		ResetInputState();
		return;
	}

	if (!bInputPossessed)
	{
		InputSystem::Get().SetUseRawMouse(false);
		SetCursorCaptured(false);
		return;
	}

	if (UUIManager::Get().AnyViewportWidgetWantsMouse())
	{
		InputSystem::Get().SetUseRawMouse(false);
		SetCursorCaptured(false);
		return;
	}

	InputSystem::Get().SetUseRawMouse(true);
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
