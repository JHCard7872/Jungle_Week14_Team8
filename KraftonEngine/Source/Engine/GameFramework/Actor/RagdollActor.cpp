#include "GameFramework/Actor/RagdollActor.h"

#include <random>

#include "Animation/AnimationMode.h"
#include "Animation/Instance/CharacterAnimInstance.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Mesh/MeshManager.h"
#include "Runtime/Engine.h"

void ARagdollActor::BeginPlay()
{
	Super::BeginPlay();
}

void ARagdollActor::InitDefaultComponents(const FString& SkeletalMeshFileName)
{
	if (!SkeletalMeshComponent)
	{
		SkeletalMeshComponent = AddComponent<USkeletalMeshComponent>();
		SetRootComponent(SkeletalMeshComponent);
	}

	const FString SelectedMeshFileName = SkeletalMeshFileName.empty()
		? SelectInitialSkeletalMeshFileName()
		: SkeletalMeshFileName;

	const bool bApplied = ApplySkeletalMeshFileName(SelectedMeshFileName);
	ApplyRagdollStartupOptions();

	if (bApplied && bAutoActivateRagdoll)
	{
		ActivateRagdoll();
	}
}

void ARagdollActor::ActivateRagdoll()
{
	ResolveComponents();
	ApplyRagdollStartupOptions();

	if (SkeletalMeshComponent)
	{
		SkeletalMeshComponent->SetRagdollEnabled(true);
		SkeletalMeshComponent->WakeAllRagdollBodies();
	}
}

void ARagdollActor::DeactivateRagdoll()
{
	if (SkeletalMeshComponent)
	{
		SkeletalMeshComponent->SetRagdollEnabled(false);
	}
}

void ARagdollActor::SetSkeletalMeshFileName(const FString& InSkeletalMeshFileName)
{
	ResolveComponents();

	const bool bWasRagdollActive = SkeletalMeshComponent && SkeletalMeshComponent->IsRagdollEnabled();
	if (bWasRagdollActive)
	{
		SkeletalMeshComponent->SetRagdollEnabled(false);
	}

	const bool bApplied = ApplySkeletalMeshFileName(InSkeletalMeshFileName);
	ApplyRagdollStartupOptions();

	if (bApplied && bAutoActivateRagdoll)
	{
		ActivateRagdoll();
	}
}

void ARagdollActor::OnOwnedComponentRemoved(UActorComponent* Component)
{
	Super::OnOwnedComponentRemoved(Component);

	if (Component == SkeletalMeshComponent)
	{
		SkeletalMeshComponent = nullptr;
	}
}

void ARagdollActor::PostDuplicate()
{
	Super::PostDuplicate();
	ResolveComponents();
	ApplyRagdollStartupOptions();
}

FString ARagdollActor::SelectInitialSkeletalMeshFileName() const
{
	std::vector<const FString*> Candidates;

	const FString* MeshFiles[] =
	{
		&InitialSkeletalMeshFileName,
		&RandomSkeletalMeshFileName1,
		/*&RandomSkeletalMeshFileName2,
		&RandomSkeletalMeshFileName3,
		&RandomSkeletalMeshFileName4,*/
	};

	for (const FString* MeshFile : MeshFiles)
	{
		if (MeshFile && !MeshFile->empty())
		{
			Candidates.push_back(MeshFile);
		}
	}

	if (Candidates.empty())
	{
		return FString();
	}

	static std::random_device RandomDevice;
	static std::mt19937 RandomEngine(RandomDevice());

	std::uniform_int_distribution<size_t> Distribution(0, Candidates.size() - 1);
	return *Candidates[Distribution(RandomEngine)];
}

void ARagdollActor::ResolveComponents()
{
	SkeletalMeshComponent = Cast<USkeletalMeshComponent>(GetRootComponent());
	if (!SkeletalMeshComponent)
	{
		SkeletalMeshComponent = GetComponentByClass<USkeletalMeshComponent>();
	}
}

bool ARagdollActor::ApplySkeletalMeshFileName(const FString& SkeletalMeshFileName)
{
	if (SkeletalMeshFileName.empty())
	{
		return false;
	}

	ResolveComponents();
	if (!GEngine || !SkeletalMeshComponent)
	{
		return false;
	}

	ID3D11Device* Device = GEngine->GetRenderer().GetFD3DDevice().GetDevice();
	USkeletalMesh* Asset = FMeshManager::LoadSkeletalMesh(SkeletalMeshFileName, Device);
	if (!Asset)
	{
		return false;
	}

	SkeletalMeshComponent->SetSkeletalMesh(Asset);

	// 순수 Ragdoll Actor이므로 기본은 ref/local pose 기준으로 물리 바디를 만든다.
	// 애니메이션이 필요하면 외부에서 AnimationMode/AnimInstance를 별도로 설정하면 된다.
	SkeletalMeshComponent->SetAnimInstanceClass(UCharacterAnimInstance::StaticClass());
	SkeletalMeshComponent->SetAnimationMode(EAnimationMode::AnimationCustom);
	return true;
}

void ARagdollActor::ApplyRagdollStartupOptions()
{
	if (SkeletalMeshComponent)
	{
		SkeletalMeshComponent->SetRagdollSelfCollisionMode(ERagdollSelfCollisionMode::DisableParentChild);
		SkeletalMeshComponent->SetRagdollGravityEnabled(bRagdollGravity);
	}
}
