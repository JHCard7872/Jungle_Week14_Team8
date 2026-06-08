#include "BobbingMovementComponent.h"

#include "Component/SceneComponent.h"
#include "Math/MathUtils.h"

#include "Object/Reflection/ObjectFactory.h"
#include "Serialization/Archive.h"

#include <cmath>

void UBobbingMovementComponent::BeginPlay()
{
	UMovementComponent::BeginPlay();
	ElapsedTime = 0.0f;

	if (USceneComponent* Target = GetUpdatedComponent())
	{
		InitialRelativeLocation = Target->GetRelativeLocation();
	}
}

void UBobbingMovementComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction& ThisTickFunction)
{
	UMovementComponent::TickComponent(DeltaTime, TickType, ThisTickFunction);

	USceneComponent* Target = GetUpdatedComponent();
	if (!Target)
	{
		return;
	}

	ElapsedTime += DeltaTime;

	// offset = Amplitude * sin(2π * Frequency * t + Phase)
	const float PhaseRad = Phase * FMath::DegToRad;
	const float Offset = Amplitude * std::sin(2.0f * FMath::Pi * Frequency * ElapsedTime + PhaseRad);

	FVector NewLocation = InitialRelativeLocation;
	NewLocation.Z += Offset;
	Target->SetRelativeLocation(NewLocation);
}
