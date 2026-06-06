#include "Engine/Platform/WindowsWindow.h"

void FWindowsWindow::Initialize(HWND InHWindow)
{
	HWindow = InHWindow;

	RECT Rect;
	GetClientRect(HWindow, &Rect);
	Width = static_cast<float>(Rect.right - Rect.left);
	Height = static_cast<float>(Rect.bottom - Rect.top);
}

void FWindowsWindow::OnResized(unsigned int InWidth, unsigned int InHeight)
{
	Width = static_cast<float>(InWidth);
	Height = static_cast<float>(InHeight);
}

POINT FWindowsWindow::ScreenToClientPoint(POINT ScreenPoint) const
{
	ScreenToClient(HWindow, &ScreenPoint);
	return ScreenPoint;
}

bool FWindowsWindow::EnterBorderlessFullscreen()
{
	if (!HWindow)
	{
		return false;
	}

	if (bIsBorderlessFullscreen)
	{
		return true;
	}

	SavedWindowStyle = static_cast<DWORD>(GetWindowLongPtrW(HWindow, GWL_STYLE));
	SavedWindowExStyle = static_cast<DWORD>(GetWindowLongPtrW(HWindow, GWL_EXSTYLE));
	SavedWindowPlacement = { sizeof(WINDOWPLACEMENT) };
	GetWindowPlacement(HWindow, &SavedWindowPlacement);

	MONITORINFO MonitorInfo = {};
	MonitorInfo.cbSize = sizeof(MONITORINFO);
	const HMONITOR Monitor = MonitorFromWindow(HWindow, MONITOR_DEFAULTTONEAREST);
	if (!GetMonitorInfoW(Monitor, &MonitorInfo))
	{
		return false;
	}

	const DWORD FullscreenStyle = (SavedWindowStyle & ~WS_OVERLAPPEDWINDOW) | WS_POPUP | WS_VISIBLE;
	SetWindowLongPtrW(HWindow, GWL_STYLE, static_cast<LONG_PTR>(FullscreenStyle));
	SetWindowLongPtrW(HWindow, GWL_EXSTYLE, static_cast<LONG_PTR>(SavedWindowExStyle));
	SetWindowPos(
		HWindow,
		HWND_TOP,
		MonitorInfo.rcMonitor.left,
		MonitorInfo.rcMonitor.top,
		MonitorInfo.rcMonitor.right - MonitorInfo.rcMonitor.left,
		MonitorInfo.rcMonitor.bottom - MonitorInfo.rcMonitor.top,
		SWP_FRAMECHANGED | SWP_SHOWWINDOW);

	bIsBorderlessFullscreen = true;
	return true;
}

void FWindowsWindow::ExitBorderlessFullscreen()
{
	if (!HWindow || !bIsBorderlessFullscreen)
	{
		return;
	}

	SetWindowLongPtrW(HWindow, GWL_STYLE, static_cast<LONG_PTR>(SavedWindowStyle));
	SetWindowLongPtrW(HWindow, GWL_EXSTYLE, static_cast<LONG_PTR>(SavedWindowExStyle));
	SetWindowPlacement(HWindow, &SavedWindowPlacement);
	SetWindowPos(
		HWindow,
		nullptr,
		0,
		0,
		0,
		0,
		SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW);

	bIsBorderlessFullscreen = false;
}
