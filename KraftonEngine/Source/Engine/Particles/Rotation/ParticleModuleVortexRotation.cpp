#include "ParticleModuleVortexRotation.h"
#include "Particles/ParticleHelper.h"
#include "Particles/ParticleEmitterInstances.h"
#include "Math/MathUtils.h"
#include "Serialization/Archive.h"
#include <cmath>
#include <cstdlib>

namespace
{
	constexpr float TurnsToRadians = 6.2831853f; // 1턴 = 2π 라디안
}

UParticleModuleVortexRotation::UParticleModuleVortexRotation()
{
	bSpawnModule = true;
	bUpdateModule = true;
}

uint32 UParticleModuleVortexRotation::RequiredBytes(UParticleModuleTypeDataBase* TypeData)
{
	return sizeof(FVortexRotationPayload);
}

void UParticleModuleVortexRotation::Spawn(const FSpawnContext& Context)
{
	SPAWN_INIT;
	PARTICLE_ELEMENT(FVortexRotationPayload, Payload);
	const float Alpha = (float)rand() / (float)RAND_MAX;
	Payload.RadiansPerSecond = FMath::Lerp(TurnsPerSecondMin, TurnsPerSecondMax, Alpha) * TurnsToRadians;
}

void UParticleModuleVortexRotation::Update(const FUpdateContext& Context)
{
	const FVector Center = Context.Owner.Location;

	// 회전축 — 로테이터 컨벤션(X:Roll, Y:Pitch, Z:Yaw)의 로컬 축을 에미터 회전에 통과시켜
	// 월드 축으로 변환한다. 액터를 세우면(예: 정면 포탈) 와류도 같이 선다.
	FVector LocalAxis = FVector(0.0f, 0.0f, 1.0f); // 기본 Yaw(Z)
	if (RotationAxis == 0)
	{
		LocalAxis = FVector(1.0f, 0.0f, 0.0f);     // Roll(X)
	}
	else if (RotationAxis == 1)
	{
		LocalAxis = FVector(0.0f, 1.0f, 0.0f);     // Pitch(Y)
	}
	FVector Axis = Context.Owner.EmitterToSimulation.TransformVector(LocalAxis);
	const float AxisLength = Axis.Length();
	if (AxisLength <= 0.0001f)
	{
		return;
	}
	Axis = Axis * (1.0f / AxisLength);

	BEGIN_UPDATE_LOOP
	{
		PARTICLE_ELEMENT(FVortexRotationPayload, Payload);

		const float Theta = Payload.RadiansPerSecond * DeltaTime;
		const float S = sinf(Theta);
		const float C = cosf(Theta);
		const float OneMinusC = 1.0f - C;

		// 로드리게스 회전: v' = v·cosθ + (k×v)·sinθ + k·(k·v)·(1−cosθ)
		const FVector Rel = FVector(
			Particle.Location.X - Center.X,
			Particle.Location.Y - Center.Y,
			Particle.Location.Z - Center.Z);
		const FVector RelRot = Rel * C + Axis.Cross(Rel) * S + Axis * (Axis.Dot(Rel) * OneMinusC);
		Particle.Location.X = Center.X + RelRot.X;
		Particle.Location.Y = Center.Y + RelRot.Y;
		Particle.Location.Z = Center.Z + RelRot.Z;

		// 속도 벡터도 같이 회전 — 방사(흡입/확산) 방향이 와류를 따라 돌게 한다.
		// 매 틱 리셋 루프가 Velocity = BaseVelocity로 복원하므로 Base를 돌리고 둘 다 갱신.
		const FVector Vel = Particle.BaseVelocity;
		const FVector VelRot = Vel * C + Axis.Cross(Vel) * S + Axis * (Axis.Dot(Vel) * OneMinusC);
		Particle.BaseVelocity = VelRot;
		Particle.Velocity = VelRot;
	}
	END_UPDATE_LOOP
}

void UParticleModuleVortexRotation::Serialize(FArchive& Ar)
{
	UParticleModule::Serialize(Ar);

	int32 Version = 1; // v1: RotationAxis 추가
	Ar << Version;

	Ar << TurnsPerSecondMin;
	Ar << TurnsPerSecondMax;

	if (Version >= 1)
	{
		Ar << RotationAxis;
	}
}
