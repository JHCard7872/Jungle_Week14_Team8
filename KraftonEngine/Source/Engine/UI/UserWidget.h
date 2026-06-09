#pragma once

#include "Object/Object.h"
#include "Object/Ptr/WeakObjectPtr.h"
#include "Core/Logging/Log.h"
#include "Source/Engine/UI/UserWidget.generated.h"
#include <sol/sol.hpp>
#include <utility>

#ifdef GetNextSibling
#undef GetNextSibling
#endif
#ifdef GetFirstChild
#undef GetFirstChild
#endif
#include <RmlUi/Core.h>

class APlayerController;
class FWidgetEventListener;
namespace Rml { class ElementDocument; }

class FWidgetEventListener final : public Rml::EventListener
{
public:
	// Callback 은 sol::main_protected_function — 메인 thread 의 lua_State 를 캡처한다.
	// 그냥 sol::protected_function 으로 받으면, 바인딩이 코루틴(별도 lua thread) 안에서
	// 일어난 경우 그 코루틴 thread 포인터를 저장하게 되고, 코루틴이 Lua GC 로 회수되면
	// 위젯 파괴 시 deref 가 닫힌 thread 에 luaL_unref 를 호출해 lua51.dll 에서 크래시난다.
	FWidgetEventListener(FString InElementId, FString InEventName, FString InLogLabel, sol::main_protected_function InCallback)
		: ElementId(std::move(InElementId))
		, EventName(std::move(InEventName))
		, LogLabel(std::move(InLogLabel))
		, Callback(std::move(InCallback))
	{
	}

	void ProcessEvent(Rml::Event& /*Event*/) override
	{
		if (!Callback.valid())
		{
			return;
		}

		sol::protected_function_result Result = Callback();
		if (!Result.valid())
		{
			sol::error Err = Result;
			UE_LOG("[Lua] UI %s callback error: %s", LogLabel.c_str(), Err.what());
		}
	}

	const FString& GetElementId() const { return ElementId; }
	const FString& GetEventName() const { return EventName; }

private:
	FString ElementId;
	FString EventName;
	FString LogLabel;
	sol::main_protected_function Callback;
};

UCLASS()
class UUserWidget : public UObject
{
public:
	GENERATED_BODY()
	UUserWidget() = default;
	~UUserWidget() override = default;

    void BeginDestroy() override;
    void AddReferencedObjects(FReferenceCollector& Collector) override;

	void Initialize(APlayerController* InOwningPlayer, const FString& InDocumentPath);
	void AddToViewport(int32 InZOrder = 0);
	void RemoveFromParent();
	void BindClick(const FString& ElementId, sol::main_protected_function Callback);
	void BindHover(const FString& ElementId, sol::main_protected_function Callback);
	void BindMouseMove(const FString& ElementId, sol::main_protected_function Callback);
	void RegisterEventListeners();
	void ClearEventListeners();
	// 셧다운 시 lua_State 가 살아있는 동안 호출 — 위젯이 들고 있는 Lua 콜백을 모두 해제.
	// 안 하면 이후 GC 가 위젯을 파괴할 때 닫힌 lua_State 에 luaL_unref → 크래시.
	// [호출처: UUIManager::DestroyAllWidgets]
	void ReleaseLuaCallbacks();
	void SetText(const FString& ElementId, const FString& Text);
	bool SetProperty(const FString& ElementId, const FString& PropertyName, const FString& Value);
	bool SetAttribute(const FString& ElementId, const FString& AttributeName, const FString& Value);
	FString GetValue(const FString& ElementId) const;
	bool SetValue(const FString& ElementId, const FString& Value);

	APlayerController* GetOwningPlayer() const { return OwningPlayer.Get(); }
	const FString& GetDocumentPath() const { return DocumentPath; }
	int32 GetZOrder() const { return ZOrder; }
	bool IsInViewport() const { return bInViewport; }
	bool IsDocumentLoaded() const { return bDocumentLoaded; }
	Rml::ElementDocument* GetDocument() const { return Document; }

	// 메뉴/대화창처럼 사용자가 클릭/포인팅을 해야 하는 widget 은 true 로 설정.
	// UUIManager 가 viewport 에 올라온 widget 중 하나라도 이 값이 true 면 GameViewportClient
	// 에 알려 시스템 커서를 보이고 raw mouse / clip 을 해제하도록 한다. HUD 처럼 비대화형
	// 오버레이는 false 유지.
	void SetWantsMouse(bool bInWantsMouse) { bWantsMouse = bInWantsMouse; }
	bool WantsMouse() const { return bWantsMouse; }

	void MarkDocumentLoaded(Rml::ElementDocument* InDocument) { Document = InDocument; bDocumentLoaded = Document != nullptr; }
	void MarkRemovedFromViewport() { bInViewport = false; }
	void ClearDocument() { Document = nullptr; bDocumentLoaded = false; }

private:
	TWeakObjectPtr<APlayerController> OwningPlayer;
	Rml::ElementDocument* Document = nullptr;
	FString DocumentPath;
	TArray<std::pair<FString, sol::main_protected_function>> PendingClickBindings;
	TArray<std::pair<FString, sol::main_protected_function>> PendingHoverBindings;
	TArray<std::pair<FString, sol::main_protected_function>> PendingMouseMoveBindings;
	TArray<FWidgetEventListener*> EventListeners;
	int32 ZOrder = 0;
	bool bInViewport = false;
	bool bDocumentLoaded = false;
	bool bWantsMouse = false;
};
