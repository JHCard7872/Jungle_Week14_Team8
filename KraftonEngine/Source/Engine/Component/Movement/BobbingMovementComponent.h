#pragma once

#include "MovementComponent.h"
#include "Math/Vector.h"

#include "Source/Engine/Component/Movement/BobbingMovementComponent.generated.h"
// 시작 위치를 기준으로 Z축을 따라 위아래로 sin 왕복하는 이동 컴포넌트
// offset(t) = Amplitude * sin(2π * Frequency * t + Phase)
// 빌보드처럼 회전이 무시되는 대상에서도 위치 왕복은 그대로 보인다.
UCLASS()
class UBobbingMovementComponent : public UMovementComponent
{
public:
	GENERATED_BODY()
	UBobbingMovementComponent() = default;
	~UBobbingMovementComponent() override = default;

	void BeginPlay() override;
	void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction& ThisTickFunction) override;

	void SetAmplitude(float InAmplitude) { Amplitude = InAmplitude; }
	void SetFrequency(float InFrequency) { Frequency = InFrequency; }
	void SetPhase(float InPhase) { Phase = InPhase; }
private:
	UPROPERTY(Edit, Save, Category="Movement", DisplayName="Amplitude", Min=0.0f, Max=1000.0f, Speed=0.5f)
	float Amplitude  = 50.0f;	// 위아래 최대 이동 거리
	UPROPERTY(Edit, Save, Category="Movement", DisplayName="Frequency (Hz)", Min=0.01f, Max=10.0f, Speed=0.01f)
	float Frequency  = 0.5f;	// 초당 왕복 횟수 (Hz)
	UPROPERTY(Edit, Save, Category="Movement", DisplayName="Phase (deg)", Min=0.0f, Max=360.0f, Speed=1.0f)
	float Phase      = 0.0f;	// 초기 위상 (도)

	FVector InitialRelativeLocation;	// BeginPlay 시점 위치 (직렬화 제외)
	float ElapsedTime = 0.0f;	// 누적 시간 (직렬화 제외)
};
