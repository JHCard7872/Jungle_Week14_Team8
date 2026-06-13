#include "Game/Actors/SummonPortalActor.h"

#include "Component/Movement/RotatingMovementComponent.h"
#include "Component/Primitive/ParticleSystemComponent.h"
#include "Component/Primitive/StaticMeshComponent.h"
#include "Component/SceneComponent.h"
#include "Component/Script/LuaScriptComponent.h"
#include "Component/Shape/BoxComponent.h"
#include "Core/Logging/Log.h"
#include "Core/Types/CollisionTypes.h"
#include "Materials/MaterialManager.h"
#include "Math/MathUtils.h"
#include "Mesh/MeshManager.h"
#include "Particles/ParticleSystem.h"
#include "Particles/ParticleSystemManager.h"
#include "Runtime/Engine.h"

#include <string>

namespace
{
	const FString SummonPortalTemplatePath = "Content/Particle/FX_StrangePortal.uasset";
	const FString ShaftPlaneMeshPath = "Content/Data/BasicShape/Plane.obj";
	const FString ShaftMaterialPath = "Content/Material/FX_LightShaftMesh.mat";
	const FString CollectorLuaScriptFile = "PortalBehavior.lua";

	// 색상별 빛기둥 머티리얼 변형 (0=하늘 1=분홍 2=노랑). 인덱스가 범위 밖이면 기본 무색 사용.
	const FString ShaftMaterialByColor[3] = {
		"Content/Material/FX_LightShaftMesh_Cyan.mat",
		"Content/Material/FX_LightShaftMesh_Pink.mat",
		"Content/Material/FX_LightShaftMesh_Yellow.mat",
	};

	// 바닥 파티클(소환진) 색조 — 진한 채도. 빛기둥 머티리얼 Tint / 비네팅(PortalData.colors)과 맞춤.
	const FLinearColor PortalTint[3] = {
		FLinearColor(0.10f, 0.55f, 1.00f, 1.0f),  // 하늘
		FLinearColor(1.00f, 0.08f, 0.55f, 1.0f),  // 분홍
		FLinearColor(1.00f, 0.62f, 0.00f, 1.0f),  // 노랑
	};

	constexpr int32 ShaftCount = 80;   // 링 둘레 빛기둥 개수 — 클수록 빽빽

	constexpr float ShaftRingRadius = 2.05f; // FX_StrangePortal 바닥 링(Radius 2.0~2.1) 위에 걸치는 값
	constexpr float ShaftWidth = 0.6f;   // 쿼드 폭 스케일 — 이웃과 살짝 겹치게
	constexpr float ShaftHeight = 3.5f;  // 쿼드 높이 스케일
	constexpr float ShaftPitchDeg = 13.0f;   // 기둥 기울임 — 위가 바깥으로 벌어지는 콘. 반대면 부호 뒤집기
	constexpr float RingYawSpeedDeg = 60.0f; // 초당 회전 각도
}

void ASummonPortalActor::InitDefaultComponents()
{
	// 이미 구성됐으면(트리거 존재) 색만 보정하고 종료 — 배치/로드/스폰/BeginPlay가 모두 이 경로를
	// 거치므로 중복 구성을 막는다(멱등).
	if (GetComponentByClass<UBoxComponent>() != nullptr)
	{
		ApplyPortalColor();
		return;
	}

	AddTag(FName("Portal"));   // MinimapController가 태그로 찾는다 (TrashBox와 동일 규약)

	// 1) Root — 직렬화로 복원된 루트가 있으면 재사용, 없으면(코드 스폰/에디터 플레이스) 새로 만든다.
	//    최소 직렬화 액터는 RootComponent만 저장하고 나머지는 PostLoadSceneActor에서 여기로 보강한다.
	USceneComponent* Root = GetRootComponent();
	if (Root == nullptr)
	{
		USceneComponent* NewRoot = AddComponent<USceneComponent>();
		NewRoot->SetFName(FName("SummonPortalRoot"));
		SetRootComponent(NewRoot);
		Root = NewRoot;
	}

	// 2) 빛기둥 20개 — 링 둘레에 바깥을 보게 세운 가산 쿼드.
	//    머티리얼이 NoCull이라 안/밖 어느 쪽에서 봐도 보인다.
	UStaticMesh* PlaneMesh = nullptr;
	if (GEngine)
	{
		ID3D11Device* Device = GEngine->GetRenderer().GetFD3DDevice().GetDevice();
		PlaneMesh = FMeshManager::LoadStaticMesh(ShaftPlaneMeshPath, Device);
	}
	UMaterial* ShaftMaterial = FMaterialManager::Get().GetOrCreateMaterial(ShaftMaterialPath);

	if (PlaneMesh && ShaftMaterial)
	{
		for (int32 i = 0; i < ShaftCount; ++i)
		{
			const float AngleDeg = (360.0f / ShaftCount) * i;
			const float AngleRad = AngleDeg * FMath::DegToRad;

			UStaticMeshComponent* Shaft = AddComponent<UStaticMeshComponent>();
			Shaft->SetDoNotSerialize(true);   // 절차적 생성 — 씬에 굽지 않음(매 로드 코드가 재생성)
			Shaft->SetFName(FName(FString("LightShaft") + std::to_string(i)));
			Shaft->AttachToComponent(Root);
			Shaft->SetStaticMesh(PlaneMesh);
			Shaft->SetMaterial(0, ShaftMaterial);
			Shaft->SetCollisionEnabled(ECollisionEnabled::NoCollision);
			Shaft->SetCastShadow(false); // 빛기둥이 그림자를 드리우면 안 된다
			Shaft->SetRelativeLocation(FVector(
				ShaftRingRadius * std::cos(AngleRad),
				ShaftRingRadius * std::sin(AngleRad),
				0.0f));
			// 쿼드 법선(+X)을 반경 방향으로 — 폭이 링 접선을 따라 눕는다.
			// Pitch는 Yaw 후의 로컬 축 기준이라 각 기둥이 제 반경 방향으로 기운다.
			Shaft->SetRelativeRotation(FRotator(ShaftPitchDeg, AngleDeg, 0.0f));
			Shaft->SetRelativeScale(FVector(1.0f, ShaftWidth, ShaftHeight));
		}
	}
	else
	{
		UE_LOG("[SummonPortal] 빛기둥 리소스 로드 실패. Mesh=%s Material=%s",
			ShaftPlaneMeshPath.c_str(), ShaftMaterialPath.c_str());
	}

	// 3) 링 회전 — Root를 Z축 자전 (UpdatedComponent는 BeginPlay에서 Root 자동 등록)
	URotatingMovementComponent* Rotator = AddComponent<URotatingMovementComponent>();
	Rotator->SetDoNotSerialize(true);
	Rotator->SetFName(FName("RingRotator"));
	Rotator->SetRotationInLocalSpace(true);
	Rotator->SetRotationRate(FRotator(0.0f, RingYawSpeedDeg, 0.0f));

	// 4) 바닥 파티클 (FX_StrangePortal) — 빛기둥은 메시가 맡는다
	UParticleSystemComponent* Particle = AddComponent<UParticleSystemComponent>();
	Particle->SetDoNotSerialize(true);
	Particle->SetFName(FName("SummonPortalFX"));
	Particle->AttachToComponent(Root);

	if (UParticleSystem* Template = FParticleSystemManager::Get().Load(SummonPortalTemplatePath))
	{
		Particle->SetTemplate(Template);
	}
	else
	{
		UE_LOG("[SummonPortal] 파티클 로드 실패. Path=%s", SummonPortalTemplatePath.c_str());
	}

	// 5) CollectTrigger — 링 안쪽 수거 판정 박스 (Play.Scene 튜닝값을 extent에 구움).
	//    Root가 자전하므로 박스도 같이 돌지만 정사각이라 영향 미미.
	//    QueryOnly·Kinematic·GenerateOverlapEvents=true 조합 — 하나라도 빠지면
	//    OnOverlap이 안 와서 수거가 조용히 죽는다.
	UBoxComponent* Trigger = AddComponent<UBoxComponent>();
	Trigger->SetDoNotSerialize(true);
	Trigger->SetFName(FName("CollectTrigger"));
	Trigger->AttachToComponent(Root);
	Trigger->SetRelativeLocation(FVector(0.0f, 0.0f, 1.75f));
	Trigger->SetBoxExtent(FVector(1.4f, 1.4f, 1.75f));
	Trigger->SetSimulatePhysics(false);
	Trigger->SetKinematicPhysics(true);
	Trigger->SetGenerateOverlapEvents(true);
	Trigger->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	Trigger->SetCollisionObjectType(ECollisionChannel::Trigger);
	Trigger->SetCollisionResponseToAllChannels(ECollisionResponse::Overlap);

	// 6) LuaScript — 순간이동 트리거 처리 전부 Lua에서.
	ULuaScriptComponent* Script = AddComponent<ULuaScriptComponent>();
	Script->SetDoNotSerialize(true);
	Script->SetScriptFile(CollectorLuaScriptFile);

	// 7) 색 적용 — ColorIndex 기준 빛기둥 머티리얼 변형 + "PortalColor{N}" 태그.
	ApplyPortalColor();
}

// ColorIndex(0/1/2)로 색 태그와 빛기둥 머티리얼을 (재)적용. 배치/로드/스폰 어디서든 동일 결과.
void ASummonPortalActor::ApplyPortalColor()
{
	const int32 Idx = (ColorIndex >= 0 && ColorIndex < 3) ? ColorIndex : 0;

	// 색 태그 — 기존 PortalColorN을 싹 떼고 현재 색만 남긴다(페어링/미니맵/비네팅이 읽음).
	for (int32 i = 0; i < 3; ++i)
	{
		RemoveTag(FName(FString("PortalColor") + std::to_string(i)));
	}
	AddTag(FName(FString("PortalColor") + std::to_string(Idx)));

	// 빛기둥 머티리얼 — 이 액터의 모든 StaticMeshComponent(빛기둥)에 색 변형 적용.
	UMaterial* Mat = FMaterialManager::Get().GetOrCreateMaterial(ShaftMaterialByColor[Idx]);
	for (UActorComponent* Comp : GetComponents())
	{
		if (Mat != nullptr)
		{
			if (UStaticMeshComponent* SM = Cast<UStaticMeshComponent>(Comp))
			{
				SM->SetMaterial(0, Mat);
			}
		}
		// 바닥 파티클(소환진)도 같은 색조로 — 밝기/페이드는 유지한 채 색만 치환.
		if (UParticleSystemComponent* PSC = Cast<UParticleSystemComponent>(Comp))
		{
			PSC->SetColorScale(PortalTint[Idx]);
		}
	}
}

void ASummonPortalActor::BeginPlay()
{
	// 컴포넌트가 없으면(최소 직렬화/누락) 구성하고 색·태그 적용. Super보다 먼저 해야
	// LuaScriptComponent(PortalBehavior) BeginPlay가 PortalColor 태그를 읽을 수 있다.
	InitDefaultComponents();
	AActor::BeginPlay();
}

// 씬 로드(에디터 열기 + PIE) 직후 1회 — 최소 직렬화된 포탈을 완성해 에디터 뷰포트에도 보이게 한다.
void ASummonPortalActor::PostLoadSceneActor()
{
	InitDefaultComponents();
}

void ASummonPortalActor::PostEditProperty(const char* PropertyName)
{
	AActor::PostEditProperty(PropertyName);   // 태그 문자열 split 등 기본 처리
	ApplyPortalColor();                       // ColorIndex 변경을 에디터에서 즉시 반영
}
