#include "ParticleModuleLocationRing.h"
#include "Component/Primitive/ParticleSystemComponent.h"
#include "Particles/ParticleHelper.h"
#include "Particles/ParticleEmitterInstances.h"
#include "Math/MathUtils.h"
#include "Serialization/Archive.h"
#include <cmath>
#include <cstdlib>

namespace
{
	constexpr float TwoPi = 6.2831853f;

	float RandomUnit()
	{
		return (float)rand() / (float)RAND_MAX;
	}
}

UParticleModuleLocationRing::UParticleModuleLocationRing()
{
	bSpawnModule = true;
	bUpdateModule = false;
}

void UParticleModuleLocationRing::Spawn(const FSpawnContext& Context)
{
	SPAWN_INIT;

	float Theta;
	if (bSequentialAngle && Context.Owner.Component)
	{
		// 회전하는 헤드 — 월드 시계 기준이라 에미터 루프(EmitterTime 리셋)와 무관하게 연속.
		// SpawnTime(틱 내 출생 시점 보간)을 빼서 같은 틱에 태어난 입자들도 경로 위에 고르게 깔린다
		const float HeadTime = Context.Owner.Component->GetWorldTimeSeconds() - Context.SpawnTime;
		Theta = HeadTime * AngleTurnsPerSecond * TwoPi;
	}
	else
	{
		Theta = RandomUnit() * TwoPi;
	}
	const float Radius = FMath::Lerp(RadiusMin, RadiusMax, RandomUnit());
	const float PlaneA = cosf(Theta) * Radius;
	const float PlaneB = sinf(Theta) * Radius;
	const float Normal = (RandomUnit() - 0.5f) * Thickness;

	// 평면 좌표(A,B)와 법선(N)을 선택 축에 매핑 — 로테이터 컨벤션(X:Roll, Y:Pitch, Z:Yaw)
	FVector LocalOffset;
	if (AxisNormal == 0)
	{
		LocalOffset = FVector(Normal, PlaneA, PlaneB);   // YZ 평면 링 (세로 포탈)
	}
	else if (AxisNormal == 1)
	{
		LocalOffset = FVector(PlaneA, Normal, PlaneB);   // XZ 평면 링
	}
	else
	{
		LocalOffset = FVector(PlaneA, PlaneB, Normal);   // XY 평면 링 (바닥)
	}

	// 에미터 회전을 통과시켜 액터 배치 방향을 따라가게 한다 (VortexRotation과 동일 정책)
	const FVector WorldOffset = Context.Owner.EmitterToSimulation.TransformVector(LocalOffset);
	Particle.Location = Particle.Location + WorldOffset;
}

void UParticleModuleLocationRing::Serialize(FArchive& Ar)
{
	UParticleModule::Serialize(Ar);

	int32 Version = 1; // v1: bSequentialAngle/AngleTurnsPerSecond 추가
	Ar << Version;

	Ar << RadiusMin;
	Ar << RadiusMax;
	Ar << AxisNormal;
	Ar << Thickness;

	if (Version >= 1)
	{
		Ar << bSequentialAngle;
		Ar << AngleTurnsPerSecond;
	}
}
