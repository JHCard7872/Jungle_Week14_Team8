#pragma once

#include "Object/Object.h"
#include "Slate/SWindow.h"
#include "Viewport/ViewportClient.h"
#include "Input/InputSystem.h"

#include "Source/Engine/Viewport/GameViewportClient.generated.h"
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

class FViewport;
class UCameraComponent;

// UE's UGameViewportClient equivalent.
UCLASS()
class UGameViewportClient : public UObject, public FViewportClient
{
public:
	GENERATED_BODY()
	UGameViewportClient() = default;
	~UGameViewportClient() override = default;

	void Draw(FViewport* Viewport, float DeltaTime) override {}
	bool InputKey(int32 Key, bool bPressed) override { return false; }

	void SetViewport(FViewport* InViewport) { Viewport = InViewport; }
	FViewport* GetViewport() const { return Viewport; }
	void SetOwnerWindow(HWND InOwnerHWnd) { OwnerHWnd = InOwnerHWnd; }
	void SetCursorClipRect(const FRect& InViewportScreenRect);
	void SetCursorVisible(bool bVisible);
	bool IsCursorVisible() const { return bCursorVisible; }
	bool GetMouseViewportPosition(POINT& OutMousePos) const;

	void SetInputPossessed(bool bPossessed);
	bool IsPossessed() const { return bInputPossessed; }

	void BeginGameSession(FViewport* InViewport);
	void EndGameSession();

	void ResetInputState();
	void ProcessInput(const FInputSystemSnapshot& Snapshot, float DeltaTime);

	const FInputSystemSnapshot& GetGameInputSnapshot() const { return GameInputSnapshot; }

private:
	void SetCursorCaptured(bool bCaptured);
	void ApplyCursorClip();

	bool GetEffectiveCursorClientRect(RECT& OutClientRect) const;
	void LockCursorToViewportCenter();

	void SetGameInputSnapshot(const FInputSystemSnapshot& Snapshot);
	void ClearGameInputSnapshot();

	FViewport* Viewport = nullptr;
	HWND OwnerHWnd = nullptr;
	RECT CursorClipClientRect = {};
	bool bHasCursorClipRect = false;
	bool bInputPossessed = false;
	bool bCursorCaptured = false;
	bool bCursorVisible = true;

	FInputSystemSnapshot GameInputSnapshot{};
	bool bHasGameInputSnapshot = false;
};
