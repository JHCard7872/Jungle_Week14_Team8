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

	constexpr int32 ShaftCount = 30;
	constexpr float ShaftRingRadius = 2.05f; // FX_StrangePortal 바닥 링(Radius 2.0~2.1) 위에 걸치는 값
	constexpr float ShaftWidth = 0.6f;   // 쿼드 폭 스케일 — 이웃과 살짝 겹치게
	constexpr float ShaftHeight = 3.5f;  // 쿼드 높이 스케일
	constexpr float ShaftPitchDeg = 13.0f;   // 기둥 기울임 — 위가 바깥으로 벌어지는 콘. 반대면 부호 뒤집기
	constexpr float RingYawSpeedDeg = 60.0f; // 초당 회전 각도
}

void ASummonPortalActor::InitDefaultComponents()
{
	AddTag(FName("Portal"));   // MinimapController가 태그로 찾는다 (TrashBox와 동일 규약)

	// 1) Root — 액터 위치가 곧 소환진 바닥 중심
	USceneComponent* Root = AddComponent<USceneComponent>();
	Root->SetFName(FName("SummonPortalRoot"));
	SetRootComponent(Root);

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
	Rotator->SetFName(FName("RingRotator"));
	Rotator->SetRotationInLocalSpace(true);
	Rotator->SetRotationRate(FRotator(0.0f, RingYawSpeedDeg, 0.0f));

	// 4) 바닥 파티클 (FX_StrangePortal) — 빛기둥은 메시가 맡는다
	UParticleSystemComponent* Particle = AddComponent<UParticleSystemComponent>();
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

	// 6) LuaScript — 수거(점수/미션/소멸) 처리 전부 Lua에서.
	ULuaScriptComponent* Script = AddComponent<ULuaScriptComponent>();
	Script->SetScriptFile(CollectorLuaScriptFile);
}
