#include "Engine/Platform/WindowsApplication.h"
#include "Engine/Platform/resource.h"

#include <windowsx.h>
#include <vector>

#include "Core/ProjectSettings.h"
#include "Engine/Input/InputSystem.h"

// ImGui Win32 메시지 핸들러
extern LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, unsigned int Msg, WPARAM wParam, LPARAM lParam);

namespace
{
	constexpr uint32 DefaultGameWindowWidth = 1920;
	constexpr uint32 DefaultGameWindowHeight = 1080;

	void ResolveGameWindowSettings(uint32& OutWidth, uint32& OutHeight, bool& OutFullscreen)
	{
		FProjectSettings& ProjectSettings = FProjectSettings::Get();
		ProjectSettings.LoadFromFile(FProjectSettings::GetDefaultPath());

		OutWidth = ProjectSettings.Game.GameWindowWidth > 0 ? ProjectSettings.Game.GameWindowWidth : DefaultGameWindowWidth;
		OutHeight = ProjectSettings.Game.GameWindowHeight > 0 ? ProjectSettings.Game.GameWindowHeight : DefaultGameWindowHeight;
#if WITH_STANDALONE
		OutFullscreen = ProjectSettings.Game.bStartFullscreen;
#else
		OutFullscreen = false;
#endif
	}
}

LRESULT CALLBACK FWindowsApplication::StaticWndProc(HWND hWnd, unsigned int Msg, WPARAM wParam, LPARAM lParam)
{
	FWindowsApplication* App = reinterpret_cast<FWindowsApplication*>(GetWindowLongPtr(hWnd, GWLP_USERDATA));

	if (Msg == WM_NCCREATE)
	{
		CREATESTRUCT* CreateStruct = reinterpret_cast<CREATESTRUCT*>(lParam);
		App = reinterpret_cast<FWindowsApplication*>(CreateStruct->lpCreateParams);
		SetWindowLongPtr(hWnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(App));
	}

	if (App)
	{
		return App->WndProc(hWnd, Msg, wParam, lParam);
	}

	return DefWindowProc(hWnd, Msg, wParam, lParam);
}

LRESULT FWindowsApplication::WndProc(HWND hWnd, unsigned int Msg, WPARAM wParam, LPARAM lParam)
{
	if (ImGui_ImplWin32_WndProcHandler(hWnd, Msg, wParam, lParam))
	{
		return true;
	}

	switch (Msg)
	{
	case WM_DESTROY:
		PostQuitMessage(0);
		return 0;
	case WM_MOUSEWHEEL:
		InputSystem::Get().AddScrollDelta(GET_WHEEL_DELTA_WPARAM(wParam));
		return 0;
	case WM_CHAR:
		InputSystem::Get().AddTextChar(static_cast<wchar_t>(wParam));
		return 0;
	case WM_INPUT:
	{
		UINT DataSize = 0;
		if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lParam), RID_INPUT, nullptr, &DataSize, sizeof(RAWINPUTHEADER)) != 0 || DataSize == 0)
		{
			return 0;
		}

		std::vector<BYTE> Buffer(DataSize);
		if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lParam), RID_INPUT, Buffer.data(), &DataSize, sizeof(RAWINPUTHEADER)) != DataSize)
		{
			return 0;
		}

		const RAWINPUT* Raw = reinterpret_cast<const RAWINPUT*>(Buffer.data());
		if (Raw->header.dwType == RIM_TYPEMOUSE)
		{
			InputSystem::Get().AddRawMouseDelta(
				static_cast<int>(Raw->data.mouse.lLastX),
				static_cast<int>(Raw->data.mouse.lLastY));
		}
		return 0;
	}
	case WM_SIZE:
		if (wParam != SIZE_MINIMIZED)
		{
			unsigned int Width = LOWORD(lParam);
			unsigned int Height = HIWORD(lParam);
			Window.OnResized(Width, Height);
			if (OnResizedCallback)
			{
				OnResizedCallback(Width, Height);
			}
		}
		return 0;
	case WM_ENTERSIZEMOVE:
		bIsResizing = true;
		return 0;
	case WM_EXITSIZEMOVE:
		bIsResizing = false;
		return 0;
	case WM_SIZING:
		if (OnSizingCallback)
		{
			OnSizingCallback();
		}
		return 0;
	default:
		break;
	}

	return DefWindowProc(hWnd, Msg, wParam, lParam);
}

bool FWindowsApplication::Init(HINSTANCE InHInstance)
{
	HInstance = InHInstance;

	WCHAR WindowClass[] = L"JungleWindowClass";
	WCHAR Title[] = L"Game Tech Lab";
	WNDCLASSEXW WndClass = {};
	WndClass.cbSize = sizeof(WNDCLASSEXW);
	WndClass.lpfnWndProc = StaticWndProc;
	WndClass.hInstance = HInstance;
	WndClass.hIcon = LoadIconW(HInstance, MAKEINTRESOURCEW(IDI_APP_ICON));
	WndClass.hIconSm = LoadIconW(HInstance, MAKEINTRESOURCEW(IDI_APP_ICON));
	WndClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
	WndClass.lpszClassName = WindowClass;

	RegisterClassExW(&WndClass);

	uint32 RequestedWidth = DefaultGameWindowWidth;
	uint32 RequestedHeight = DefaultGameWindowHeight;
	bool bStartFullscreen = false;
	ResolveGameWindowSettings(RequestedWidth, RequestedHeight, bStartFullscreen);

	DWORD WindowStyle = WS_VISIBLE | (bStartFullscreen ? WS_POPUP : WS_OVERLAPPEDWINDOW);
	int WindowX = CW_USEDEFAULT;
	int WindowY = CW_USEDEFAULT;
	int WindowWidth = static_cast<int>(RequestedWidth);
	int WindowHeight = static_cast<int>(RequestedHeight);

	if (bStartFullscreen)
	{
		MONITORINFO MonitorInfo = {};
		MonitorInfo.cbSize = sizeof(MONITORINFO);
		HMONITOR Monitor = MonitorFromPoint(POINT{ 0, 0 }, MONITOR_DEFAULTTOPRIMARY);
		if (GetMonitorInfoW(Monitor, &MonitorInfo))
		{
			WindowX = MonitorInfo.rcMonitor.left;
			WindowY = MonitorInfo.rcMonitor.top;
			WindowWidth = MonitorInfo.rcMonitor.right - MonitorInfo.rcMonitor.left;
			WindowHeight = MonitorInfo.rcMonitor.bottom - MonitorInfo.rcMonitor.top;
		}
	}
	else
	{
		RECT WindowRect = { 0, 0, static_cast<LONG>(RequestedWidth), static_cast<LONG>(RequestedHeight) };
		AdjustWindowRect(&WindowRect, WindowStyle, FALSE);
		WindowWidth = WindowRect.right - WindowRect.left;
		WindowHeight = WindowRect.bottom - WindowRect.top;
	}

	HWND HWindow = CreateWindowExW(
		0,
		WindowClass,
		Title,
		WindowStyle,
		WindowX, WindowY,
		WindowWidth, WindowHeight,
		nullptr, nullptr, HInstance, this);

	if (!HWindow)
	{
		return false;
	}

	RAWINPUTDEVICE RawMouseDevice = {};
	RawMouseDevice.usUsagePage = 0x01;
	RawMouseDevice.usUsage = 0x02;
	RawMouseDevice.dwFlags = RIDEV_INPUTSINK;
	RawMouseDevice.hwndTarget = HWindow;
	RegisterRawInputDevices(&RawMouseDevice, 1, sizeof(RAWINPUTDEVICE));

	Window.Initialize(HWindow);
	return true;
}

void FWindowsApplication::PumpMessages()
{
	MSG Msg;
	while (PeekMessage(&Msg, nullptr, 0, 0, PM_REMOVE))
	{
		TranslateMessage(&Msg);
		DispatchMessage(&Msg);

		if (Msg.message == WM_QUIT)
		{
			bIsExitRequested = true;
			break;
		}
	}
}

void FWindowsApplication::Destroy()
{
	if (Window.GetHWND())
	{
		DestroyWindow(Window.GetHWND());
	}
}
