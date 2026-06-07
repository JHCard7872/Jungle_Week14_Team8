#include "ParticleModuleRotation.h"
#include "Particles/ParticleHelper.h"
#include "Particles/ParticleEmitterInstances.h"
#include "Math/MathUtils.h"
#include "Serialization/Archive.h"
#include <cstdlib>

namespace
{
	constexpr float TurnsToRadians = 6.2831853f; // 1턴 = 2π 라디안
}

UParticleModuleRotation::UParticleModuleRotation()
{
	bSpawnModule = true;
	bUpdateModule = false;
}

void UParticleModuleRotation::Spawn(const FSpawnContext& Context)
{
	SPAWN_INIT;
	const float Alpha = (float)rand() / (float)RAND_MAX;
	Particle.Rotation += FMath::Lerp(RotationMin, RotationMax, Alpha) * TurnsToRadians;
}

void UParticleModuleRotation::Serialize(FArchive& Ar)
{
	UParticleModule::Serialize(Ar);

	int32 Version = 0;
	Ar << Version;

	Ar << RotationMin;
	Ar << RotationMax;
}
