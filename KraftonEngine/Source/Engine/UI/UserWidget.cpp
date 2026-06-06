#include "UI/UserWidget.h"

#include "Object/Reflection/ObjectFactory.h"
#include "UI/UIManager.h"
#include <RmlUi/Core/Element.h>
#include <RmlUi/Core/Elements/ElementFormControl.h>

namespace
{
	void RegisterWidgetEventListeners(
		Rml::ElementDocument* Document,
		const TArray<std::pair<FString, sol::protected_function>>& Bindings,
		const FString& EventName,
		const FString& LogLabel,
		TArray<FWidgetEventListener*>& OutListeners)
	{
		for (const auto& Binding : Bindings)
		{
			Rml::Element* Element = Document->GetElementById(Binding.first);
			if (!Element)
			{
				UE_LOG("[RmlUi] %s target not found: %s", LogLabel.c_str(), Binding.first.c_str());
				continue;
			}

			auto* Listener = new FWidgetEventListener(Binding.first, EventName, LogLabel, Binding.second);
			Element->AddEventListener(EventName.c_str(), Listener);
			OutListeners.push_back(Listener);
		}
	}
}

void UUserWidget::BeginDestroy()
{
    if (HasAnyFlags(RF_BeginDestroy))
    {
        return;
    }

    RemoveFromParent();
    ClearEventListeners();
    PendingClickBindings.clear();
    PendingHoverBindings.clear();
    ClearDocument();

    OwningPlayer.Reset();

    UObject::BeginDestroy();
}

void UUserWidget::AddReferencedObjects(FReferenceCollector& Collector)
{
    UObject::AddReferencedObjects(Collector);
}

void UUserWidget::Initialize(APlayerController* InOwningPlayer, const FString& InDocumentPath)
{
	OwningPlayer = InOwningPlayer;
	DocumentPath = InDocumentPath;
}

void UUserWidget::AddToViewport(int32 InZOrder)
{
	ZOrder = InZOrder;
	bInViewport = true;
	UUIManager::Get().AddToViewport(this, InZOrder);
}

void UUserWidget::RemoveFromParent()
{
	UUIManager::Get().RemoveFromViewport(this);
	bInViewport = false;
}

void UUserWidget::BindClick(const FString& ElementId, sol::protected_function Callback)
{
	PendingClickBindings.push_back({ ElementId, Callback });
	if (IsDocumentLoaded())
	{
		RegisterEventListeners();
	}
}

void UUserWidget::BindHover(const FString& ElementId, sol::protected_function Callback)
{
	PendingHoverBindings.push_back({ ElementId, Callback });
	if (IsDocumentLoaded())
	{
		RegisterEventListeners();
	}
}

void UUserWidget::RegisterEventListeners()
{
	if (!Document)
	{
		return;
	}

	ClearEventListeners();
	RegisterWidgetEventListeners(Document, PendingClickBindings, "click", "click", EventListeners);
	RegisterWidgetEventListeners(Document, PendingHoverBindings, "mouseover", "hover", EventListeners);
}

void UUserWidget::ClearEventListeners()
{
	if (Document)
	{
		for (FWidgetEventListener* Listener : EventListeners)
		{
			if (!Listener)
			{
				continue;
			}

			Rml::Element* Element = Document->GetElementById(Listener->GetElementId());
			if (Element)
			{
				Element->RemoveEventListener(Listener->GetEventName().c_str(), Listener);
			}
		}
	}

	for (FWidgetEventListener* Listener : EventListeners)
	{
		delete Listener;
	}
	EventListeners.clear();
}

void UUserWidget::SetText(const FString& ElementId, const FString& Text)
{
	if (!Document)
	{
		return;
	}

	Rml::Element* Element = Document->GetElementById(ElementId);
	if (!Element)
	{
		UE_LOG("[RmlUi] Text target not found: %s", ElementId.c_str());
		return;
	}

	Element->SetInnerRML(Text.c_str());
}

bool UUserWidget::SetProperty(const FString& ElementId, const FString& PropertyName, const FString& Value)
{
	if (!Document)
	{
		return false;
	}

	Rml::Element* Element = Document->GetElementById(ElementId);
	if (!Element)
	{
		UE_LOG("[RmlUi] Property target not found: %s", ElementId.c_str());
		return false;
	}

	return Element->SetProperty(PropertyName.c_str(), Value.c_str());
}

bool UUserWidget::SetAttribute(const FString& ElementId, const FString& AttributeName, const FString& Value)
{
	if (!Document)
	{
		return false;
	}

	Rml::Element* Element = Document->GetElementById(ElementId);
	if (!Element)
	{
		UE_LOG("[RmlUi] Attribute target not found: %s", ElementId.c_str());
		return false;
	}

	// img의 src처럼 스타일 프로퍼티가 아닌 요소 속성용 — SetProperty로 넣으면
	// RmlUi가 인라인 스타일 파싱 오류를 낸다
	Element->SetAttribute(AttributeName.c_str(), Rml::String(Value.c_str()));
	return true;
}

FString UUserWidget::GetValue(const FString& ElementId) const
{
	if (!Document)
	{
		return "";
	}

	Rml::Element* Element = Document->GetElementById(ElementId);
	if (!Element)
	{
		UE_LOG("[RmlUi] Value target not found: %s", ElementId.c_str());
		return "";
	}

	Rml::ElementFormControl* FormControl = rmlui_dynamic_cast<Rml::ElementFormControl*>(Element);
	if (!FormControl)
	{
		UE_LOG("[RmlUi] Value target is not a form control: %s", ElementId.c_str());
		return "";
	}

	return FormControl->GetValue();
}

bool UUserWidget::SetValue(const FString& ElementId, const FString& Value)
{
	if (!Document)
	{
		return false;
	}

	Rml::Element* Element = Document->GetElementById(ElementId);
	if (!Element)
	{
		UE_LOG("[RmlUi] Value target not found: %s", ElementId.c_str());
		return false;
	}

	Rml::ElementFormControl* FormControl = rmlui_dynamic_cast<Rml::ElementFormControl*>(Element);
	if (!FormControl)
	{
		UE_LOG("[RmlUi] Value target is not a form control: %s", ElementId.c_str());
		return false;
	}

	FormControl->SetValue(Value.c_str());
	return true;
}
