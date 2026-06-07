#pragma once
#include "Particles/ParticleModule.h"

#include "Source/Engine/Particles/Size/ParticleModuleSizeOverLife.generated.h"

// ======================================================
// 수명에 따른 크기 스케일 (Update 매 틱) — 꼬리/연기처럼
// 시간이 갈수록 줄어들거나 커지는 입자를 만든다.
// 매 틱 리셋 루프가 Size = BaseSize로 복원한 뒤 호출되므로
// BaseSize × lerp(Start, End, RelativeTime)을 곱하기만 하면 된다.
// ======================================================
UCLASS()
class UParticleModuleSizeOverLife : public UParticleModule
{
public:
	GENERATED_BODY()
	UParticleModuleSizeOverLife();

	// 출생 시 크기 배율 (1 = BaseSize 그대로)
	UPROPERTY(EditAnywhere, Category = "Size")
	float ScaleStart = 1.0f;

	// 수명 끝 크기 배율 (0.1 = 10%까지 축소)
	UPROPERTY(EditAnywhere, Category = "Size")
	float ScaleEnd = 0.1f;

	virtual void Update(const FUpdateContext& Context) override;

	virtual void Serialize(FArchive& Ar) override;
};
