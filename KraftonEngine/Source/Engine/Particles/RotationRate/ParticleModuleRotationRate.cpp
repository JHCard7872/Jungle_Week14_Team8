#include "ParticleModuleRotationRate.h"
#include "Particles/ParticleHelper.h"
#include "Particles/ParticleEmitterInstances.h"
#include "Math/MathUtils.h"
#include "Serialization/Archive.h"
#include <cstdlib>

namespace
{
	constexpr float TurnsToRadians = 6.2831853f; // 1턴 = 2π 라디안
}

UParticleModuleRotationRate::UParticleModuleRotationRate()
{
	bSpawnModule = true;
	bUpdateModule = false;
}

void UParticleModuleRotationRate::Spawn(const FSpawnContext& Context)
{
	SPAWN_INIT;
	const float Alpha = (float)rand() / (float)RAND_MAX;
	Particle.BaseRotationRate += FMath::Lerp(RotationRateMin, RotationRateMax, Alpha) * TurnsToRadians;
	Particle.RotationRate = Particle.BaseRotationRate;
}

void UParticleModuleRotationRate::Serialize(FArchive& Ar)
{
	UParticleModule::Serialize(Ar);

	int32 Version = 0;
	Ar << Version;

	Ar << RotationRateMin;
	Ar << RotationRateMax;
}
