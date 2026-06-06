#include "LuaScriptManager.h"

#include "Core/Logging/Log.h"
#include "Core/Logging/Notification.h"
#include "Audio/AudioManager.h"
#include "Component/Input/ActionComponent.h"
#include "Component/Script/LuaScriptComponent.h"
#include "Component/Input/InputComponent.h"
#include "Animation/Instance/LuaAnimInstance.h"
#include "Component/Movement/FloatingPawnMovementComponent.h"
#include "Component/Camera/CameraComponent.h"
#include "Component/PrimitiveComponent.h"
#include "Component/SceneComponent.h"
#include "Component/Primitive/ParticleSystemComponent.h"
#include "Component/Primitive/StaticMeshComponent.h"

#include "Particles/ParticleSystem.h"
#include "Particles/ParticleSystemManager.h"
#include "Core/Types/CollisionTypes.h"
#include "Runtime/Engine.h"
#include "Viewport/GameViewportClient.h"
#include "Viewport/Viewport.h"
#include "Input/InputSystem.h"
#include "Physics/BodyInstance.h"
#include "GameFramework/AActor.h"
#include "GameFramework/Pawn/Character.h"
#include "GameFramework/Pawn/Pawn.h"
#include "GameFramework/GameMode/PlayerController.h"
#include "GameFramework/Camera/PlayerCameraManager.h"
#include "GameFramework/Camera/WaveOscillatorCameraShake.h"
#include "GameFramework/Camera/SequenceCameraShake.h"
#include "GameFramework/GameMode/GameplayStatics.h"
#include "GameFramework/World.h"
#include "Render/Types/MinimalViewInfo.h"
#include "Object/Reflection/UClass.h"
#include "Object/Reflection/UStruct.h"
#include "Object/Object.h"
#include "Component/ActorComponent.h"
#include "Core/Property/ArrayProperty.h"
#include "Core/Property/BoolProperty.h"
#include "Core/Property/ClassProperty.h"
#include "Core/Property/EnumProperty.h"
#include "Core/Property/NameProperty.h"
#include "Core/Property/NumericProperty.h"
#include "Core/Property/ObjectProperty.h"
#include "Core/Property/SoftObjectProperty.h"
#include "Core/Property/StringProperty.h"
#include "Core/Property/StructProperty.h"
#include "Platform/Paths.h"
#include "Math/Vector.h"
#include "Math/Rotator.h"
#include "Math/MathUtils.h"
#include "Particles/ParticleEmitterInstances.h"
#include "Platform/WindowsWindow.h"
#include "UI/UIManager.h"
#include "UI/UserWidget.h"
#include <algorithm>
#include <cmath>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <windows.h>  // PostQuitMessage

std::unique_ptr<sol::state> FLuaScriptManager::Lua;
sol::protected_function FLuaScriptManager::OnEscapePressedCallback;
std::mutex FLuaScriptManager::ComponentMutex;
TArray<TWeakObjectPtr<ULuaScriptComponent>> FLuaScriptManager::RegisteredComponents;
TArray<TWeakObjectPtr<ULuaAnimInstance>>    FLuaScriptManager::RegisteredAnimInstances;
FSubscriptionID FLuaScriptManager::WatchSub = 0;

namespace
{
	bool GetLuaViewportSize(float& OutWidth, float& OutHeight)
	{
		OutWidth = 0.0f;
		OutHeight = 0.0f;

		if (!GEngine)
		{
			return false;
		}

		if (UGameViewportClient* GameViewportClient = GEngine->GetGameViewportClient())
		{
			if (FViewport* Viewport = GameViewportClient->GetViewport())
			{
				OutWidth = static_cast<float>(Viewport->GetWidth());
				OutHeight = static_cast<float>(Viewport->GetHeight());
				if (OutWidth > 0.0f && OutHeight > 0.0f)
				{
					return true;
				}
			}
		}

		if (FWindowsWindow* Window = GEngine->GetWindow())
		{
			OutWidth = static_cast<float>(Window->GetWidth());
			OutHeight = static_cast<float>(Window->GetHeight());
			return OutWidth > 0.0f && OutHeight > 0.0f;
		}

		return false;
	}

	struct FLuaReflectedEventOverride
	{
		TWeakObjectPtr<UObject> Target;
		sol::protected_function Callback;
	};

	TMap<FString, FLuaReflectedEventOverride> GLuaReflectedEventOverrides;

	FString MakeLuaReflectedEventKey(const UObject* Object, const FFunction& Function)
	{
		if (!Object)
		{
			return {};
		}
		return std::to_string(Object->GetUUID()) + "::" + Function.GetSignature();
	}

	void CompactLuaReflectedEventOverrides()
	{
		for (auto It = GLuaReflectedEventOverrides.begin(); It != GLuaReflectedEventOverrides.end(); )
		{
			if (!It->second.Target.IsValid() || !It->second.Callback.valid())
			{
				It = GLuaReflectedEventOverrides.erase(It);
				continue;
			}
			++It;
		}
	}

	template <typename FuncType>
	bool ApplyToBeamEmitters(UPrimitiveComponent& Component, FuncType Func)
	{
		UParticleSystemComponent* ParticleComponent = Cast<UParticleSystemComponent>(&Component);
		if (!ParticleComponent)
		{
			return false;
		}

		if (ParticleComponent->GetEmitterInstances().empty())
		{
			ParticleComponent->InitializeSystem();
		}

		bool bApplied = false;
		for (FParticleEmitterInstance* Instance : ParticleComponent->GetEmitterInstances())
		{
			FParticleBeam2EmitterInstance* BeamInstance = dynamic_cast<FParticleBeam2EmitterInstance*>(Instance);
			if (!BeamInstance)
			{
				continue;
			}

			Func(*BeamInstance);
			bApplied = true;
		}

		if (bApplied)
		{
			ParticleComponent->RefreshDynamicData();
		}

		return bApplied;
	}

	sol::table LuaPhysicsRaycast(
		sol::this_state        State,
		const FVector&         Start,
		const FVector&         Direction,
		float                  MaxDistance,
		sol::optional<AActor*> IgnoreActor)
	{
		sol::state_view L(State);
		sol::table      Result = L.create_table();

		FHitResult Hit{};
		FVector    TraceDir = Direction;
		FVector    End = Start;
		bool       bHit = false;

		const float DirLength = TraceDir.Length();
		if (DirLength > 1.0e-4f && MaxDistance > 0.0f)
		{
			TraceDir = TraceDir * (1.0f / DirLength);
			End = Start + TraceDir * MaxDistance;

			UWorld* CurrentWorld = GEngine ? GEngine->GetWorld() : nullptr;
			if (CurrentWorld)
			{
				bHit = CurrentWorld->PhysicsRaycast(
					Start,
					TraceDir,
					MaxDistance,
					Hit,
					ECollisionChannel::WorldStatic,
					IgnoreActor.value_or(nullptr));
			}

			if (bHit && Hit.bHit)
			{
				End = Hit.WorldHitLocation;
			}
			else
			{
				Hit = {};
				Hit.bHit = false;
				Hit.Distance = MaxDistance;
				Hit.WorldHitLocation = End;
			}
		}
		else
		{
			Hit = {};
			Hit.bHit = false;
			Hit.Distance = 0.0f;
			Hit.WorldHitLocation = Start;
		}

		Result["bHit"] = bHit && Hit.bHit;
		Result["Hit"] = Hit;
		Result["Location"] = Hit.WorldHitLocation;
		Result["WorldHitLocation"] = Hit.WorldHitLocation;
		Result["End"] = End;
		Result["Distance"] = Hit.Distance;
		Result["HitActor"] = Hit.HitActor;
		Result["HitComponent"] = Hit.HitComponent;
		Result["PhysicsBody"] = Hit.PhysicsBody;
		return Result;
	}
}

bool FLuaScriptManager::IsInitialized()
{
	return Lua != nullptr;
}

void FLuaScriptManager::SetOnEscapePressed(sol::protected_function Callback)
{
	OnEscapePressedCallback = std::move(Callback);
}

void FLuaScriptManager::RegisterComponent(ULuaScriptComponent* Component)
{
    if (!IsAliveObject(Component)) return;

	std::lock_guard<std::mutex> Lock(ComponentMutex);
	for (const TWeakObjectPtr<ULuaScriptComponent>& Existing : RegisteredComponents)
	{
		if (Existing.Get() == Component)
		{
			return;
		}
	}
	RegisteredComponents.push_back(Component);
}

void FLuaScriptManager::InvalidateChangedModules(const TSet<FString>& ChangedFiles)
{
	if (!Lua) return;

	sol::table Loaded = (*Lua)["package"]["loaded"];
	if (!Loaded.valid()) return;

	for (const FString& File : ChangedFiles)
	{
		FString ModuleName = GetModuleNameFromPath(File);
		if (ModuleName.empty()) continue;

		Loaded[ModuleName] = sol::nil;
		UE_LOG("[LuaHotReload] Invalidated module: %s", ModuleName.c_str());
	}
}

FString FLuaScriptManager::GetModuleNameFromPath(const FString& ScriptPath)
{
	if (ScriptPath.empty())
	{
		return {};
	}

	FString Normalized = ScriptPath;
	for (char& Ch : Normalized)
	{
		if (Ch == '\\')
		{
			Ch = '/';
		}
	}

	constexpr const char* LuaExt = ".lua";
	if (Normalized.size() <= 4 || Normalized.substr(Normalized.size() - 4) != LuaExt)
	{
		return {};
	}

	Normalized.erase(Normalized.size() - 4);

	// 캐시 키는 슬래시 형태로 통일 — require 래퍼(Initialize)가 '.' 를 '/' 로
	// 정규화해서 로드하므로, 핫리로드 무효화 키도 같은 형태여야 맞는다.
	return Normalized;
}

void FLuaScriptManager::UnregisterComponent(ULuaScriptComponent* Component)
{
	if (!Component) return;

	std::lock_guard<std::mutex> Lock(ComponentMutex);
	RegisteredComponents.erase(
		std::remove_if(
			RegisteredComponents.begin(),
			RegisteredComponents.end(),
			[Component](const TWeakObjectPtr<ULuaScriptComponent>& Existing)
			{
				return Existing.Get() == Component || !Existing.IsValid();
			}),
		RegisteredComponents.end());
}

void FLuaScriptManager::TickPrePhysics(float DeltaTime)
{
	if (!IsInitialized()) return;

	TArray<TWeakObjectPtr<ULuaScriptComponent>> Components;
	{
		std::lock_guard<std::mutex> Lock(ComponentMutex);
		RegisteredComponents.erase(
			std::remove_if(
				RegisteredComponents.begin(),
				RegisteredComponents.end(),
				[](const TWeakObjectPtr<ULuaScriptComponent>& Component) { return !Component.IsValid(); }),
			RegisteredComponents.end());
		Components = RegisteredComponents;
	}

	for (const TWeakObjectPtr<ULuaScriptComponent>& ComponentPtr : Components)
	{
		ULuaScriptComponent* Component = ComponentPtr.Get();
		if (IsValid(Component))
		{
			Component->TickPrePhysics(DeltaTime);
		}
	}
}

void FLuaScriptManager::TickPostCamera(float DeltaTime)
{
	if (!IsInitialized()) return;

	TArray<TWeakObjectPtr<ULuaScriptComponent>> Components;
	{
		std::lock_guard<std::mutex> Lock(ComponentMutex);
		RegisteredComponents.erase(
			std::remove_if(
				RegisteredComponents.begin(),
				RegisteredComponents.end(),
				[](const TWeakObjectPtr<ULuaScriptComponent>& Component) { return !Component.IsValid(); }),
			RegisteredComponents.end());
		Components = RegisteredComponents;
	}

	for (const TWeakObjectPtr<ULuaScriptComponent>& ComponentPtr : Components)
	{
		ULuaScriptComponent* Component = ComponentPtr.Get();
		if (IsValid(Component))
		{
			Component->TickPostCamera(DeltaTime);
		}
	}
}

void FLuaScriptManager::RegisterAnimInstance(ULuaAnimInstance* Instance)
{
    if (!IsAliveObject(Instance)) return;
	std::lock_guard<std::mutex> Lock(ComponentMutex);
	for (const TWeakObjectPtr<ULuaAnimInstance>& Existing : RegisteredAnimInstances)
	{
		if (Existing.Get() == Instance)
		{
			return;
		}
	}
	RegisteredAnimInstances.push_back(Instance);
}

void FLuaScriptManager::UnregisterAnimInstance(ULuaAnimInstance* Instance)
{
	if (!Instance) return;
	std::lock_guard<std::mutex> Lock(ComponentMutex);
	RegisteredAnimInstances.erase(
		std::remove_if(
			RegisteredAnimInstances.begin(),
			RegisteredAnimInstances.end(),
			[Instance](const TWeakObjectPtr<ULuaAnimInstance>& Existing)
			{
				return Existing.Get() == Instance || !Existing.IsValid();
			}),
		RegisteredAnimInstances.end());
}

void FLuaScriptManager::OnScriptsChanged(const TSet<FString>& ChangedFiles)
{
	TSet<ULuaScriptComponent*> Targets;

	InvalidateChangedModules(ChangedFiles);

	{
		std::lock_guard<std::mutex> Lock(ComponentMutex);
        RegisteredComponents.erase(
            std::remove_if(
                RegisteredComponents.begin(),
                RegisteredComponents.end(),
                [](const TWeakObjectPtr<ULuaScriptComponent>& Component) { return !Component.IsValid(); }
            ),
            RegisteredComponents.end()
        );
		for (const TWeakObjectPtr<ULuaScriptComponent>& ComponentPtr : RegisteredComponents)
		{
            ULuaScriptComponent* Component = ComponentPtr.Get();
            if (!IsValid(Component)) continue;

			const FString& ScriptFile = Component->GetScriptFile();
			if (ScriptFile.empty()) continue;

			for (const FString& File : ChangedFiles)
			{
				if (File == ScriptFile)
				{
					Targets.insert(Component);
					break;
				}
			}
		}
	}

	for (ULuaScriptComponent* Component : Targets)
	{
		if (!Component) continue;

		UE_LOG("[LuaHotReload] Reloading: %s", Component->GetScriptFile().c_str());
		FNotificationManager::Get().AddNotification("Lua Reloaded: " + Component->GetScriptFile(), ENotificationType::Success, 3.0f);
		Component->ReloadScript();
	}

	// AnimInstance 측도 같은 패턴 — 매칭되는 ScriptFile 의 인스턴스 reload.
	TSet<ULuaAnimInstance*> AnimTargets;
	{
		std::lock_guard<std::mutex> Lock(ComponentMutex);
        RegisteredAnimInstances.erase(
            std::remove_if(
                RegisteredAnimInstances.begin(),
                RegisteredAnimInstances.end(),
                [](const TWeakObjectPtr<ULuaAnimInstance>& Instance) { return !Instance.IsValid(); }
            ),
            RegisteredAnimInstances.end()
        );
		for (const TWeakObjectPtr<ULuaAnimInstance>& InstPtr : RegisteredAnimInstances)
		{
            ULuaAnimInstance* Inst = InstPtr.Get();
            if (!IsValid(Inst)) continue;
			const FString& AnimScript = Inst->ScriptFile;
			if (AnimScript.empty()) continue;
			for (const FString& File : ChangedFiles)
			{
				if (File == AnimScript)
				{
					AnimTargets.insert(Inst);
					break;
				}
			}
		}
	}
	for (ULuaAnimInstance* Inst : AnimTargets)
	{
		if (!Inst) continue;
		UE_LOG("[LuaHotReload] Reloading Anim: %s", Inst->ScriptFile.c_str());
		FNotificationManager::Get().AddNotification("Anim Reloaded: " + Inst->ScriptFile, ENotificationType::Success, 3.0f);
		Inst->ReloadScript();
	}
}

void FLuaScriptManager::FireOnEscapePressed()
{
	if (!OnEscapePressedCallback.valid())
	{
		return;
	}
	sol::protected_function_result Result = OnEscapePressedCallback();
	if (!Result.valid())
	{
		sol::error Err = Result;
		UE_LOG("[Lua] OnEscapePressed callback error: %s", Err.what());
	}
}

void FLuaScriptManager::FireWorldReset()
{
	if (!Lua) return;

	// require 로 한 번 로드된 모듈 테이블은 package.loaded 에 캐시된다. 씬 전환 시에도
	// 살아남기 때문에, 이 두 모듈이 보유한 죽은-월드 참조를 비워준다.
	sol::table Loaded = (*Lua)["package"]["loaded"];
	if (!Loaded.valid()) return;

	// 1) CoroutineManager — 옛 액터의 lua 클로저가 캡처한 환경의 obj 가 dangling.
	//    Wait(30) 도중에 씬 전환되면 새 월드 Tick 에서 만료되면서 freed AActor* deref.
	if (sol::object Coro = Loaded["CoroutineManager"]; Coro.valid() && Coro.get_type() == sol::type::table)
	{
		Coro.as<sol::table>()["coroutines"] = Lua->create_table();
	}

	// 2) ObjRegistry — 액터 핸들 캐시. 새 월드의 BeginPlay 가 다시 등록해줄 때까지 nil 로.
	if (sol::object Reg = Loaded["ObjRegistry"]; Reg.valid() && Reg.get_type() == sol::type::table)
	{
		sol::table T = Reg.as<sol::table>();
		T["car"]        = sol::nil;
		T["carCamera"]  = sol::nil;
		T["carGas"]     = sol::nil;
		T["manObj"]     = sol::nil;
		T["manCamera"]  = sol::nil;
		T["gasNozzle"]  = sol::nil;
		T["carWasher"]  = sol::nil;
		T["dirtyCar"]   = sol::nil;
		T["policeCars"] = Lua->create_table();
	}
}

void FLuaScriptManager::Initialize()
{
	Lua = std::make_unique<sol::state>();
	Lua->open_libraries(sol::lib::base, sol::lib::package, sol::lib::math, sol::lib::string, sol::lib::table, sol::lib::coroutine);
	(*Lua)["package"]["path"] = FPaths::ToUtf8(FPaths::Combine(FPaths::ScriptDir(), L"?.lua").c_str());

	// 한글 경로 호환을 위해 require 의 파일 검색을 wide-aware 로 교체.
	// Lua 5.2+ 는 package.searchers, Lua 5.1/LuaJIT 은 package.loaders 를 사용한다.
	sol::table Package = (*Lua)["package"];
	sol::object Searchers = Package["searchers"];
	sol::table ModuleLoaders = Searchers.valid() && Searchers.get_type() == sol::type::table
		? Searchers.as<sol::table>()
		: Package["loaders"].get<sol::table>();
	ModuleLoaders[2] = [](sol::this_state ts, const std::string& ModName) -> sol::object
	{
		sol::state_view L(ts);
		const std::wstring WidePath = FPaths::Combine(FPaths::ScriptDir(), FPaths::ToWide(ModName + ".lua"));
		std::error_code EC;
		if (!std::filesystem::exists(WidePath, EC))
		{
			return sol::make_object(L, std::string("\n\tno file '") + FPaths::ToUtf8(WidePath) + "'");
		}

		FString Content;
		if (!ReadScriptFileContent(ModName + ".lua", Content))
		{
			return sol::make_object(L, std::string("\n\tcannot read '") + FPaths::ToUtf8(WidePath) + "'");
		}

		const FString ChunkName = FPaths::ToUtf8(WidePath);
		sol::load_result LR = L.load(Content, ChunkName);
		if (!LR.valid())
		{
			sol::error Err = LR;
			return sol::make_object(L, std::string("\n\t") + Err.what());
		}
		return LR.get<sol::object>();
	};

	// require 이름 정규화 — require("Manager.ScoreManager") 와 require("Manager/ScoreManager")
	// 를 같은 모듈로 취급한다. '.' 를 '/' 로 바꿔 한 가지 키로만 package.loaded 에 캐시되게 함
	// (키가 둘로 갈리면 같은 모듈 인스턴스가 2개 생겨 상태가 분열된다).
	// 핫리로드 무효화(GetModuleNameFromPath)도 같은 슬래시 키를 지운다.
	sol::protected_function_result WrapResult = Lua->safe_script(R"(
		local _require = require
		require = function(name)
			return _require((string.gsub(name, "[%.\\]", "/")))
		end
	)", sol::script_pass_on_error);
	if (!WrapResult.valid())
	{
		sol::error WrapErr = WrapResult;
		UE_LOG("[Lua] require wrapper error: %s", WrapErr.what());
	}

	RegisterBindings(*Lua);

	// 모든 sol::protected_function 호출의 default error handler 를 debug.traceback 으로 설정.
	// 이로써 lua 함수 호출 실패 시 protected_function_result 의 err.what() 에 lua 콜스택
	// (어느 파일, 어느 라인, 어느 함수) 이 포함되어 디버깅이 가능해진다. 미설정 시
	// sol2 는 단순 에러 메시지만 던져 lua 측 stack 정보가 사라진다.
	//sol::function Traceback = (*Lua)["debug"]["traceback"];
	//if (Traceback.valid())
	//{
	//	sol::protected_function::set_default_handler(Traceback);
	//}

	FWatchID WatchID = FDirectoryWatcher::Get().Watch(FPaths::ScriptDir(), "");
	if (WatchID != 0)
	{
		WatchSub = FDirectoryWatcher::Get().Subscribe(WatchID,
			[](const TSet<FString>& Files) { FLuaScriptManager::OnScriptsChanged(Files); });
	}
}

void FLuaScriptManager::Shutdown()
{
	if (WatchSub != 0)
	{
		FDirectoryWatcher::Get().Unsubscribe(WatchSub);
		WatchSub = 0;
	}

	TArray<TWeakObjectPtr<ULuaScriptComponent>> ComponentsToRelease;
	TArray<TWeakObjectPtr<ULuaAnimInstance>> AnimInstancesToRelease;
	{
		std::lock_guard<std::mutex> Lock(ComponentMutex);
		ComponentsToRelease = RegisteredComponents;
		AnimInstancesToRelease = RegisteredAnimInstances;
	}

	// lua_State 가 살아있는 동안 런타임 객체들이 들고 있는 sol reference 를 먼저 해제한다.
	// 이 작업을 Lua.reset() 뒤로 미루면 GC/dtor 단계에서 sol::basic_reference::~basic_reference 가
	// 닫힌 lua_State 에 luaL_unref 를 호출하며 lua51.dll 내부에서 크래시난다.
	for (const TWeakObjectPtr<ULuaScriptComponent>& ComponentPtr : ComponentsToRelease)
	{
		if (ULuaScriptComponent* Component = ComponentPtr.GetEvenIfPendingKill())
		{
			if (IsAliveObject(Component))
			{
				Component->ReleaseLuaRuntimeForShutdown();
			}
		}
	}
	for (const TWeakObjectPtr<ULuaAnimInstance>& InstancePtr : AnimInstancesToRelease)
	{
		if (ULuaAnimInstance* Instance = InstancePtr.GetEvenIfPendingKill())
		{
			if (IsAliveObject(Instance))
			{
				Instance->ReleaseLuaRuntimeForShutdown();
			}
		}
	}

	{
		std::lock_guard<std::mutex> Lock(ComponentMutex);
		RegisteredComponents.clear();
		RegisteredAnimInstances.clear();
	}

	// 등록된 Lua 콜백 (sol::protected_function 들) 을 lua_State 가 살아있는 동안 먼저 release.
	// static 멤버라 프로그램 종료 시점까지 살아있는데, 그때 destructor 가 luaL_unref 를
	// 호출하면서 이미 reset 된 lua_State 를 만지면 크래시. 빈 함수로 덮어써 deref 를 지금
	// (Lua 가 valid 한 동안) 일으킨다.
	OnEscapePressedCallback = sol::protected_function();
	GLuaReflectedEventOverrides.clear();

	Lua.reset();
}

FString FLuaScriptManager::ResolveScriptPath(const FString& ScriptFile)
{
	std::wstring FullPath = FPaths::Combine(FPaths::ScriptDir(), FPaths::ToWide(ScriptFile));
	return FPaths::ToUtf8(FullPath);
}

bool FLuaScriptManager::ReadScriptFileContent(const FString& ScriptFile, FString& OutContent)
{
	const std::wstring WidePath = FPaths::Combine(FPaths::ScriptDir(), FPaths::ToWide(ScriptFile));
	std::ifstream File(WidePath.c_str(), std::ios::binary);
	if (!File.is_open())
	{
		return false;
	}
	std::ostringstream SS;
	SS << File.rdbuf();
	OutContent = SS.str();
	return true;
}

bool FLuaScriptManager::OpenOrCreateScript(const FString& ScriptFile)
{
	std::wstring FullPath = FPaths::Combine(FPaths::ScriptDir(), FPaths::ToWide(ScriptFile));
	if (!std::filesystem::exists(FullPath))
	{
		FPaths::CreateDir(FPaths::ScriptDir());

		const std::wstring TemplatePath = FPaths::Combine(FPaths::ScriptDir(), L"template.lua");
		std::error_code Error;
		if (std::filesystem::exists(TemplatePath))
		{
			std::filesystem::copy_file(TemplatePath, FullPath, std::filesystem::copy_options::none, Error);
			if (Error)
			{
				UE_LOG("Failed to copy Lua script template: %s", Error.message().c_str());
			}
		}

		if (!std::filesystem::exists(FullPath))
		{
			std::ofstream Out(FullPath);
			if (!Out)
			{
				return false;
			}
		}
	}

	HINSTANCE HInst = ShellExecuteW(nullptr, L"open", FullPath.c_str(), nullptr, nullptr, SW_SHOWNORMAL);

	if ((INT_PTR)HInst <= 32)
	{
		return false;
	}

	return true;
}

namespace
{
	const char* LuaPropertyTypeName(EPropertyType Type)
	{
		switch (Type)
		{
		case EPropertyType::Bool:
			return "Bool";
		case EPropertyType::ByteBool:
			return "ByteBool";
		case EPropertyType::Int:
			return "Int";
		case EPropertyType::Float:
			return "Float";
		case EPropertyType::Vec3:
			return "Vec3";
		case EPropertyType::Vec4:
			return "Vec4";
		case EPropertyType::Rotator:
			return "Rotator";
		case EPropertyType::String:
			return "String";
		case EPropertyType::Name:
			return "Name";
		case EPropertyType::ObjectRef:
			return "ObjectRef";
		case EPropertyType::Color4:
			return "Color4";
		case EPropertyType::ClassRef:
			return "ClassRef";
		case EPropertyType::Enum:
			return "Enum";
		case EPropertyType::Struct:
			return "Struct";
		case EPropertyType::SoftObjectRef:
			return "SoftObjectRef";
		case EPropertyType::Array:
			return "Array";
		default:
			return "Unknown";
		}
	}

	bool LuaReadNumber(const sol::object& Object, double& OutValue)
	{
		if (!Object.valid() || Object == sol::nil || Object.get_type() != sol::type::number)
		{
			return false;
		}
		OutValue = Object.as<double>();
		return true;
	}

	bool LuaReadFloatField(const sol::table& Table, const char* Name, int Index, float& OutValue)
	{
		double      Number = 0.0;
		sol::object Named  = Table[Name];
		if (LuaReadNumber(Named, Number))
		{
			OutValue = static_cast<float>(Number);
			return true;
		}
		sol::object Indexed = Table[Index];
		if (LuaReadNumber(Indexed, Number))
		{
			OutValue = static_cast<float>(Number);
			return true;
		}
		return false;
	}

	bool LuaObjectToVector(const sol::object& Object, FVector& OutVector)
	{
		if (!Object.valid() || Object == sol::nil)
		{
			return false;
		}
		if (Object.is<FVector>())
		{
			OutVector = Object.as<FVector>();
			return true;
		}
		if (Object.get_type() != sol::type::table)
		{
			return false;
		}
		sol::table Table = Object.as<sol::table>();
		float      X     = 0.0f;
		float      Y     = 0.0f;
		float      Z     = 0.0f;
		LuaReadFloatField(Table, "X", 1, X);
		LuaReadFloatField(Table, "Y", 2, Y);
		LuaReadFloatField(Table, "Z", 3, Z);
		OutVector = FVector(X, Y, Z);
		return true;
	}

	bool LuaObjectToVector4(const sol::object& Object, FVector4& OutVector)
	{
		if (!Object.valid() || Object == sol::nil)
		{
			return false;
		}
		if (Object.is<FVector4>())
		{
			OutVector = Object.as<FVector4>();
			return true;
		}
		if (Object.get_type() != sol::type::table)
		{
			return false;
		}
		sol::table Table = Object.as<sol::table>();
		float      X     = 0.0f;
		float      Y     = 0.0f;
		float      Z     = 0.0f;
		float      W     = 0.0f;
		LuaReadFloatField(Table, "X", 1, X);
		LuaReadFloatField(Table, "Y", 2, Y);
		LuaReadFloatField(Table, "Z", 3, Z);
		if (!LuaReadFloatField(Table, "W", 4, W))
		{
			LuaReadFloatField(Table, "A", 4, W);
		}
		OutVector = FVector4(X, Y, Z, W);
		return true;
	}

	sol::table LuaVector4ToTable(sol::this_state State, const FVector4& Value)
	{
		sol::state_view Lua(State);
		sol::table      Table = Lua.create_table();
		Table["X"]            = Value.X;
		Table["Y"]            = Value.Y;
		Table["Z"]            = Value.Z;
		Table["W"]            = Value.W;
		Table["R"]            = Value.R;
		Table["G"]            = Value.G;
		Table["B"]            = Value.B;
		Table["A"]            = Value.A;
		return Table;
	}

	sol::object LuaValueToObject(sol::this_state State, const FProperty& Property, void* ValuePtr);
	bool        LuaObjectToValue(
		const FProperty&   Property,
		void*              ValuePtr,
		const sol::object& Object,
		FString*           OutError = nullptr
		);

	bool LuaObjectToEnumValue(const FEnum* EnumType, const sol::object& Object, int64& OutValue)
	{
		if (!Object.valid() || Object == sol::nil)
		{
			return false;
		}
		if (Object.get_type() == sol::type::number)
		{
			OutValue = static_cast<int64>(Object.as<double>());
			return true;
		}
		if (Object.get_type() == sol::type::string)
		{
			FString Name = Object.as<FString>();
			if (!EnumType)
			{
				return false;
			}
			for (uint32 Index = 0; Index < EnumType->GetCount(); ++Index)
			{
				const char* EntryName = EnumType->GetNameAt(Index);
				if (EntryName && Name == EntryName)
				{
					OutValue = EnumType->GetValueAt(Index);
					return true;
				}
			}
		}
		return false;
	}

	sol::object LuaStructToTable(sol::this_state State, const FStructProperty& Property, void* ValuePtr)
	{
		sol::state_view Lua(State);
		sol::table      Table      = Lua.create_table();
		UStruct*        StructType = Property.GetStructType();
		if (!StructType || !ValuePtr)
		{
			return sol::make_object(Lua, Table);
		}
		TArray<const FProperty*> Children;
		StructType->GetPropertyRefs(Children);
		for (const FProperty* Child : Children)
		{
			if (!Child || !Child->Name)
			{
				continue;
			}
			Table[Child->Name] = LuaValueToObject(State, *Child, Child->GetValuePtrFor(ValuePtr));
		}
		return sol::make_object(Lua, Table);
	}

	bool LuaTableToStruct(const FStructProperty& Property, void* ValuePtr, const sol::object& Object, FString* OutError)
	{
		if (!ValuePtr)
		{
			if (OutError) *OutError = "null struct storage";
			return false;
		}
		if (Object.get_type() != sol::type::table)
		{
			if (OutError) *OutError = "expected table for struct";
			return false;
		}
		UStruct* StructType = Property.GetStructType();
		if (!StructType)
		{
			if (OutError) *OutError = "struct type is not registered";
			return false;
		}
		sol::table               Table = Object.as<sol::table>();
		TArray<const FProperty*> Children;
		StructType->GetPropertyRefs(Children);
		for (const FProperty* Child : Children)
		{
			if (!Child || !Child->Name)
			{
				continue;
			}
			sol::object Field = Table[Child->Name];
			if (!Field.valid() || Field == sol::nil)
			{
				continue;
			}
			if (!LuaObjectToValue(*Child, Child->GetValuePtrFor(ValuePtr), Field, OutError))
			{
				return false;
			}
		}
		return true;
	}

	sol::object LuaArrayToTable(sol::this_state State, const FArrayProperty& Property, void* ValuePtr)
	{
		sol::state_view                  Lua(State);
		sol::table                       Table = Lua.create_table();
		const FArrayProperty::FArrayOps* Ops   = Property.GetArrayOps();
		const FProperty*                 Inner = Property.GetInnerProperty();
		if (!ValuePtr || !Ops || !Ops->GetNum || !Ops->GetElementPtr || !Inner)
		{
			return sol::make_object(Lua, Table);
		}
		const size_t Count = Ops->GetNum(ValuePtr);
		for (size_t Index = 0; Index < Count; ++Index)
		{
			Table[static_cast<int>(Index + 1)] = LuaValueToObject(State, *Inner, Ops->GetElementPtr(ValuePtr, Index));
		}
		return sol::make_object(Lua, Table);
	}

	bool LuaTableToArray(const FArrayProperty& Property, void* ValuePtr, const sol::object& Object, FString* OutError)
	{
		if (Object.get_type() != sol::type::table)
		{
			if (OutError) *OutError = "expected table for array";
			return false;
		}
		const FArrayProperty::FArrayOps* Ops   = Property.GetArrayOps();
		const FProperty*                 Inner = Property.GetInnerProperty();
		if (!ValuePtr || !Ops || !Ops->Resize || !Ops->GetElementPtr || !Inner)
		{
			if (OutError) *OutError = "array reflection ops are missing";
			return false;
		}
		sol::table   Table = Object.as<sol::table>();
		const size_t Count = static_cast<size_t>(Table.size());
		Ops->Resize(ValuePtr, Count);
		for (size_t Index = 0; Index < Count; ++Index)
		{
			sol::object Element = Table[static_cast<int>(Index + 1)];
			if (!LuaObjectToValue(*Inner, Ops->GetElementPtr(ValuePtr, Index), Element, OutError))
			{
				return false;
			}
		}
		return true;
	}

	sol::object LuaValueToObject(sol::this_state State, const FProperty& Property, void* ValuePtr)
	{
		sol::state_view Lua(State);
		if (!ValuePtr)
		{
			return sol::make_object(Lua, sol::nil);
		}

		switch (Property.GetType())
		{
		case EPropertyType::Bool:
			return sol::make_object(Lua, *static_cast<bool*>(ValuePtr));
		case EPropertyType::ByteBool:
			return sol::make_object(Lua, *static_cast<uint8*>(ValuePtr) != 0);
		case EPropertyType::Int:
			return sol::make_object(Lua, *static_cast<int32*>(ValuePtr));
		case EPropertyType::Float:
			return sol::make_object(Lua, *static_cast<float*>(ValuePtr));
		case EPropertyType::String:
			return sol::make_object(Lua, *static_cast<FString*>(ValuePtr));
		case EPropertyType::Name:
			return sol::make_object(Lua, static_cast<FName*>(ValuePtr)->ToString());
		case EPropertyType::Vec3:
			return sol::make_object(Lua, *static_cast<FVector*>(ValuePtr));
		case EPropertyType::Rotator:
			return sol::make_object(Lua, static_cast<FRotator*>(ValuePtr)->ToVector());
		case EPropertyType::Vec4:
		case EPropertyType::Color4:
			return sol::make_object(Lua, LuaVector4ToTable(State, *static_cast<FVector4*>(ValuePtr)));
		case EPropertyType::Enum:
		{
			const FEnum* EnumType  = Property.GetEnumType();
			int64        EnumValue = 0;
			std::memcpy(&EnumValue, ValuePtr, std::min<size_t>(Property.Size, sizeof(EnumValue)));
			if (EnumType)
			{
				const char* Name = EnumType->GetNameByValue(EnumValue);
				if (Name && std::strcmp(Name, "Unknown") != 0)
				{
					return sol::make_object(Lua, FString(Name));
				}
			}
			return sol::make_object(Lua, EnumValue);
		}
		case EPropertyType::ObjectRef:
		{
			const FObjectProperty* ObjectProperty = Property.AsObjectProperty();
			return sol::make_object(
				Lua,
				ObjectProperty ? ObjectProperty->GetObjectValueFromValuePtr(ValuePtr) : nullptr
			);
		}
		case EPropertyType::ClassRef:
		{
			const FClassProperty* ClassProperty = Property.AsClassProperty();
			UClass*               Class = ClassProperty ? ClassProperty->GetClassValueFromValuePtr(ValuePtr) : nullptr;
			return Class ? sol::make_object(Lua, FString(Class->GetName())) : sol::make_object(Lua, sol::nil);
		}
		case EPropertyType::SoftObjectRef:
		{
			const FSoftObjectProperty* SoftProperty = Property.AsSoftObjectProperty();
			return SoftProperty ? sol::make_object(Lua, SoftProperty->GetPathFromValuePtr(ValuePtr))
			: sol::make_object(Lua, sol::nil);
		}
		case EPropertyType::Struct:
		{
			const FStructProperty* StructProperty = Property.AsStructProperty();
			return StructProperty ? LuaStructToTable(State, *StructProperty, ValuePtr)
			: sol::make_object(Lua, sol::nil);
		}
		case EPropertyType::Array:
		{
			const FArrayProperty* ArrayProperty = Property.AsArrayProperty();
			return ArrayProperty ? LuaArrayToTable(State, *ArrayProperty, ValuePtr) : sol::make_object(Lua, sol::nil);
		}
		default:
			return sol::make_object(Lua, sol::nil);
		}
	}

	bool LuaObjectToValue(const FProperty& Property, void* ValuePtr, const sol::object& Object, FString* OutError)
	{
		if (!ValuePtr)
		{
			if (OutError) *OutError = "null value storage";
			return false;
		}
		if (!Object.valid() || Object == sol::nil)
		{
			if (Property.GetType() == EPropertyType::ObjectRef)
			{
				if (const FObjectProperty* ObjectProperty = Property.AsObjectProperty())
				{
					ObjectProperty->SetObjectValueFromValuePtr(ValuePtr, nullptr);
					return true;
				}
			}
			if (Property.GetType() == EPropertyType::ClassRef)
			{
				if (const FClassProperty* ClassProperty = Property.AsClassProperty())
				{
					ClassProperty->SetClassValueFromValuePtr(ValuePtr, nullptr);
					return true;
				}
			}
			if (OutError) *OutError = FString("nil is not assignable to ") + LuaPropertyTypeName(Property.GetType());
			return false;
		}

		switch (Property.GetType())
		{
		case EPropertyType::Bool:
			if (!Object.is<bool>())
			{
				if (OutError) *OutError = "expected bool";
				return false;
			}
			*static_cast<bool*>(ValuePtr) = Object.as<bool>();
			return true;
		case EPropertyType::ByteBool:
			if (!Object.is<bool>())
			{
				if (OutError) *OutError = "expected bool";
				return false;
			}
			*static_cast<uint8*>(ValuePtr) = Object.as<bool>() ? 1 : 0;
			return true;
		case EPropertyType::Int:
			if (Object.get_type() != sol::type::number)
			{
				if (OutError) *OutError = "expected number";
				return false;
			}
			*static_cast<int32*>(ValuePtr) = static_cast<int32>(Object.as<double>());
			return true;
		case EPropertyType::Float:
			if (Object.get_type() != sol::type::number)
			{
				if (OutError) *OutError = "expected number";
				return false;
			}
			*static_cast<float*>(ValuePtr) = static_cast<float>(Object.as<double>());
			return true;
		case EPropertyType::String:
			if (Object.get_type() != sol::type::string)
			{
				if (OutError) *OutError = "expected string";
				return false;
			}
			*static_cast<FString*>(ValuePtr) = Object.as<FString>();
			return true;
		case EPropertyType::Name:
			if (Object.get_type() != sol::type::string)
			{
				if (OutError) *OutError = "expected string";
				return false;
			}
			*static_cast<FName*>(ValuePtr) = FName(Object.as<FString>());
			return true;
		case EPropertyType::Vec3:
		{
			FVector Vector;
			if (!LuaObjectToVector(Object, Vector))
			{
				if (OutError) *OutError = "expected Vector or {X,Y,Z}";
				return false;
			}
			*static_cast<FVector*>(ValuePtr) = Vector;
			return true;
		}
		case EPropertyType::Rotator:
		{
			FVector Vector;
			if (!LuaObjectToVector(Object, Vector))
			{
				if (OutError) *OutError = "expected Vector or {X,Y,Z}";
				return false;
			}
			*static_cast<FRotator*>(ValuePtr) = FRotator(Vector);
			return true;
		}
		case EPropertyType::Vec4:
		case EPropertyType::Color4:
		{
			FVector4 Vector;
			if (!LuaObjectToVector4(Object, Vector))
			{
				if (OutError) *OutError = "expected {X,Y,Z,W}";
				return false;
			}
			*static_cast<FVector4*>(ValuePtr) = Vector;
			return true;
		}
		case EPropertyType::Enum:
		{
			int64 EnumValue = 0;
			if (!LuaObjectToEnumValue(Property.GetEnumType(), Object, EnumValue))
			{
				if (OutError) *OutError = "expected enum name or value";
				return false;
			}
			std::memcpy(ValuePtr, &EnumValue, std::min<size_t>(Property.Size, sizeof(EnumValue)));
			return true;
		}
		case EPropertyType::ObjectRef:
		{
			if (!Object.is<UObject*>())
			{
				if (OutError) *OutError = "expected Object";
				return false;
			}
			UObject*               SourceObject   = Object.as<UObject*>();
			const FObjectProperty* ObjectProperty = Property.AsObjectProperty();
			if (!ObjectProperty)
			{
				if (OutError) *OutError = "object property ops missing";
				return false;
			}
			if (UClass* AllowedClass = ObjectProperty->GetAllowedClassType())
			{
				if (SourceObject && !SourceObject->GetClass()->IsA(AllowedClass))
				{
					if (OutError) *OutError = "object class is not assignable to parameter";
					return false;
				}
			}
			ObjectProperty->SetObjectValueFromValuePtr(ValuePtr, SourceObject);
			return true;
		}
		case EPropertyType::ClassRef:
		{
			const FClassProperty* ClassProperty = Property.AsClassProperty();
			if (!ClassProperty)
			{
				if (OutError) *OutError = "class property ops missing";
				return false;
			}
			if (Object.get_type() != sol::type::string)
			{
				if (OutError) *OutError = "expected class name string";
				return false;
			}
			UClass* Class = UClass::FindByName(Object.as<FString>().c_str());
			if (!Class)
			{
				if (OutError) *OutError = "class was not found";
				return false;
			}
			if (UClass* AllowedClass = ClassProperty->GetAllowedClassType())
			{
				if (!Class->IsA(AllowedClass))
				{
					if (OutError) *OutError = "class is not assignable to parameter";
					return false;
				}
			}
			ClassProperty->SetClassValueFromValuePtr(ValuePtr, Class);
			return true;
		}
		case EPropertyType::SoftObjectRef:
		{
			const FSoftObjectProperty* SoftProperty = Property.AsSoftObjectProperty();
			if (!SoftProperty)
			{
				if (OutError) *OutError = "soft object property ops missing";
				return false;
			}
			if (Object.get_type() != sol::type::string)
			{
				if (OutError) *OutError = "expected asset path string";
				return false;
			}
			SoftProperty->SetPathFromValuePtr(ValuePtr, Object.as<FString>());
			return true;
		}
		case EPropertyType::Struct:
		{
			const FStructProperty* StructProperty = Property.AsStructProperty();
			return StructProperty ? LuaTableToStruct(*StructProperty, ValuePtr, Object, OutError) : false;
		}
		case EPropertyType::Array:
		{
			const FArrayProperty* ArrayProperty = Property.AsArrayProperty();
			return ArrayProperty ? LuaTableToArray(*ArrayProperty, ValuePtr, Object, OutError) : false;
		}
		default:
			if (OutError) *OutError = "unsupported reflected property type for Lua";
			return false;
		}
	}

	bool LuaCanSkipMissingArgument(const FProperty& Parameter)
	{
		if ((Parameter.Flags & PF_OutParm) != 0 && (Parameter.Flags & PF_ConstParm) == 0)
		{
			return true;
		}
		return Parameter.Metadata.find("defaultvalue") != Parameter.Metadata.end();
	}

	bool LuaTryPrepareFunctionCall(const FFunction& Function, sol::variadic_args Args, void* Storage, FString& OutError)
	{
		const TArray<FProperty*>& Parameters  = Function.GetParameters();
		const size_t              LuaArgCount = Args.size();
		size_t                    LuaArgIndex = 0;

		for (const FProperty* Parameter : Parameters)
		{
			if (!Parameter)
			{
				continue;
			}

			const bool bOutOnly = (Parameter->Flags & PF_OutParm) != 0 && (Parameter->Flags & PF_ConstParm) == 0;
			if (bOutOnly && LuaArgIndex >= LuaArgCount)
			{
				continue;
			}

			if (LuaArgIndex >= LuaArgCount)
			{
				if (LuaCanSkipMissingArgument(*Parameter))
				{
					continue;
				}
				OutError = FString("missing Lua argument for parameter '") + (Parameter->Name ? Parameter->Name : "") +
				"'";
				return false;
			}

			sol::object Arg = Args[static_cast<int>(LuaArgIndex)];
			FString     ConvertError;
			if (!LuaObjectToValue(*Parameter, Parameter->GetValuePtrFor(Storage), Arg, &ConvertError))
			{
				OutError = FString("parameter '") + (Parameter->Name ? Parameter->Name : "") + "': " + ConvertError;
				return false;
			}
			++LuaArgIndex;
		}

		if (LuaArgIndex < LuaArgCount)
		{
			OutError = "too many Lua arguments";
			return false;
		}
		return true;
	}

	sol::object LuaCollectFunctionResult(sol::this_state State, const FFunction& Function, void* Storage)
	{
		sol::state_view          Lua(State);
		const FProperty*         ReturnProperty = Function.GetReturnProperty();
		TArray<const FProperty*> OutParameters;
		for (const FProperty* Parameter : Function.GetParameters())
		{
			if (Parameter && (Parameter->Flags & PF_OutParm) != 0 && (Parameter->Flags & PF_ConstParm) == 0)
			{
				OutParameters.push_back(Parameter);
			}
		}

		if (!ReturnProperty && OutParameters.empty())
		{
			return sol::make_object(Lua, true);
		}
		if (ReturnProperty && OutParameters.empty())
		{
			return LuaValueToObject(State, *ReturnProperty, ReturnProperty->GetValuePtrFor(Storage));
		}

		sol::table Result = Lua.create_table();
		if (ReturnProperty)
		{
			Result["ReturnValue"] = LuaValueToObject(State, *ReturnProperty, ReturnProperty->GetValuePtrFor(Storage));
		}
		for (const FProperty* Parameter : OutParameters)
		{
			Result[(Parameter->Name ? Parameter->Name : "")] = LuaValueToObject(
				State,
				*Parameter,
				Parameter->GetValuePtrFor(Storage)
			);
		}
		return sol::make_object(Lua, Result);
	}

	const FFunction* LuaFindFunctionByNameOrSignature(UStruct* TargetStruct, const FString& FunctionNameOrSignature)
	{
		if (!TargetStruct || FunctionNameOrSignature.empty())
		{
			return nullptr;
		}

		if (FunctionNameOrSignature.find('(') != FString::npos)
		{
			return TargetStruct->FindFunctionBySignature(FunctionNameOrSignature.c_str(), true);
		}

		return TargetStruct->FindFunctionByName(FunctionNameOrSignature.c_str(), true);
	}

	bool LuaCopyFunctionResultFromObject(
		sol::this_state    State,
		const FFunction&   Function,
		void*              Storage,
		const sol::object& ResultObject,
		FString&           OutError
		)
	{
		(void)State;
		const bool bResultIsTable = ResultObject.valid() && ResultObject.get_type() == sol::type::table;

		if (const FProperty* ReturnProperty = Function.GetReturnProperty())
		{
			sol::object ReturnValue = bResultIsTable ? ResultObject.as<sol::table>()["ReturnValue"].get<sol::object>()
			: ResultObject;
			if (ReturnValue.valid() && ReturnValue != sol::nil)
			{
				FString ConvertError;
				if (!LuaObjectToValue(
					*ReturnProperty,
					ReturnProperty->GetValuePtrFor(Storage),
					ReturnValue,
					&ConvertError
				))
				{
					OutError = FString("return value: ") + ConvertError;
					return false;
				}
			}
		}

		if (bResultIsTable)
		{
			sol::table ResultTable = ResultObject.as<sol::table>();
			for (const FProperty* Parameter : Function.GetParameters())
			{
				if (!Parameter || (Parameter->Flags & PF_OutParm) == 0 || (Parameter->Flags & PF_ConstParm) != 0)
				{
					continue;
				}

				sol::object OutValue = ResultTable[Parameter->Name ? Parameter->Name : ""].get<sol::object>();
				if (!OutValue.valid() || OutValue == sol::nil)
				{
					continue;
				}

				FString ConvertError;
				if (!LuaObjectToValue(*Parameter, Parameter->GetValuePtrFor(Storage), OutValue, &ConvertError))
				{
					OutError = FString("out parameter '") + (Parameter->Name ? Parameter->Name : "") + "': " +
					ConvertError;
					return false;
				}
			}
		}

		return true;
	}

	enum class ELuaEventOverrideResult : uint8
	{
		NotBound,
		Invoked,
		Failed,
	};

	ELuaEventOverrideResult LuaTryInvokeReflectedEventOverride(
		sol::this_state  State,
		UObject*         Instance,
		const FFunction& Function,
		void*            Storage,
		FString&         OutError
		)
	{
		if (!Instance || !Function.HasAnyFunctionFlags(FUNC_Event))
		{
			return ELuaEventOverrideResult::NotBound;
		}

		CompactLuaReflectedEventOverrides();
		auto It = GLuaReflectedEventOverrides.find(MakeLuaReflectedEventKey(Instance, Function));
		if (It == GLuaReflectedEventOverrides.end() || It->second.Target.Get() != Instance || !It->second.Callback.valid())
		{
			return ELuaEventOverrideResult::NotBound;
		}

		TArray<sol::object> LuaArgs;
		for (const FProperty* Parameter : Function.GetParameters())
		{
			if (!Parameter)
			{
				continue;
			}
			const bool bOutOnly = (Parameter->Flags & PF_OutParm) != 0 && (Parameter->Flags & PF_ConstParm) == 0;
			if (bOutOnly)
			{
				continue;
			}
			LuaArgs.push_back(LuaValueToObject(State, *Parameter, Parameter->GetValuePtrFor(Storage)));
		}

		sol::protected_function_result Result = It->second.Callback(sol::as_args(LuaArgs));
		if (!Result.valid())
		{
			sol::error Err = Result;
			OutError       = Err.what();
			return ELuaEventOverrideResult::Failed;
		}

		sol::object ResultObject = Result.get<sol::object>();
		if (!LuaCopyFunctionResultFromObject(State, Function, Storage, ResultObject, OutError))
		{
			return ELuaEventOverrideResult::Failed;
		}

		return ELuaEventOverrideResult::Invoked;
	}

	sol::object LuaInvokeReflectedFunctionBySignature(
		sol::this_state    State,
		UObject*           Instance,
		UClass*            StaticClass,
		const FString&     Signature,
		sol::variadic_args Args
		)
	{
		sol::state_view Lua(State);
		UStruct*        TargetStruct = Instance ? Instance->GetClass() : StaticClass;
		if (!TargetStruct)
		{
			UE_LOG("[LuaReflection] Reflection.CallSignature failed: target has no reflected class");
			return sol::make_object(Lua, sol::nil);
		}

		const FFunction* Function = TargetStruct->FindFunctionBySignature(Signature.c_str(), true);
		if (!Function)
		{
			UE_LOG("[LuaReflection] Reflection.CallSignature failed: function not found: %s", Signature.c_str());
			return sol::make_object(Lua, sol::nil);
		}
		if (!Instance && !Function->IsStatic())
		{
			UE_LOG(
				"[LuaReflection] Reflection.CallSignature failed: non-static function requires object instance: %s",
				Signature.c_str()
			);
			return sol::make_object(Lua, sol::nil);
		}

		void* Storage = Function->CreateParameterStorage();
		if (!Storage)
		{
			UE_LOG(
				"[LuaReflection] Reflection.CallSignature failed: failed to allocate parameter storage: %s",
				Signature.c_str()
			);
			return sol::make_object(Lua, sol::nil);
		}

		FString PrepareError;
		if (!LuaTryPrepareFunctionCall(*Function, Args, Storage, PrepareError))
		{
			Function->DestroyParameterStorage(Storage);
			UE_LOG("[LuaReflection] Reflection.CallSignature failed: %s: %s", Signature.c_str(), PrepareError.c_str());
			return sol::make_object(Lua, sol::nil);
		}

		FString                       EventError;
		const ELuaEventOverrideResult EventResult = LuaTryInvokeReflectedEventOverride(
			State,
			Instance,
			*Function,
			Storage,
			EventError
		);
		if (EventResult == ELuaEventOverrideResult::Failed)
		{
			Function->DestroyParameterStorage(Storage);
			UE_LOG(
				"[LuaReflection] Reflection.CallSignature event override failed: %s: %s",
				Signature.c_str(),
				EventError.c_str()
			);
			return sol::make_object(Lua, sol::nil);
		}

		if (EventResult == ELuaEventOverrideResult::NotBound)
		{
			const bool bInvoked = Function->Invoke(Instance, Storage, nullptr);
			if (!bInvoked)
			{
				Function->DestroyParameterStorage(Storage);
				UE_LOG("[LuaReflection] Reflection.CallSignature failed: native invoke failed: %s", Signature.c_str());
				return sol::make_object(Lua, sol::nil);
			}
		}

		sol::object Result = LuaCollectFunctionResult(State, *Function, Storage);
		Function->DestroyParameterStorage(Storage);
		return Result;
	}

	bool LuaBindReflectedEventOverride(
		UObject*                Object,
		const FString&          FunctionNameOrSignature,
		sol::protected_function Callback
		)
	{
		if (!Object || !Object->GetClass() || !Callback.valid())
		{
			return false;
		}

		const FFunction* Function = LuaFindFunctionByNameOrSignature(Object->GetClass(), FunctionNameOrSignature);
		if (!Function || !Function->HasAnyFunctionFlags(FUNC_Event))
		{
			UE_LOG("[LuaReflection] BindEvent failed: reflected event not found: %s", FunctionNameOrSignature.c_str());
			return false;
		}

		FLuaReflectedEventOverride Override;
		Override.Target = Object;
		Override.Callback = std::move(Callback);
		GLuaReflectedEventOverrides[MakeLuaReflectedEventKey(Object, *Function)] = std::move(Override);
		CompactLuaReflectedEventOverrides();
		return true;
	}

	bool LuaUnbindReflectedEventOverride(UObject* Object, const FString& FunctionNameOrSignature)
	{
		if (!Object || !Object->GetClass())
		{
			return false;
		}

		const FFunction* Function = LuaFindFunctionByNameOrSignature(Object->GetClass(), FunctionNameOrSignature);
		if (!Function)
		{
			return false;
		}

		return GLuaReflectedEventOverrides.erase(MakeLuaReflectedEventKey(Object, *Function)) > 0;
	}

	bool LuaHasReflectedEventOverride(UObject* Object, const FString& FunctionNameOrSignature)
	{
		if (!Object || !Object->GetClass())
		{
			return false;
		}

		const FFunction* Function = LuaFindFunctionByNameOrSignature(Object->GetClass(), FunctionNameOrSignature);
		if (!Function)
		{
			return false;
		}

		CompactLuaReflectedEventOverrides();
		auto It = GLuaReflectedEventOverrides.find(MakeLuaReflectedEventKey(Object, *Function));
		return It != GLuaReflectedEventOverrides.end() && It->second.Target.Get() == Object && It->second.Callback.valid();
	}

	sol::object LuaInvokeReflectedFunction(
		sol::this_state    State,
		UObject*           Instance,
		UClass*            StaticClass,
		const FString&     FunctionName,
		sol::variadic_args Args
		)
	{
		sol::state_view Lua(State);
		UStruct*        TargetStruct = Instance ? Instance->GetClass() : StaticClass;
		if (!TargetStruct)
		{
			UE_LOG("[LuaReflection] Reflection.Call failed: target has no reflected class");
			return sol::make_object(Lua, sol::nil);
		}

		TArray<const FFunction*> Functions;
		TargetStruct->FindFunctionsByName(FunctionName.c_str(), Functions, true);
		if (Functions.empty())
		{
			UE_LOG("[LuaReflection] Reflection.Call failed: function not found: %s", FunctionName.c_str());
			return sol::make_object(Lua, sol::nil);
		}

		FString LastError;
		for (const FFunction* Function : Functions)
		{
			if (!Function)
			{
				continue;
			}
			if (!Instance && !Function->IsStatic())
			{
				LastError = "non-static function requires object instance";
				continue;
			}

			void* Storage = Function->CreateParameterStorage();
			if (!Storage)
			{
				LastError = "failed to allocate parameter storage";
				continue;
			}

			FString PrepareError;
			if (!LuaTryPrepareFunctionCall(*Function, Args, Storage, PrepareError))
			{
				Function->DestroyParameterStorage(Storage);
				LastError = PrepareError;
				continue;
			}

			FString                       EventError;
			const ELuaEventOverrideResult EventResult = LuaTryInvokeReflectedEventOverride(
				State,
				Instance,
				*Function,
				Storage,
				EventError
			);
			if (EventResult == ELuaEventOverrideResult::Failed)
			{
				Function->DestroyParameterStorage(Storage);
				LastError = FString("event override failed: ") + EventError;
				continue;
			}

			if (EventResult == ELuaEventOverrideResult::NotBound)
			{
				const bool bInvoked = Function->Invoke(Instance, Storage, nullptr);
				if (!bInvoked)
				{
					Function->DestroyParameterStorage(Storage);
					LastError = "native invoke failed";
					continue;
				}
			}

			sol::object Result = LuaCollectFunctionResult(State, *Function, Storage);
			Function->DestroyParameterStorage(Storage);
			return Result;
		}

		UE_LOG(
			"[LuaReflection] Reflection.Call failed: no overload matched for %s: %s",
			FunctionName.c_str(),
			LastError.c_str()
		);
		return sol::make_object(Lua, sol::nil);
	}

	const FProperty* LuaFindProperty(UObject* Object, const FString& PropertyName)
	{
		if (!Object || !Object->GetClass())
		{
			return nullptr;
		}
		TArray<const FProperty*> Properties;
		Object->GetClass()->GetPropertyRefs(Properties);
		for (const FProperty* Property : Properties)
		{
			if (Property && Property->Name && PropertyName == Property->Name)
			{
				return Property;
			}
		}
		return nullptr;
	}

	sol::object LuaGetReflectedProperty(sol::this_state State, UObject* Object, const FString& PropertyName)
	{
		sol::state_view  Lua(State);
		const FProperty* Property = LuaFindProperty(Object, PropertyName);
		if (!Property)
		{
			return sol::make_object(Lua, sol::nil);
		}
		return LuaValueToObject(State, *Property, Property->GetValuePtrFor(Object));
	}

	bool LuaSetReflectedProperty(UObject* Object, const FString& PropertyName, sol::object Value)
	{
		const FProperty* Property = LuaFindProperty(Object, PropertyName);
		if (!Object || !Property)
		{
			return false;
		}
		FString    Error;
		const bool bOk = LuaObjectToValue(*Property, Property->GetValuePtrFor(Object), Value, &Error);
		if (!bOk)
		{
			UE_LOG(
				"[LuaReflection] SetProperty failed: %s.%s: %s",
				Object->GetClass()->GetName(),
				PropertyName.c_str(),
				Error.c_str()
			);
		}
		return bOk;
	}

	sol::table LuaDescribeProperty(sol::this_state State, const FProperty& Property)
	{
		sol::state_view Lua(State);
		sol::table      Desc = Lua.create_table();
		Desc["Name"]         = Property.Name ? Property.Name : "";
		Desc["DisplayName"]  = Property.DisplayName ? Property.DisplayName : (Property.Name ? Property.Name : "");
		Desc["Category"]     = Property.Category ? Property.Category : "";
		Desc["Type"]         = LuaPropertyTypeName(Property.GetType());
		Desc["Flags"]        = Property.Flags;
		Desc["OwnerClass"]   = Property.OwnerClassName ? Property.OwnerClassName : "";
		if (const FArrayProperty* ArrayProperty = Property.AsArrayProperty())
		{
			Desc["ElementType"] = LuaPropertyTypeName(ArrayProperty->GetElementType());
		}
		if (const FEnum* EnumType = Property.GetEnumType())
		{
			Desc["Enum"] = EnumType->GetName();
		}
		if (UStruct* StructType = Property.GetStructType())
		{
			Desc["Struct"] = StructType->GetName();
		}
		return Desc;
	}

	sol::table LuaDescribeFunction(sol::this_state State, const FFunction& Function)
	{
		sol::state_view Lua(State);
		sol::table      Desc = Lua.create_table();
		Desc["Name"]         = Function.GetName();
		Desc["Signature"]    = Function.GetSignature();
		Desc["DisplayName"]  = Function.GetDisplayName();
		Desc["Category"]     = Function.GetCategory();
		Desc["Flags"]        = Function.GetFlags();
		Desc["Const"]        = Function.IsConst();
		Desc["Static"]       = Function.IsStatic();
		Desc["OwnerClass"]   = Function.OwnerClassName ? Function.OwnerClassName : "";
		sol::table Params    = Lua.create_table();
		int        Index     = 1;
		for (const FProperty* Parameter : Function.GetParameters())
		{
			if (Parameter)
			{
				Params[Index++] = LuaDescribeProperty(State, *Parameter);
			}
		}
		Desc["Parameters"] = Params;
		if (const FProperty* ReturnProperty = Function.GetReturnProperty())
		{
			Desc["Return"] = LuaDescribeProperty(State, *ReturnProperty);
		}
		return Desc;
	}
}


sol::state& FLuaScriptManager::GetState()
{
	return *Lua;
}

void FLuaScriptManager::RegisterBindings(sol::state& Lua)
{
	RegisterLuaHelpers(Lua);
	RegisterCoreBindings(Lua);
	RegisterMathBindings(Lua);
	RegisterReflectionBindings(Lua);
	RegisterActorBindings(Lua);
	RegisterUIBindings(Lua);
}

FInputSystemSnapshot FLuaScriptManager::GetLuaInputSnapshot()
{
	if (GEngine)
	{
		if (UGameViewportClient* GameViewportClient = GEngine->GetGameViewportClient())
		{
			FInputSystemSnapshot Snapshot = GameViewportClient->GetGameInputSnapshot();
			return Snapshot;
		}
	}

	return InputSystem::Get().MakeSnapshot();
}

void FLuaScriptManager::RegisterLuaHelpers(sol::state& Lua)
{
	// 한글 경로 호환 — safe_script_file 은 내부적으로 fopen(UTF-8) 을 쓰므로 ANSI 해석에서
	// 깨진다. wide ifstream 으로 직접 읽어 safe_script(string) 으로 실행.
	FString Content;
	if (!ReadScriptFileContent("CoroutineManager.lua", Content))
	{
		UE_LOG("[Lua] Failed to load CoroutineManager.lua");
		return;
	}
	const FString ChunkName = ResolveScriptPath("CoroutineManager.lua");
	sol::protected_function_result Result = Lua.safe_script(Content, sol::script_pass_on_error, ChunkName);
	if (!Result.valid())
	{
		sol::error Err = Result;
		UE_LOG("[Lua] CoroutineManager.lua error: %s", Err.what());
	}
}

void FLuaScriptManager::RegisterCoreBindings(sol::state& Lua)
{
	Lua.set_function("print", [](sol::variadic_args Args)
	{
		FString Message;

		for (auto Arg : Args)
		{
			if (!Message.empty())
			{
				Message += "\t";
			}

			Message += Arg.as<FString>();
		}

		UE_LOG("[Lua] %s", Message.c_str());
	});

	sol::table Input = Lua.create_named_table("Input");
	Input.set_function("GetKeyDown", sol::overload(
		[](int VK)
	{
		return GetLuaInputSnapshot().WasPressed(VK);
	}));
	Input.set_function("GetKey", sol::overload(
		[](int VK)
	{
		return GetLuaInputSnapshot().IsDown(VK);
	}));
	Input.set_function("GetKeyUp", sol::overload(
		[](int VK)
	{
		return GetLuaInputSnapshot().WasReleased(VK);
	}));
	Input.set_function("GetMouseDeltaX", []()
	{
		return GetLuaInputSnapshot().MouseDeltaX;
	});
	Input.set_function("GetMouseDeltaY", []()
	{
		return GetLuaInputSnapshot().MouseDeltaY;
	});
	Input.set_function("GetMouseWheelDelta", []()
	{
		return GetLuaInputSnapshot().ScrollDelta;
	});
	Input.set_function("GetMouseWheelNotches", []()
	{
		return static_cast<float>(GetLuaInputSnapshot().ScrollDelta) / static_cast<float>(WHEEL_DELTA);
	});
	Input.set_function("GetMouseX", []()
	{
		if (GEngine)
		{
			if (UGameViewportClient* GameViewportClient = GEngine->GetGameViewportClient())
			{
				POINT MousePos = {};
				if (GameViewportClient->GetMouseViewportPosition(MousePos))
				{
					return MousePos.x;
				}
			}
		}

		return InputSystem::Get().GetMouseClientPos().x;
	});
	Input.set_function("GetMouseY", []()
	{
		if (GEngine)
		{
			if (UGameViewportClient* GameViewportClient = GEngine->GetGameViewportClient())
			{
				POINT MousePos = {};
				if (GameViewportClient->GetMouseViewportPosition(MousePos))
				{
					return MousePos.y;
				}
			}
		}

		return InputSystem::Get().GetMouseClientPos().y;
	});

	// Engine — 게임 일시정지 / 종료.
	sol::table Engine = Lua.create_named_table("Engine");
	Engine.set_function("PauseGame", []()
	{
		if (GEngine)
		{
			if (UWorld* World = GEngine->GetWorld())
			{
				World->SetPaused(true);
			}
		}
	});
	Engine.set_function("ResumeGame", []()
	{
		if (GEngine)
		{
			if (UWorld* World = GEngine->GetWorld())
			{
				World->SetPaused(false);
			}
		}
	});
	Engine.set_function("SetCursorVisible", [](bool bVisible)
	{
		if (!GEngine)
		{
			return;
		}

		if (UGameViewportClient* GameViewportClient = GEngine->GetGameViewportClient())
		{
			GameViewportClient->SetCursorVisible(bVisible);
		}
	});
	Engine.set_function("IsPaused", []()
	{
		if (GEngine)
		{
			if (UWorld* World = GEngine->GetWorld())
			{
				return World->IsPaused();
			}
		}
		return false;
	});
	Engine.set_function("GetViewportSize", []() -> sol::table
	{
		sol::table Result = FLuaScriptManager::GetState().create_table();
		Result["Width"] = 0.0f;
		Result["Height"] = 0.0f;

		float ViewportWidth = 0.0f;
		float ViewportHeight = 0.0f;
		if (GetLuaViewportSize(ViewportWidth, ViewportHeight))
		{
			Result["Width"] = ViewportWidth;
			Result["Height"] = ViewportHeight;
		}

		return Result;
	});
	Engine.set_function("GetViewportCenterRay", []() -> sol::table
	{
		sol::table Result = FLuaScriptManager::GetState().create_table();
		Result["bValid"] = false;
		Result["Width"] = 0.0f;
		Result["Height"] = 0.0f;
		Result["ScreenX"] = 0.0f;
		Result["ScreenY"] = 0.0f;
		Result["Origin"] = FVector(0.0f, 0.0f, 0.0f);
		Result["NearOrigin"] = FVector(0.0f, 0.0f, 0.0f);
		Result["Direction"] = FVector(1.0f, 0.0f, 0.0f);

		if (!GEngine)
		{
			return Result;
		}

		UWorld* World = GEngine->GetWorld();
		if (!World)
		{
			return Result;
		}

		float ViewportWidth = 0.0f;
		float ViewportHeight = 0.0f;
		GetLuaViewportSize(ViewportWidth, ViewportHeight);
		const float ScreenX = ViewportWidth * 0.5f;
		const float ScreenY = ViewportHeight * 0.5f;
		Result["Width"] = ViewportWidth;
		Result["Height"] = ViewportHeight;
		Result["ScreenX"] = ScreenX;
		Result["ScreenY"] = ScreenY;
		if (ViewportWidth <= 0.0f || ViewportHeight <= 0.0f)
		{
			return Result;
		}

		FMinimalViewInfo POV;
		bool bHasPOV = false;
		if (APlayerController* PC = World->GetFirstPlayerController())
		{
			if (APlayerCameraManager* CameraManager = PC->GetPlayerCameraManager())
			{
				bHasPOV = CameraManager->GetCameraView(POV);
			}
		}
		if (!bHasPOV)
		{
			bHasPOV = World->GetActivePOV(POV);
		}
		if (!bHasPOV)
		{
			return Result;
		}

		POV.AspectRatio = ViewportWidth / ViewportHeight;
		const FRay Ray = POV.DeprojectScreenToWorld(ScreenX, ScreenY, ViewportWidth, ViewportHeight);
		FVector Direction = Ray.Direction;
		if (Direction.Length() <= 0.0001f)
		{
			Direction = POV.Rotation.GetForwardVector();
		}
		Direction.Normalize();

		Result["Origin"] = POV.Location;
		Result["NearOrigin"] = Ray.Origin;
		Result["Direction"] = Direction;
		Result["bValid"] = true;
		return Result;
	});
	Engine.set_function("ProjectWorldToScreen", [](const FVector& WorldPosition) -> sol::table
	{
		sol::table Result = FLuaScriptManager::GetState().create_table();
		Result["X"] = 0.0f;
		Result["Y"] = 0.0f;
		Result["Depth"] = 0.0f;
		Result["Width"] = 0.0f;
		Result["Height"] = 0.0f;
		Result["bValid"] = false;
		Result["bInFront"] = false;
		Result["bOnScreen"] = false;

		if (!GEngine)
		{
			return Result;
		}

		UWorld* World = GEngine->GetWorld();
		if (!World)
		{
			return Result;
		}

		float ViewportWidth = 0.0f;
		float ViewportHeight = 0.0f;
		GetLuaViewportSize(ViewportWidth, ViewportHeight);
		Result["Width"] = ViewportWidth;
		Result["Height"] = ViewportHeight;
		if (ViewportWidth <= 0.0f || ViewportHeight <= 0.0f)
		{
			return Result;
		}

		FMinimalViewInfo POV;
		bool bHasPOV = false;
		if (APlayerController* PC = World->GetFirstPlayerController())
		{
			if (APlayerCameraManager* CameraManager = PC->GetPlayerCameraManager())
			{
				bHasPOV = CameraManager->GetCameraView(POV);
			}
		}
		if (!bHasPOV)
		{
			bHasPOV = World->GetActivePOV(POV);
		}
		if (!bHasPOV)
		{
			return Result;
		}

		POV.AspectRatio = ViewportWidth / ViewportHeight;
		const FMatrix ViewProjection = POV.CalculateViewProjectionMatrix();
		const FVector Clip = ViewProjection.TransformPositionWithW(WorldPosition);
		if (!std::isfinite(Clip.X) || !std::isfinite(Clip.Y) || !std::isfinite(Clip.Z))
		{
			return Result;
		}

		const FVector ToPoint = WorldPosition - POV.Location;
		const float Depth = ToPoint.Dot(POV.Rotation.GetForwardVector());
		Result["Depth"] = Depth;
		Result["bInFront"] = Depth > 0.0001f;
		if (Depth <= 0.0001f)
		{
			return Result;
		}

		const float ScreenX = (Clip.X * 0.5f + 0.5f) * ViewportWidth;
		const float ScreenY = (0.5f - Clip.Y * 0.5f) * ViewportHeight;

		Result["X"] = ScreenX;
		Result["Y"] = ScreenY;
		Result["bValid"] = true;
		Result["bOnScreen"] = ScreenX >= 0.0f
			&& ScreenX <= ViewportWidth
			&& ScreenY >= 0.0f
			&& ScreenY <= ViewportHeight;
		return Result;
	});
	Engine.set_function("Exit", []()
	{
		// WM_QUIT — FEngineLoop::Run 이 PumpMessages 에서 잡고 정상 shutdown.
		PostQuitMessage(0);
	});
	Engine.set_function("LoadScene", [](const FString& ScenePath)
	{
		// 요청한 프레임 끝(WorldTick·Render 이후)에 안전 교체 (GameEngine::ProcessPendingTransition
		// — 월드 destroy + FireWorldReset + 새 씬 BeginPlay). "GameOver" 같은 짧은 이름도 됨.
		// PIE 에선 세션 종료(에디터 복귀)로 매핑된다.
		if (GEngine)
		{
			GEngine->RequestTransitionToScene(ScenePath);
		}
	});
	Engine.set_function("SetOnEscape", [](sol::protected_function Callback)
	{
		FLuaScriptManager::SetOnEscapePressed(std::move(Callback));
	});

	sol::table Key = Lua.create_named_table("Key");
	Key["W"] = static_cast<int32>('W');
	Key["A"] = static_cast<int32>('A');
	Key["S"] = static_cast<int32>('S');
	Key["D"] = static_cast<int32>('D');
	Key["R"] = static_cast<int32>('R');
	Key["Shift"] = VK_SHIFT;
	Key["Space"] = VK_SPACE;
	Key["Escape"] = VK_ESCAPE;
	Key["F1"] = VK_F1;
	Key["F2"] = VK_F2;
	Key["F3"] = VK_F3;
	Key["F4"] = VK_F4;
	Key["F5"] = VK_F5;
	Key["F6"] = VK_F6;
	Key["F7"] = VK_F7;
	Key["F8"] = VK_F8;

	sol::table CameraManager = Lua.create_named_table("CameraManager");
	CameraManager.set_function("ToggleActorCamera", [](const FString& ActorName, sol::optional<float> BlendTime)
	{
		if (!GEngine || !GEngine->GetWorld())
		{
			return false;
		}

		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		return Manager ? Manager->ToggleActiveCameraForActor(ActorName, BlendTime.value_or(0.0f)) : false;
	});
	CameraManager.set_function("ToggleOwnerCamera", [](AActor* Actor, sol::optional<float> BlendTime)
	{
		if (!GEngine || !GEngine->GetWorld())
		{
			return false;
		}

		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		return Manager ? Manager->ToggleActiveCameraForActor(Actor, BlendTime.value_or(0.0f)) : false;
	});
	CameraManager.set_function("PossessCamera", [](UCameraComponent* Camera)
	{
		if (!GEngine || !GEngine->GetWorld() || !IsValid(Camera))
		{
			return false;
		}

		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		if (!Manager)
		{
			return false;
		}

		Manager->SetActiveCamera(Camera);
		Manager->Possess(Camera);
		return true;
	});
	CameraManager.set_function("GetActiveCameraOwner", []() -> AActor*
	{
		if (!GEngine || !GEngine->GetWorld())
		{
			return nullptr;
		}
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		UCameraComponent* ActiveCamera = Manager ? Manager->GetActiveCamera() : nullptr;
		if (!IsValid(ActiveCamera)) return nullptr;
		AActor* Owner = ActiveCamera->GetOwner();
		return IsValid(Owner) ? Owner : nullptr;
	});
	CameraManager.set_function("GetPossessedCamera", []() -> UCameraComponent*
	{
		if (!GEngine || !GEngine->GetWorld())
		{
			return nullptr;
		}
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		return Manager ? Manager->GetPossessedCamera() : nullptr;
	});
	CameraManager.set_function("GetPossessedCameraOwner", []() -> AActor*
	{
		if (!GEngine || !GEngine->GetWorld())
		{
			return nullptr;
		}
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		UCameraComponent* PossessedCamera = Manager ? Manager->GetPossessedCamera() : nullptr;
		if (!IsValid(PossessedCamera)) return nullptr;
		AActor* Owner = PossessedCamera->GetOwner();
		return IsValid(Owner) ? Owner : nullptr;
	});
	CameraManager.set_function("FadeOut", [](float Duration)
	{
		if (!GEngine || !GEngine->GetWorld()) return;
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		if (Manager)
		{
			Manager->StartCameraFade(0.0f, 1.0f, Duration, FLinearColor::Black(), false, true);
		}
	});
	CameraManager.set_function("FadeIn", [](float Duration)
	{
		if (!GEngine || !GEngine->GetWorld()) return;
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		if (Manager)
		{
			Manager->StartCameraFade(1.0f, 0.0f, Duration, FLinearColor::Black(), false, true);
		}
	});
	CameraManager.set_function("SetVignette", [](float Intensity, float Radius, float Softness)
	{
		if (!GEngine || !GEngine->GetWorld()) return;
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		if (Manager)
		{
			Manager->SetCameraVignette(Intensity, Radius, Softness, FLinearColor::Black());
		}
	});
	CameraManager.set_function("ClearVignette", []()
	{
		if (!GEngine || !GEngine->GetWorld()) return;
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		if (Manager)
		{
			Manager->ClearCameraVignette();
		}
	});
	CameraManager.set_function("SetViewTargetWithBlend", [](AActor* Target, float BlendTime)
	{
		if (!GEngine || !GEngine->GetWorld() || !IsValid(Target)) return;

		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		if (PC)
		{
			PC->SetViewTargetWithBlend(Target, BlendTime);
		}
	});
	// ActiveCamera 컴포넌트 단위 blend — 같은 액터 내 1인칭/3인칭 같은 별개 카메라
	// 컴포넌트 사이 부드럽게 전환. BlendTime 미지정 시 0 (즉시 swap).
	CameraManager.set_function("SetActiveCameraWithBlend", [](UCameraComponent* NewCamera, sol::optional<float> BlendTime)
	{
		if (!GEngine || !GEngine->GetWorld() || !IsValid(NewCamera)) return;
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		if (Manager)
		{
			Manager->SetActiveCameraWithBlend(NewCamera, BlendTime.value_or(0.0f));
		}
	});
	// Sample wave-oscillator shake — Lua console / 스크립트에서 즉시 흔들기 테스트용.
	// 호출 예: CameraManager.StartWaveShake(1.0)
	CameraManager.set_function("StartWaveShake", [](sol::optional<float> Scale)
	{
		if (!GEngine || !GEngine->GetWorld()) return;
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		if (Manager)
		{
			Manager->StartCameraShake<UWaveOscillatorCameraShake>(Scale.value_or(1.0f));
		}
	});
	CameraManager.set_function("StartSequenceShake", [](sol::optional<float> Scale)
	{
		if (!GEngine || !GEngine->GetWorld()) return;
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		if (Manager)
		{
			Manager->StartCameraShake<USequenceCameraShake>(Scale.value_or(1.0f));
		}
	});
	CameraManager.set_function("StartCameraShakeAsset", [](const FString& AssetPath, sol::optional<float> Scale)
	{
		if (!GEngine || !GEngine->GetWorld()) return;
		APlayerController* PC = GEngine->GetWorld()->GetFirstPlayerController();
		APlayerCameraManager* Manager = PC ? PC->GetPlayerCameraManager() : nullptr;
		if (Manager)
		{
			Manager->StartCameraShakeAsset(AssetPath, Scale.value_or(1.0f));
		}
	});

	sol::table AudioManager = Lua.create_named_table("AudioManager");
	AudioManager.set_function("Load", [](const FString& SoundName, const FString& Path, sol::optional<bool> bLoop)
	{
		return FAudioManager::Get().LoadAudio(SoundName, Path, bLoop.value_or(false));
	});
	AudioManager.set_function("Play", [](const FString& SoundName, float Volume)
	{
		FAudioManager::Get().PlayAudio(SoundName, Volume);
	});
	AudioManager.set_function("PlayBGM", [](const FString& SoundName, float Volume)
	{
		FAudioManager::Get().PlayBGM(SoundName, Volume);
	});
	AudioManager.set_function("StopBGM", []()
	{
		FAudioManager::Get().StopBGM();
	});
	AudioManager.set_function("PlayLoop", [](const FString& SoundName, const FString& LoopName, sol::optional<float> Volume, sol::optional<float> Pitch)
	{
		FAudioManager::Get().PlayLoop(SoundName, LoopName, Volume.value_or(1.0f), Pitch.value_or(1.0f));
	});
	AudioManager.set_function("StopLoop", [](const FString& LoopName)
	{
		FAudioManager::Get().StopLoop(LoopName);
	});
	AudioManager.set_function("StopAllLoops", []()
	{
		FAudioManager::Get().StopAllLoops();
	});
	AudioManager.set_function("SetLoopVolume", [](const FString& LoopName, float Volume)
	{
		FAudioManager::Get().SetLoopVolume(LoopName, Volume);
	});
	AudioManager.set_function("SetLoopPitch", [](const FString& LoopName, float Pitch)
	{
		FAudioManager::Get().SetLoopPitch(LoopName, Pitch);
	});
	AudioManager.set_function("IsLoopPlaying", [](const FString& LoopName)
	{
		return FAudioManager::Get().IsLoopPlaying(LoopName);
	});

	// ParticleManager — 파티클 에셋(.uasset)을 위치에 스폰. FParticleSystemManager(캐시) 래핑.
	// 반환값은 Actor 핸들 — 수명 관리(Destroy)는 Lua 쪽 몫이다 (ParticleFX.lua 참고).
	sol::table ParticleManager = Lua.create_named_table("ParticleManager");
	ParticleManager.set_function("SpawnAt", [](const FString& Path, const FVector& Pos) -> AActor*
	{
		if (!GEngine) return nullptr;
		UWorld* World = GEngine->GetWorld();
		if (!World) return nullptr;

		UParticleSystem* Template = FParticleSystemManager::Get().Load(Path);
		if (!Template)
		{
			UE_LOG("[Lua] ParticleManager.SpawnAt: 파티클 로드 실패. Path=%s", Path.c_str());
			return nullptr;
		}

		AActor* Actor = World->SpawnActorByClass(AActor::StaticClass());
		if (!Actor) return nullptr;

		UParticleSystemComponent* Comp = Actor->AddComponent<UParticleSystemComponent>();
		if (!Comp)
		{
			World->DestroyActor(Actor);
			return nullptr;
		}

		Actor->SetRootComponent(Comp);
		Comp->SetTemplate(Template);   // 내부에서 InitializeSystem + render state dirty 까지
		Actor->SetActorLocation(Pos);
		return Actor;
	});

	Lua.set_function("LoadAudio", [](const FString& SoundName, const FString& Path, sol::optional<bool> bLoop)
	{
		return FAudioManager::Get().LoadAudio(SoundName, Path, bLoop.value_or(false));
	});
}

void FLuaScriptManager::RegisterMathBindings(sol::state& Lua)
{
	Lua.new_usertype<FVector>("Vector",
		sol::constructors<FVector(), FVector(float, float, float)>(),
		"X", &FVector::X,
		"Y", &FVector::Y,
		"Z", &FVector::Z,
		"Length", &FVector::Length,
		"Normalize", &FVector::Normalize,
		"Normalized", &FVector::Normalized,
		"Dot", &FVector::Dot,
		"Cross", sol::overload(
		static_cast<FVector(FVector::*)(const FVector&) const>(&FVector::Cross),
		static_cast<FVector(*)(const FVector&, const FVector&)>(&FVector::Cross)
	),
		"Distance", &FVector::Distance,
		"DistSquared", &FVector::DistSquared,
		"Lerp", &FVector::Lerp,
		sol::meta_function::addition, sol::overload(
		static_cast<FVector(FVector::*)(const FVector&) const>(&FVector::operator+),
		static_cast<FVector(FVector::*)(float) const>(&FVector::operator+)
	),
		sol::meta_function::subtraction, sol::overload(
		static_cast<FVector(FVector::*)(const FVector&) const>(&FVector::operator-),
		static_cast<FVector(FVector::*)(float) const>(&FVector::operator-)
	),
		sol::meta_function::multiplication, sol::overload(
		static_cast<FVector(FVector::*)(const FVector&) const>(&FVector::operator*),
		static_cast<FVector(FVector::*)(float) const>(&FVector::operator*)
	),
		sol::meta_function::division, &FVector::operator/,
		"Zero", []() { return FVector::ZeroVector; },
		"One", []() { return FVector::OneVector; },
		"Up", []() { return FVector::UpVector; },
		"Down", []() { return FVector::DownVector; },
		"Forward", []() { return FVector::ForwardVector; },
		"Backward", []() { return FVector::BackwardVector; },
		"Right", []() { return FVector::RightVector; },
		"Left", []() { return FVector::LeftVector; },
		"XAxis", []() { return FVector::XAxisVector; },
		"YAxis", []() { return FVector::YAxisVector; },
		"ZAxis", []() { return FVector::ZAxisVector; });

	sol::table Math = Lua.create_named_table("Math");

	Math["Pi"] = FMath::Pi;
	Math["DegToRad"] = FMath::DegToRad;
	Math["RadToDeg"] = FMath::RadToDeg;

	Math.set_function("Atan2", [](float Y, float X)
		{
			return std::atan2(Y, X);
		});

	Math.set_function("RadiansToDegrees", [](float Radians)
		{
			return Radians * FMath::RadToDeg;
		});

	Math.set_function("DegreesToRadians", [](float Degrees)
		{
			return Degrees * FMath::DegToRad;
		});
}

void FLuaScriptManager::RegisterReflectionBindings(sol::state& Lua)
{
	Lua.new_usertype<UObject>(
		"Object",
		"GetName",
		[](UObject& Object) { return Object.GetName(); },
		"GetClassName",
		[](UObject& Object) { return Object.GetClass() ? FString(Object.GetClass()->GetName()) : FString(); },
		"GetUUID",
		&UObject::GetUUID,
		"IsValid",
		[](UObject* Object) { return IsValid(Object); },
		"CallFunction",
		[](UObject& Object, const FString& FunctionName, sol::variadic_args Args, sol::this_state State)
		{
			return LuaInvokeReflectedFunction(State, &Object, nullptr, FunctionName, Args);
		},
		"CallFunctionSignature",
		[](UObject& Object, const FString& Signature, sol::variadic_args Args, sol::this_state State)
		{
			return LuaInvokeReflectedFunctionBySignature(State, &Object, nullptr, Signature, Args);
		},
		"BindEvent",
		[](UObject& Object, const FString& FunctionNameOrSignature, sol::protected_function Callback)
		{
			return LuaBindReflectedEventOverride(&Object, FunctionNameOrSignature, std::move(Callback));
		},
		"UnbindEvent",
		[](UObject& Object, const FString& FunctionNameOrSignature)
		{
			return LuaUnbindReflectedEventOverride(&Object, FunctionNameOrSignature);
		},
		"HasEventBinding",
		[](UObject& Object, const FString& FunctionNameOrSignature)
		{
			return LuaHasReflectedEventOverride(&Object, FunctionNameOrSignature);
		},
		"GetProperty",
		[](UObject& Object, const FString& PropertyName, sol::this_state State)
		{
			return LuaGetReflectedProperty(State, &Object, PropertyName);
		},
		"SetProperty",
		[](UObject& Object, const FString& PropertyName, sol::object Value)
		{
			return LuaSetReflectedProperty(&Object, PropertyName, Value);
		},
		"GetFunctions",
		[](UObject& Object, sol::this_state State)
		{
			sol::state_view L(State);
			sol::table      Result = L.create_table();
			if (!Object.GetClass())
			{
				return Result;
			}
			TArray<const FFunction*> Functions;
			Object.GetClass()->GetFunctionRefs(Functions);
			int Index = 1;
			for (const FFunction* Function : Functions)
			{
				if (Function)
				{
					Result[Index++] = LuaDescribeFunction(State, *Function);
				}
			}
			return Result;
		},
		"GetProperties",
		[](UObject& Object, sol::this_state State)
		{
			sol::state_view L(State);
			sol::table      Result = L.create_table();
			if (!Object.GetClass())
			{
				return Result;
			}
			TArray<const FProperty*> Properties;
			Object.GetClass()->GetPropertyRefs(Properties);
			int Index = 1;
			for (const FProperty* Property : Properties)
			{
				if (Property)
				{
					Result[Index++] = LuaDescribeProperty(State, *Property);
				}
			}
			return Result;
		}
	);

	Lua.new_usertype<UActorComponent>(
		"ActorComponent",
		sol::base_classes,
		sol::bases<UObject>(),
		"GetOwner",
		&UActorComponent::GetOwner,
		"IsActive",
		&UActorComponent::IsActive,
		"SetActive",
		&UActorComponent::SetActive,
		"Activate",
		&UActorComponent::Activate,
		"Deactivate",
		&UActorComponent::Deactivate
	);

	sol::table Reflection = Lua.create_named_table("Reflection");
	Reflection.set_function(
		"Call",
		[](UObject* Object, const FString& FunctionName, sol::variadic_args Args, sol::this_state State)
		{
			return LuaInvokeReflectedFunction(State, Object, nullptr, FunctionName, Args);
		}
	);
	Reflection.set_function(
		"CallSignature",
		[](UObject* Object, const FString& Signature, sol::variadic_args Args, sol::this_state State)
		{
			return LuaInvokeReflectedFunctionBySignature(State, Object, nullptr, Signature, Args);
		}
	);
	Reflection.set_function(
		"CallStatic",
		[](const FString& ClassName, const FString& FunctionName, sol::variadic_args Args, sol::this_state State)
		{
			UClass* Class = UClass::FindByName(ClassName.c_str());
			return LuaInvokeReflectedFunction(State, nullptr, Class, FunctionName, Args);
		}
	);
	Reflection.set_function(
		"CallStaticSignature",
		[](const FString& ClassName, const FString& Signature, sol::variadic_args Args, sol::this_state State)
		{
			UClass* Class = UClass::FindByName(ClassName.c_str());
			return LuaInvokeReflectedFunctionBySignature(State, nullptr, Class, Signature, Args);
		}
	);
	Reflection.set_function(
		"BindEvent",
		[](UObject* Object, const FString& FunctionNameOrSignature, sol::protected_function Callback)
		{
			return LuaBindReflectedEventOverride(Object, FunctionNameOrSignature, std::move(Callback));
		}
	);
	Reflection.set_function(
		"UnbindEvent",
		[](UObject* Object, const FString& FunctionNameOrSignature)
		{
			return LuaUnbindReflectedEventOverride(Object, FunctionNameOrSignature);
		}
	);
	Reflection.set_function(
		"HasEventBinding",
		[](UObject* Object, const FString& FunctionNameOrSignature)
		{
			return LuaHasReflectedEventOverride(Object, FunctionNameOrSignature);
		}
	);
	Reflection.set_function(
		"GetProperty",
		[](UObject* Object, const FString& PropertyName, sol::this_state State)
		{
			return LuaGetReflectedProperty(State, Object, PropertyName);
		}
	);
	Reflection.set_function(
		"SetProperty",
		[](UObject* Object, const FString& PropertyName, sol::object Value)
		{
			return LuaSetReflectedProperty(Object, PropertyName, Value);
		}
	);
	Reflection.set_function(
		"GetFunctions",
		[](UObject* Object, sol::this_state State)
		{
			sol::state_view L(State);
			sol::table      Result = L.create_table();
			if (!Object || !Object->GetClass())
			{
				return Result;
			}
			TArray<const FFunction*> Functions;
			Object->GetClass()->GetFunctionRefs(Functions);
			int Index = 1;
			for (const FFunction* Function : Functions)
			{
				if (Function)
				{
					Result[Index++] = LuaDescribeFunction(State, *Function);
				}
			}
			return Result;
		}
	);
	// LuaBlueprint Cast 노드용 — IsA 통과 시 같은 객체 반환, 실패 시 nil.
	// 실제 Unreal Blueprint Cast 와 동일한 의미 (성공/실패 분기).
	Reflection.set_function(
		"Cast",
		[](UObject* Object, const FString& ClassName) -> UObject*
		{
			if (!Object) return nullptr;
			UClass* Target = UClass::FindByName(ClassName.c_str());
			if (!Target) return nullptr;
			UClass* Source = Object->GetClass();
			if (!Source) return nullptr;
			return Source->IsA(Target) ? Object : nullptr;
		}
	);
	Reflection.set_function(
		"GetStaticFunctions",
		[](const FString& ClassName, sol::this_state State)
		{
			sol::state_view L(State);
			sol::table      Result = L.create_table();
			UClass*         Class  = UClass::FindByName(ClassName.c_str());
			if (!Class)
			{
				return Result;
			}
			TArray<const FFunction*> Functions;
			Class->GetFunctionRefs(Functions);
			int Index = 1;
			for (const FFunction* Function : Functions)
			{
				if (Function && Function->IsStatic())
				{
					Result[Index++] = LuaDescribeFunction(State, *Function);
				}
			}
			return Result;
		}
	);
	Reflection.set_function(
		"GetProperties",
		[](UObject* Object, sol::this_state State)
		{
			sol::state_view L(State);
			sol::table      Result = L.create_table();
			if (!Object || !Object->GetClass())
			{
				return Result;
			}
			TArray<const FProperty*> Properties;
			Object->GetClass()->GetPropertyRefs(Properties);
			int Index = 1;
			for (const FProperty* Property : Properties)
			{
				if (Property)
				{
					Result[Index++] = LuaDescribeProperty(State, *Property);
				}
			}
			return Result;
		}
	);
}

void FLuaScriptManager::RegisterActorBindings(sol::state& Lua)
{
	Lua.new_usertype<UActionComponent>("ActionComponent",
		sol::base_classes,
		sol::bases<UActorComponent, UObject>(),
		"HitStop", &UActionComponent::HitStop,
		"HitSquash", &UActionComponent::HitSquash,
		"Knockback", &UActionComponent::Knockback,
		"Slomo", &UActionComponent::Slomo,
		"StopHitStop", &UActionComponent::StopHitStop,
		"StopHitSquash", &UActionComponent::StopHitSquash,
		"StopKnockback", &UActionComponent::StopKnockback,
		"StopSlomo", &UActionComponent::StopSlomo,
		"StopAllActions", &UActionComponent::StopAllActions);

	Lua.new_usertype<UFloatingPawnMovementComponent>("FloatingPawnMovementComponent",
		sol::base_classes,
		sol::bases<UActorComponent, UObject>(),
		"SetMoveInput", &UFloatingPawnMovementComponent::SetMoveInput,
		"SetLookInput", &UFloatingPawnMovementComponent::SetLookInput);

	Lua.new_usertype<USceneComponent>("SceneComponent",
		sol::base_classes,
		sol::bases<UActorComponent, UObject>(),
		"Location", sol::property(
		[](USceneComponent& Component)
	{
		return Component.GetWorldLocation();
	},
		[](USceneComponent& Component, const FVector& Location)
	{
		Component.SetWorldLocation(Location);
	}
	),
		"Rotation", sol::property(
		[](USceneComponent& Component)
	{
		return Component.GetRelativeRotation().ToVector();
	},
		[](USceneComponent& Component, const FVector& Rotation)
	{
		Component.SetRelativeRotation(Rotation);
	}
	),
		"Forward", sol::property([](USceneComponent& Component)
	{
		return Component.GetForwardVector();
	}
	),
		"Right", sol::property([](USceneComponent& Component)
	{
		return Component.GetRightVector();
	}
	),
		"Up", sol::property([](USceneComponent& Component)
	{
		return Component.GetUpVector();
	}
	),
		"GetLocation", [](USceneComponent& Component)
	{
		return Component.GetWorldLocation();
	},
		"SetLocation", [](USceneComponent& Component, const FVector& Location)
	{
		Component.SetWorldLocation(Location);
	},
		"GetRotation", [](USceneComponent& Component)
	{
		return Component.GetRelativeRotation().ToVector();
	},
		"SetRotation", [](USceneComponent& Component, const FVector& Rotation)
	{
		Component.SetRelativeRotation(Rotation);
	},

		// 부모 기준 상대 위치 — 동일한 메시를 4개 깐 바퀴 같은 케이스에서 앞/뒤 구분 등
		// 위치 기반 필터링에 쓰인다. 월드 위치는 위 "Location" 프로퍼티 참고.
		"RelativeLocation", sol::property(
		[](USceneComponent& Component) { return Component.GetRelativeLocation(); },
		[](USceneComponent& Component, const FVector& V) { Component.SetRelativeLocation(V); }
		),
		"GetRelativeLocation", [](USceneComponent& Component) { return Component.GetRelativeLocation(); },
		"SetRelativeLocation", [](USceneComponent& Component, const FVector& V) { Component.SetRelativeLocation(V); },
		"RelativeScale", sol::property(
		[](USceneComponent& Component) { return Component.GetRelativeScale(); },
		[](USceneComponent& Component, const FVector& V) { Component.SetRelativeScale(V); }
		),
		"GetRelativeScale", [](USceneComponent& Component) { return Component.GetRelativeScale(); },
		"SetRelativeScale", [](USceneComponent& Component, const FVector& V) { Component.SetRelativeScale(V); }
		);

	Lua.new_usertype<FBodyInstance>("PhysicsBody",
		"IsValid", [](FBodyInstance& Body)
		{
			return Body.IsValidBodyInstance();
		},
		"IsDynamic", [](FBodyInstance& Body)
		{
			return Body.GetRigidDynamic() != nullptr;
		},
		"IsKinematic", [](FBodyInstance& Body)
		{
			return Body.bKinematic;
		},
		"SetKinematic", &FBodyInstance::SetKinematic,
		"SetGravityEnabled", &FBodyInstance::SetGravityEnabled,
		"WakeUp", &FBodyInstance::WakeUp,
		"AddForce", &FBodyInstance::AddForce,
		"AddImpulse", &FBodyInstance::AddImpulse,
		"AddForceAtLocation", &FBodyInstance::AddForceAtLocation,
		"AddTorque", &FBodyInstance::AddTorque,
		"GetLinearVelocity", &FBodyInstance::GetLinearVelocity,
		"SetLinearVelocity", &FBodyInstance::SetLinearVelocity,
		"GetAngularVelocity", &FBodyInstance::GetAngularVelocity,
		"SetAngularVelocity", &FBodyInstance::SetAngularVelocity,
		"GetMass", &FBodyInstance::GetMass,
		"SetMass", &FBodyInstance::SetMass,
		"GetLocation", [](FBodyInstance& Body)
		{
			return Body.GetBodyTransform().GetLocation();
		},
		"WorldToLocalPoint", [](FBodyInstance& Body, const FVector& WorldPoint)
		{
			return Body.GetBodyTransform().ToMatrix().GetAffineInverse().TransformPositionWithW(WorldPoint);
		},
		"LocalToWorldPoint", [](FBodyInstance& Body, const FVector& LocalPoint)
		{
			return Body.GetBodyTransform().TransformPosition(LocalPoint);
		},
		"GetOwnerActor", [](FBodyInstance& Body) -> AActor*
		{
			return Body.GetOwnerActor();
		},
		"GetOwnerComponent", [](FBodyInstance& Body) -> UPrimitiveComponent*
		{
			return Body.OwnerComponent ? Body.OwnerComponent : Body.OwnerSkeletalComponent;
		},
		"GetBoneName", [](FBodyInstance& Body)
		{
			return Body.BoneName.ToString();
		},
		"BoneName", sol::property([](FBodyInstance& Body)
		{
			return Body.BoneName.ToString();
		}));

	Lua.new_usertype<UPrimitiveComponent>("PrimitiveComponent",
		sol::base_classes,
		sol::bases<USceneComponent, UActorComponent, UObject>(),
		"SetSimulatePhysics", &UPrimitiveComponent::SetSimulatePhysics,
		"GetSimulatePhysics", &UPrimitiveComponent::GetSimulatePhysics,
		"AddForce", &UPrimitiveComponent::AddForce,
		"AddForceAtLocation", &UPrimitiveComponent::AddForceAtLocation,
		"AddTorque", &UPrimitiveComponent::AddTorque,
		"GetLinearVelocity", &UPrimitiveComponent::GetLinearVelocity,
		"SetLinearVelocity", &UPrimitiveComponent::SetLinearVelocity,
		"GetAngularVelocity", &UPrimitiveComponent::GetAngularVelocity,
		"SetAngularVelocity", &UPrimitiveComponent::SetAngularVelocity,
		"GetMass", &UPrimitiveComponent::GetMass,
		"SetMass", &UPrimitiveComponent::SetMass,
		"SetVisibility", &UPrimitiveComponent::SetVisibility,
		"IsVisible", &UPrimitiveComponent::IsVisible,
		"GetGenerateOverlapEvents", &UPrimitiveComponent::GetGenerateOverlapEvents,
		"TriggerHitRim", [](UPrimitiveComponent& Component, sol::optional<float> Duration, sol::optional<float> Intensity, sol::optional<float> Power, sol::optional<float> SustainIntensity)
		{
			Component.TriggerHitRim(Duration.value_or(0.18f), Intensity.value_or(3.5f), Power.value_or(3.0f), SustainIntensity.value_or(0.0f));
		},
		"RefreshHitRim", [](UPrimitiveComponent& Component, sol::optional<float> SustainIntensity, sol::optional<float> Power)
		{
			Component.RefreshHitRim(SustainIntensity.value_or(1.0f), Power.value_or(3.0f));
		},
		"SetHitRimColor", [](UPrimitiveComponent& Component, sol::optional<float> R, sol::optional<float> G, sol::optional<float> B, sol::optional<float> A)
		{
			Component.SetHitRimColor(FVector4(R.value_or(0.05f), G.value_or(0.85f), B.value_or(1.0f), A.value_or(1.0f)));
		},
		"SetHitImpactGlow", [](UPrimitiveComponent& Component, const FVector& WorldLocation, sol::optional<float> Radius, sol::optional<float> CoreRadius, sol::optional<float> Intensity)
		{
			Component.SetHitImpactGlow(WorldLocation, Radius.value_or(0.32f), CoreRadius.value_or(0.055f), Intensity.value_or(2.6f));
		},
		"TriggerHitRimAt", [](UPrimitiveComponent& Component, const FVector& WorldLocation, sol::optional<float> Duration, sol::optional<float> Intensity, sol::optional<float> Power, sol::optional<float> SustainIntensity, sol::optional<float> ImpactRadius, sol::optional<float> ImpactCoreRadius, sol::optional<float> ImpactIntensity)
		{
			Component.TriggerHitRimAt(
				WorldLocation,
				Duration.value_or(0.18f),
				Intensity.value_or(3.5f),
				Power.value_or(3.0f),
				SustainIntensity.value_or(0.0f),
				ImpactRadius.value_or(0.32f),
				ImpactCoreRadius.value_or(0.055f),
				ImpactIntensity.value_or(2.6f));
		},
		"RefreshHitRimAt", [](UPrimitiveComponent& Component, const FVector& WorldLocation, sol::optional<float> SustainIntensity, sol::optional<float> Power, sol::optional<float> ImpactRadius, sol::optional<float> ImpactCoreRadius, sol::optional<float> ImpactIntensity)
		{
			Component.RefreshHitRimAt(
				WorldLocation,
				SustainIntensity.value_or(1.0f),
				Power.value_or(3.0f),
				ImpactRadius.value_or(0.32f),
				ImpactCoreRadius.value_or(0.055f),
				ImpactIntensity.value_or(2.6f));
		},
		"ClearHitRim", &UPrimitiveComponent::ClearHitRim,
		"ResetParticleSystem", [](UPrimitiveComponent& Component)
		{
			UParticleSystemComponent* ParticleComponent = Cast<UParticleSystemComponent>(&Component);
			if (!ParticleComponent)
			{
				return false;
			}

			ParticleComponent->ResetSystem();
			return true;
		},
		"SetBeamEndPoint", [](UPrimitiveComponent& Component, const FVector& EndPoint)
		{
			return ApplyToBeamEmitters(Component, [&EndPoint](FParticleBeam2EmitterInstance& BeamInstance)
			{
				BeamInstance.SetBeamEndPoint(EndPoint);
			});
		},
		"SetBeamSourcePoint", [](UPrimitiveComponent& Component, const FVector& SourcePoint, sol::optional<int32> SourceIndex)
		{
			const int32 ResolvedIndex = SourceIndex.value_or(0);
			return ApplyToBeamEmitters(Component, [&SourcePoint, ResolvedIndex](FParticleBeam2EmitterInstance& BeamInstance)
			{
				BeamInstance.SetBeamSourcePoint(SourcePoint, ResolvedIndex);
			});
		},
		"SetBeamPoints", [](UPrimitiveComponent& Component, const FVector& SourcePoint, const FVector& TargetPoint, sol::optional<int32> BeamIndex, sol::optional<int32> SheetCount)
		{
			const int32 ResolvedIndex = BeamIndex.value_or(0);
			const bool bHasSheetCount = SheetCount.has_value();
			const int32 ResolvedSheetCount = SheetCount.value_or(1);
			return ApplyToBeamEmitters(Component, [&SourcePoint, &TargetPoint, ResolvedIndex, bHasSheetCount, ResolvedSheetCount](FParticleBeam2EmitterInstance& BeamInstance)
			{
				if (bHasSheetCount)
				{
					BeamInstance.SetBeamSheetCount(ResolvedSheetCount);
				}
				BeamInstance.SetBeamSourceAndTargetPoints(SourcePoint, TargetPoint, ResolvedIndex);
			});
		},
		"SetBeamPointsWithTangents", [](UPrimitiveComponent& Component, const FVector& SourcePoint, const FVector& TargetPoint,
			const FVector& SourceTangent, const FVector& TargetTangent,
			int32 SheetCount, int32 BeamIndex,
			float SourceStrengthScale, float TargetStrengthScale)
		{
			const int32 ResolvedSheetCount = SheetCount > 0 ? SheetCount : 1;
			const int32 ResolvedIndex = BeamIndex > 0 ? BeamIndex : 0;
			const float BeamDistance = (TargetPoint - SourcePoint).Length();
			const float ResolvedSourceStrength = BeamDistance * (SourceStrengthScale > 0.0f ? SourceStrengthScale : 0.0f);
			const float ResolvedTargetStrength = BeamDistance * (TargetStrengthScale > 0.0f ? TargetStrengthScale : 0.0f);
			return ApplyToBeamEmitters(Component, [&SourcePoint, &TargetPoint, &SourceTangent, &TargetTangent,
				ResolvedSheetCount, ResolvedIndex, ResolvedSourceStrength, ResolvedTargetStrength](FParticleBeam2EmitterInstance& BeamInstance)
			{
				BeamInstance.SetBeamSheetCount(ResolvedSheetCount);
				BeamInstance.SetBeamSourceAndTargetPointsWithTangents(
					SourcePoint,
					TargetPoint,
					SourceTangent,
					TargetTangent,
					ResolvedSourceStrength,
					ResolvedTargetStrength,
					ResolvedIndex);
			});
		},
		"SetBeamSheetCount", [](UPrimitiveComponent& Component, int32 SheetCount)
		{
			return ApplyToBeamEmitters(Component, [SheetCount](FParticleBeam2EmitterInstance& BeamInstance)
			{
				BeamInstance.SetBeamSheetCount(SheetCount);
			});
		},
		"SetBeamSourceTangent", [](UPrimitiveComponent& Component, const FVector& SourceTangent, sol::optional<int32> SourceIndex)
		{
			const int32 ResolvedIndex = SourceIndex.value_or(0);
			return ApplyToBeamEmitters(Component, [&SourceTangent, ResolvedIndex](FParticleBeam2EmitterInstance& BeamInstance)
			{
				BeamInstance.SetBeamSourceTangent(SourceTangent, ResolvedIndex);
			});
		},
		"SetBeamSourceStrength", [](UPrimitiveComponent& Component, float SourceStrength, sol::optional<int32> SourceIndex)
		{
			const int32 ResolvedIndex = SourceIndex.value_or(0);
			return ApplyToBeamEmitters(Component, [SourceStrength, ResolvedIndex](FParticleBeam2EmitterInstance& BeamInstance)
			{
				BeamInstance.SetBeamSourceStrength(SourceStrength, ResolvedIndex);
			});
		},
		"SetBeamTargetPoint", [](UPrimitiveComponent& Component, const FVector& TargetPoint, sol::optional<int32> TargetIndex)
		{
			const int32 ResolvedIndex = TargetIndex.value_or(0);
			return ApplyToBeamEmitters(Component, [&TargetPoint, ResolvedIndex](FParticleBeam2EmitterInstance& BeamInstance)
			{
				BeamInstance.SetBeamTargetPoint(TargetPoint, ResolvedIndex);
			});
		},
		"SetBeamTargetTangent", [](UPrimitiveComponent& Component, const FVector& TargetTangent, sol::optional<int32> TargetIndex)
		{
			const int32 ResolvedIndex = TargetIndex.value_or(0);
			return ApplyToBeamEmitters(Component, [&TargetTangent, ResolvedIndex](FParticleBeam2EmitterInstance& BeamInstance)
			{
				BeamInstance.SetBeamTargetTangent(TargetTangent, ResolvedIndex);
			});
		},
		"SetBeamTargetStrength", [](UPrimitiveComponent& Component, float TargetStrength, sol::optional<int32> TargetIndex)
		{
			const int32 ResolvedIndex = TargetIndex.value_or(0);
			return ApplyToBeamEmitters(Component, [TargetStrength, ResolvedIndex](FParticleBeam2EmitterInstance& BeamInstance)
			{
				BeamInstance.SetBeamTargetStrength(TargetStrength, ResolvedIndex);
			});
		});

	// 메시 에셋 경로로 컴포넌트 식별 가능하게 노출. 자동 생성된 FName ("UStaticMeshComponent_41")
	// 은 월드 초기화 순서에 따라 카운터가 달라져 빌드별로 매칭이 깨질 수 있다. 메시 경로는
	// 씬 파일에 명시 저장되므로 deterministic.
	Lua.new_usertype<UStaticMeshComponent>("StaticMeshComponent",
		sol::base_classes,
		sol::bases<UPrimitiveComponent, USceneComponent, UActorComponent, UObject>(),
		"MeshPath", sol::property([](UStaticMeshComponent& C) { return C.GetStaticMeshPath(); }),
		"GetMeshPath", [](UStaticMeshComponent& C) { return C.GetStaticMeshPath(); });

	Lua.new_usertype<FHitResult>("HitResult",
		"HitComponent", &FHitResult::HitComponent,
		"HitActor", &FHitResult::HitActor,
		"PhysicsBody", &FHitResult::PhysicsBody,
		"Distance", &FHitResult::Distance,
		"PenetrationDepth", &FHitResult::PenetrationDepth,
		"WorldHitLocation", &FHitResult::WorldHitLocation,
		"WorldNormal", &FHitResult::WorldNormal,
		"ImpactNormal", &FHitResult::ImpactNormal,
		"FaceIndex", &FHitResult::FaceIndex,
		"bHit", &FHitResult::bHit);

	Lua.new_usertype<UCameraComponent>("CameraComponent",
		sol::base_classes,
		sol::bases<USceneComponent, UActorComponent, UObject>()
	);

	Lua.new_usertype<AActor>("Actor",
		sol::base_classes,
		sol::bases<UObject>(),
		"Location", sol::property(
		[](AActor& Actor)
	{
		return Actor.GetActorLocation();
	},
		[](AActor& Actor, const FVector& Location)
	{
		Actor.SetActorLocation(Location);
	}
	),
		"Rotation", sol::property(
		[](AActor& Actor)
	{
		return Actor.GetActorRotation().ToVector();
	},
		[](AActor& Actor, const FVector& Rotation)
	{
		Actor.SetActorRotation(Rotation);
	}
	),

		"Scale", sol::property(
		[](AActor& Actor)
	{
		return Actor.GetActorScale();
	},
		[](AActor& Actor, const FVector& Scale)
	{
		Actor.SetActorScale(Scale);
	}
	),

		"Forward", sol::property([](AActor& Actor)
	{
		return Actor.GetActorForward();
	}
	),
		
		"Right", sol::property([](AActor& Actor)
	{
		return Actor.GetActorRight();
	}
	),

		"AddWorldOffset", [](AActor& Actor, const FVector& Offset)
	{
		Actor.AddActorWorldOffset(Offset);
	},

		"Destroy", [](AActor& Actor)
	{
		// World->DestroyActor가 EndPlay + 정리. Lua는 호출 후 해당 액터를 더 참조하지 말 것.
		if (UWorld* W = Actor.GetWorld()) W->DestroyActor(&Actor);
	},

		"IsValid", [](AActor* Actor)
	{
		// Lua가 보유한 actor 핸들이 cpp 측에서 destroy됐는지 확인. nil/destroyed면 false.
		// IsAliveObject가 아니라 IsValid여야 한다 — DestroyActor는 MarkPendingKill만 하고
		// 메모리는 GC까지 살아 있어서, PendingKill을 안 보면 destroy 직후 true가 나온다
		// (빔이 잡은 래그돌을 트럭이 수거할 때 UAF 크래시의 원인이었음).
		return Actor != nullptr && IsValid(Actor);
	},

		"HasTag", [](AActor& Actor, const FString& Tag)
	{
		return Actor.HasTag(FName(Tag));
	},
		"AddTag", [](AActor& Actor, const FString& Tag)
	{
		Actor.AddTag(FName(Tag));
	},
		"RemoveTag", [](AActor& Actor, const FString& Tag)
	{
		Actor.RemoveTag(FName(Tag));
	},

		"GetFloatingPawnMovement", [](AActor& Actor)
	{
		return Actor.GetComponentByClass<UFloatingPawnMovementComponent>();
	},

		"GetCamera", [](AActor& Actor)
	{
		return Actor.GetComponentByClass<UCameraComponent>();
	},

		"GetActionComponent", [](AActor& Actor)
	{
		return Actor.GetComponentByClass<UActionComponent>();
	},

		"GetRootPrimitiveComponent", [](AActor& Actor) -> UPrimitiveComponent*
	{
		return Cast<UPrimitiveComponent>(Actor.GetRootComponent());
	},

		"GetPrimitiveComponent", [](AActor& Actor) -> UPrimitiveComponent*
	{
		return Actor.GetComponentByClass<UPrimitiveComponent>();
	},

	"GetPrimitiveComponentByName", [](AActor& Actor, const FString& ComponentName) -> UPrimitiveComponent*
	{
		for (UActorComponent* Component : Actor.GetComponents())
		{
			UPrimitiveComponent* PrimitiveComponent = Cast<UPrimitiveComponent>(Component);
			if (PrimitiveComponent && PrimitiveComponent->GetFName().ToString() == ComponentName)
			{
				return PrimitiveComponent;
			}
		}
		return nullptr;
	},

		"GetPrimitiveComponents", [](AActor& Actor, sol::this_state State)
	{
		sol::state_view L(State);
		sol::table Result = L.create_table();
		int32 Index = 1;
		for (UPrimitiveComponent* Component : Actor.GetPrimitiveComponents())
		{
			if (IsValid(Component))
			{
				Result[Index++] = Component;
			}
		}
		return Result;
	},

		"GetComponentByName", [](AActor& Actor, const FString& ComponentName) -> USceneComponent*
	{
		for (UActorComponent* Component : Actor.GetComponents())
		{
			USceneComponent* SceneComponent = Cast<USceneComponent>(Component);
			if (SceneComponent && SceneComponent->GetFName().ToString() == ComponentName)
			{
				return SceneComponent;
			}
		}
		return nullptr;
	},

		"AsPawn", [](AActor& Actor) -> APawn*
	{
		return Cast<APawn>(&Actor);
	},

		"AsCharacter", [](AActor& Actor) -> ACharacter*
	{
		return Cast<ACharacter>(&Actor);
	},

		"UUID", sol::property([](AActor& Actor)
	{
		return Actor.GetUUID();
	}),

		"Name", sol::property([](AActor& Actor)
	{
		return Actor.GetFName().ToString();
	}));

	Lua.new_usertype<APawn>("Pawn",
		sol::base_classes,
		sol::bases<AActor, UObject>(),
		"IsPossessed", &APawn::IsPossessed,
		"SetAutoPossessPlayer", &APawn::SetAutoPossessPlayer,
		"GetAutoPossessPlayer", &APawn::GetAutoPossessPlayer,
		"GetInputComponent", &APawn::GetInputComponent);

	Lua.new_usertype<ACharacter>("Character",
		sol::base_classes,
		sol::bases<APawn, AActor, UObject>(),
		"AddMovementInput", &ACharacter::AddMovementInput,
		"Jump", &ACharacter::Jump,
		"EnterFullRagdoll", &ACharacter::EnterFullRagdoll);

	// UInputComponent — Pawn::GetInputComponent 로 얻어 lua 에서 직접 매핑/binding 추가 가능.
	// 예 (BeginPlay 안):
	//   local input = obj:AsPawn():GetInputComponent()
	//   input:AddActionMapping("Jump", 0x20)   -- VK_SPACE = 0x20
	//   input:BindAction("Jump", "Pressed", function() print("jump!") end)
	Lua.new_usertype<UInputComponent>("InputComponent",
		sol::base_classes,
		sol::bases<UActorComponent, UObject>(),
		"AddAxisMapping",   &UInputComponent::AddAxisMapping,
		"AddActionMapping", &UInputComponent::AddActionMapping,
		"BindAxis", [](UInputComponent& Self, const FString& Name, sol::protected_function Cb)
		{
			Self.BindAxis(Name, [Cb](float V)
			{
				auto R = Cb(V);
				if (!R.valid()) { sol::error e = R; UE_LOG("[Lua] BindAxis cb error: %s", e.what()); }
			});
		},
		"BindAction", [](UInputComponent& Self, const FString& Name, const FString& EventStr, sol::protected_function Cb)
		{
			const EInputEvent Ev = (EventStr == "Released") ? EInputEvent::Released : EInputEvent::Pressed;
			Self.BindAction(Name, Ev, [Cb]()
			{
				auto R = Cb();
				if (!R.valid()) { sol::error e = R; UE_LOG("[Lua] BindAction cb error: %s", e.what()); }
			});
		},
		"ClearBindings", &UInputComponent::ClearBindings);

	// --- World binding — 런타임 액터 spawn 용 (Engine 일반 기능) ---
	sol::table World = Lua.create_named_table("World");
	World.set_function("SpawnActor", [](const FString& ClassName) -> AActor*
	{
		if (!GEngine) return nullptr;
		UWorld* W = GEngine->GetWorld();
		if (!W) return nullptr;
		UClass* Cls = UClass::FindByName(ClassName.c_str());
		if (!Cls) return nullptr;
		return W->SpawnActorByClass(Cls);
	});
	World.set_function("FindActorByName", [](const FString& ActorName) -> AActor*
	{
		if (!GEngine || !GEngine->GetWorld()) return nullptr;
		UWorld* W = GEngine->GetWorld();
		for (AActor* Actor : W->GetActors())
		{
			if (IsValid(Actor) && Actor->GetFName().ToString() == ActorName)
			{
				return Actor;
			}
		}
		return nullptr;
	});
	World.set_function("FindFirstActorByClass", [](const FString& ClassName) -> AActor*
	{
		if (!GEngine || !GEngine->GetWorld()) return nullptr;
		UWorld* W = GEngine->GetWorld();
		UClass* Cls = UClass::FindByName(ClassName.c_str());
		if (!Cls) return nullptr;
		for (AActor* Actor : W->GetActors())
		{
			if (IsValid(Actor) && Actor->GetClass()->IsA(Cls))
			{
				return Actor;
			}
		}
		return nullptr;
	});
	World.set_function("FindFirstActorByTag", [](const FString& Tag) -> AActor*
	{
		return FGameplayStatics::FindFirstActorByTag(
			GEngine ? GEngine->GetWorld() : nullptr, FName(Tag));
	});
	World.set_function("FindActorsByTag", [](const FString& Tag) -> sol::table
	{
		sol::table Result = FLuaScriptManager::GetState().create_table();
		const TArray<AActor*> Found = FGameplayStatics::FindActorsByTag(
			GEngine ? GEngine->GetWorld() : nullptr, FName(Tag));
		int Idx = 1; // Lua arrays are 1-indexed
		for (AActor* Actor : Found)
		{
			Result[Idx++] = Actor;
		}
		return Result;
	});
	// LuaBlueprint ForEachActorByClass 노드용 — 동일 패턴(table 반환)으로 노출.
	World.set_function("FindActorsByClass", [](const FString& ClassName) -> sol::table
	{
		sol::table Result = FLuaScriptManager::GetState().create_table();
		if (!GEngine || !GEngine->GetWorld()) return Result;
		UClass* Cls = UClass::FindByName(ClassName.c_str());
		if (!Cls) return Result;
		int Idx = 1;
		for (AActor* Actor : GEngine->GetWorld()->GetActors())
		{
			if (IsValid(Actor) && Actor->GetClass() && Actor->GetClass()->IsA(Cls))
			{
				Result[Idx++] = Actor;
			}
		}
		return Result;
	});
	World.set_function("GetGameTime", []() -> float
	{
		UWorld* CurrentWorld = GEngine ? GEngine->GetWorld() : nullptr;
		return CurrentWorld ? CurrentWorld->GetGameTimeSeconds() : 0.0f;
	});
	World.set_function("LineTraceGround", [](const FVector& Start, const FVector& End, AActor* IgnoreActor, sol::this_state State) -> sol::object
	{
		sol::state_view LuaState(State);
		UWorld* CurrentWorld = GEngine ? GEngine->GetWorld() : nullptr;
		if (!CurrentWorld)
		{
			return sol::make_object(LuaState, sol::nil);
		}

		const FVector Delta = End - Start;
		const float MaxDist = Delta.Length();
		if (MaxDist <= 1.0e-6f)
		{
			return sol::make_object(LuaState, sol::nil);
		}

		FHitResult Hit;
		const uint32 ObjectTypeMask =
			ObjectTypeBit(ECollisionChannel::WorldStatic) |
			ObjectTypeBit(ECollisionChannel::WorldDynamic);
		const bool bHit = CurrentWorld->PhysicsRaycastByObjectTypes(
			Start,
			Delta / MaxDist,
			MaxDist,
			Hit,
			ObjectTypeMask,
			IgnoreActor);

		if (!bHit)
		{
			return sol::make_object(LuaState, sol::nil);
		}

		return sol::make_object(LuaState, Hit);
	});
	World.set_function("PhysicsRaycast", &LuaPhysicsRaycast);
	World.set_function("Raycast", &LuaPhysicsRaycast);

	// 게임 특화 usertype/enum/global(GetGameState 등) 은 Game 모듈의
	// RegisterGameLuaBindings 가 등록한다. 호출 순서는 GameEngine/EditorEngine::Init
	// 에서 UEngine::Init() 직후.
}

void FLuaScriptManager::RegisterUIBindings(sol::state& Lua)
{
	Lua.new_usertype<UUserWidget>("UserWidget",
		sol::base_classes,
		sol::bases<UObject>(),
		"AddToViewport", [](UUserWidget& Widget)
	{
		Widget.AddToViewport();
	},
		"AddToViewportZ", [](UUserWidget& Widget, int32 ZOrder)
	{
		Widget.AddToViewport(ZOrder);
	},
		"RemoveFromParent", &UUserWidget::RemoveFromParent,
		"Show", [](UUserWidget& Widget)
	{
		Widget.AddToViewport();
	},
		"Hide", &UUserWidget::RemoveFromParent,
		"show", [](UUserWidget& Widget)
	{
		Widget.AddToViewport();
	},
		"hide", &UUserWidget::RemoveFromParent,
		"IsInViewport", &UUserWidget::IsInViewport,
		"bind_click", [](UUserWidget& Widget, const FString& ElementId, sol::protected_function Callback)
	{
		Widget.BindClick(ElementId, Callback);
	},
		"bind_hover", [](UUserWidget& Widget, const FString& ElementId, sol::protected_function Callback)
	{
		Widget.BindHover(ElementId, Callback);
	},
		"SetText", &UUserWidget::SetText,
		"set_text", &UUserWidget::SetText,
		"SetProperty", &UUserWidget::SetProperty,
		"set_property", &UUserWidget::SetProperty,
		"SetAttribute", &UUserWidget::SetAttribute,
		"set_attribute", &UUserWidget::SetAttribute,
		"GetValue", &UUserWidget::GetValue,
		"get_value", &UUserWidget::GetValue,
		"SetValue", &UUserWidget::SetValue,
		"set_value", &UUserWidget::SetValue,
		"SetWantsMouse", &UUserWidget::SetWantsMouse,
		"WantsMouse", &UUserWidget::WantsMouse);

	sol::table UI = Lua.create_named_table("UI");
	UI.set_function("CreateWidget", [](const FString& DocumentPath)
	{
		return UUIManager::Get().CreateWidget(nullptr, DocumentPath);
	});
}
