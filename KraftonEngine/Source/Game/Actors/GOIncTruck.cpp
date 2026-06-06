#include "Game/Actors/GOIncTruck.h"

#include "Component/Primitive/StaticMeshComponent.h"
#include "Component/SceneComponent.h"
#include "Component/Script/LuaScriptComponent.h"
#include "Component/Shape/BoxComponent.h"
#include "Core/Types/CollisionTypes.h"
#include "Mesh/MeshManager.h"
#include "Runtime/Engine.h"

namespace
{
	const FString TruckStaticMeshPath = "Content/Data/Truck/Truck_StaticMesh.uasset";
	const FString TruckLuaScriptFile = "TruckBehavior.lua";
}

void AGOIncTruck::InitDefaultComponents()
{
	AddTag(FName("Truck"));

	// 1) Root — 메시/트리거를 형제로 묶는 기준점. TruckBehavior가 액터 단위로 이동/회전한다.
	USceneComponent* Root = AddComponent<USceneComponent>();
	Root->SetFName(FName("TruckRoot"));
	SetRootComponent(Root);

	// 2) TruckMesh — 시각 표현만 담당, 충돌 없음. 머티리얼은 메시 기본 슬롯(Truck/Glass.mat)을 그대로 쓴다.
	UStaticMeshComponent* Mesh = AddComponent<UStaticMeshComponent>();
	Mesh->SetFName(FName("TruckMesh"));
	Mesh->AttachToComponent(Root);
	Mesh->SetRelativeScale(FVector(2.0f, 2.0f, 2.0f));
	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	if (GEngine)
	{
		ID3D11Device* Device = GEngine->GetRenderer().GetFD3DDevice().GetDevice();
		if (UStaticMesh* Loaded = FMeshManager::LoadStaticMesh(TruckStaticMeshPath, Device))
		{
			Mesh->SetStaticMesh(Loaded);
		}
	}

	// 3) CollectTrigger — 적재함 위 수거 판정 박스.
	//    씬 저장값은 extent×비균등 스케일이었는데, 같은 크기를 extent에 구워서 스케일은 1로 둔다.
	UBoxComponent* Trigger = AddComponent<UBoxComponent>();
	Trigger->SetFName(FName("CollectTrigger"));
	Trigger->AttachToComponent(Root);
	Trigger->SetRelativeLocation(FVector(-1.1f, 0.0f, 2.7f));
	Trigger->SetBoxExtent(FVector(5.264f, 2.179f, 0.482f));
	Trigger->SetSimulatePhysics(false);
	Trigger->SetKinematicPhysics(true);
	Trigger->SetGenerateOverlapEvents(true);
	Trigger->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	Trigger->SetCollisionObjectType(ECollisionChannel::Trigger);
	Trigger->SetCollisionResponseToAllChannels(ECollisionResponse::Overlap);

	// 4) LuaScript — 대기↔순회 주행과 수거 처리 전부 Lua에서.
	ULuaScriptComponent* Script = AddComponent<ULuaScriptComponent>();
	Script->SetScriptFile(TruckLuaScriptFile);
}
