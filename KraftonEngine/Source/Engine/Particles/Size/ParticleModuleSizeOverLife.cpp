#include "ParticleModuleSizeOverLife.h"
#include "Particles/ParticleHelper.h"
#include "Particles/ParticleEmitterInstances.h"
#include "Math/MathUtils.h"
#include "Serialization/Archive.h"

UParticleModuleSizeOverLife::UParticleModuleSizeOverLife()
{
	bSpawnModule = false;
	bUpdateModule = true;
}

void UParticleModuleSizeOverLife::Update(const FUpdateContext& Context)
{
	BEGIN_UPDATE_LOOP
	{
		const float Alpha = FMath::Clamp(Particle.RelativeTime, 0.0f, 1.0f);
		const float Scale = ScaleStart + (ScaleEnd - ScaleStart) * Alpha;
		Particle.Size = Particle.Size * Scale;
	}
	END_UPDATE_LOOP
}

void UParticleModuleSizeOverLife::Serialize(FArchive& Ar)
{
	UParticleModule::Serialize(Ar);

	int32 Version = 0;
	Ar << Version;

	Ar << ScaleStart;
	Ar << ScaleEnd;
}
