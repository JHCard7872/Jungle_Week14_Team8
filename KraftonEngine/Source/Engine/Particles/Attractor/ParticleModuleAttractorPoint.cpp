#include "ParticleModuleAttractorPoint.h"
#include "Particles/ParticleHelper.h"
#include "Particles/ParticleEmitterInstances.h"
#include "Serialization/Archive.h"
#include <cmath>

UParticleModuleAttractorPoint::UParticleModuleAttractorPoint()
{
	bSpawnModule = false;
	bUpdateModule = true;
}

void UParticleModuleAttractorPoint::Update(const FUpdateContext& Context)
{
	const FVector Center = Context.Owner.Location;

	BEGIN_UPDATE_LOOP
	{
		const FVector ToCenter = FVector(
			Center.X - Particle.Location.X,
			Center.Y - Particle.Location.Y,
			Center.Z - Particle.Location.Z);
		const float Dist = ToCenter.Length();

		// 주의: BEGIN_UPDATE_LOOP 안에서 continue 금지 — END의 오프셋 리셋을 건너뛴다.
		if (KillRadius > 0.0f && Dist < KillRadius)
		{
			Particle.RelativeTime = 1.1f;   // 다음 자연사 스윕에서 정리
		}
		else if (Dist > 0.0001f)
		{
			const FVector Accel = ToCenter * (Strength / Dist);
			Particle.BaseVelocity = Particle.BaseVelocity + Accel * DeltaTime;
			Particle.Velocity = Particle.BaseVelocity;
		}
	}
	END_UPDATE_LOOP
}

void UParticleModuleAttractorPoint::Serialize(FArchive& Ar)
{
	UParticleModule::Serialize(Ar);

	int32 Version = 0;
	Ar << Version;

	Ar << Strength;
	Ar << KillRadius;
}
