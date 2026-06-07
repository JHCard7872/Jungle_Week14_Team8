#include "ParticleModuleAcceleration.h"
#include "Particles/ParticleHelper.h"
#include "Particles/ParticleEmitterInstances.h"
#include "Serialization/Archive.h"

UParticleModuleAcceleration::UParticleModuleAcceleration()
{
	bSpawnModule = false;
	bUpdateModule = true;
}

void UParticleModuleAcceleration::Update(const FUpdateContext& Context)
{
	BEGIN_UPDATE_LOOP
	{
		Particle.BaseVelocity = Particle.BaseVelocity + Acceleration * DeltaTime;
		Particle.Velocity = Particle.BaseVelocity;
	}
	END_UPDATE_LOOP
}

void UParticleModuleAcceleration::Serialize(FArchive& Ar)
{
	UParticleModule::Serialize(Ar);

	int32 Version = 0;
	Ar << Version;

	Ar << Acceleration;
}
