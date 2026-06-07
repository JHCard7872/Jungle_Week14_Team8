#include "ParticleModuleEventReceiverSpawn.h"
#include "Component/Primitive/ParticleSystemComponent.h"
#include "Particles/ParticleEmitterInstances.h"
#include "Particles/ParticleHelper.h"
#include "Serialization/Archive.h"
#include <cstdlib>

UParticleModuleEventReceiverSpawn::UParticleModuleEventReceiverSpawn()
{
	bSpawnModule = false;
	bUpdateModule = true;
}

void UParticleModuleEventReceiverSpawn::Update(const FUpdateContext& Context)
{
	UParticleSystemComponent* OwnerComponent = Context.Owner.Component;
	if (!OwnerComponent)
	{
		return;
	}

	const FName NameFilter(EventNameFilter);

	for (const FParticleEventData& Event : OwnerComponent->ParticleEvents)
	{
		const bool bTypeMatch =
			(Event.Type == static_cast<int32>(EParticleEventType::Spawn) && bAcceptSpawnEvents) ||
			(Event.Type == static_cast<int32>(EParticleEventType::Death) && bAcceptDeathEvents);
		if (!bTypeMatch)
		{
			continue;
		}
		if (!(Event.EventName == NameFilter))
		{
			continue;
		}

		int32 Count = SpawnCountMin;
		if (SpawnCountMax > SpawnCountMin)
		{
			Count += rand() % (SpawnCountMax - SpawnCountMin + 1);
		}
		if (Count <= 0)
		{
			continue;
		}

		// 이벤트 위치에서 직접 스폰 — Spawn 모듈 체인(수명/크기/색)이 내부에서 적용된다
		Context.Owner.SpawnParticles(
			Count,
			0.0f,
			0.0f,
			Event.Location,
			Event.Velocity * InheritVelocityScale);
	}
}

void UParticleModuleEventReceiverSpawn::Serialize(FArchive& Ar)
{
	Super::Serialize(Ar);

	int32 Version = 0;
	Ar << Version;

	Ar << bAcceptSpawnEvents;
	Ar << bAcceptDeathEvents;
	Ar << EventNameFilter;
	Ar << SpawnCountMin;
	Ar << SpawnCountMax;
	Ar << InheritVelocityScale;
}
