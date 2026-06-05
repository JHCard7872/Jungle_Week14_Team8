#pragma once

#include "GameFramework/AActor.h"

#include "Source/Engine/GameFramework/Actor/RagdollActor.generated.h"

class USkeletalMeshComponent;

UCLASS()
class ARagdollActor : public AActor
{
public:
	GENERATED_BODY()

	ARagdollActor() = default;

	void BeginPlay() override;
	void PostDuplicate() override;

	void InitDefaultComponents(
		const FString& SkeletalMeshFileName = FString());

	UFUNCTION(Callable, Category = "Physics|Ragdoll")
	void ActivateRagdoll();

	UFUNCTION(Callable, Category = "Physics|Ragdoll")
	void DeactivateRagdoll();

	UFUNCTION(Callable, Category = "Mesh")
	void SetSkeletalMeshFileName(const FString& InSkeletalMeshFileName);

	UFUNCTION(Pure, Category = "Mesh")
	FString GetSkeletalMeshFileName() const { return InitialSkeletalMeshFileName; }

	UFUNCTION(Pure, Category = "Physics|Ragdoll")
	USkeletalMeshComponent* GetSkeletalMeshComponent() const { return SkeletalMeshComponent; }

protected:
	void OnOwnedComponentRemoved(UActorComponent* Component) override;

	virtual FString SelectInitialSkeletalMeshFileName() const;

private:
	void ResolveComponents();
	bool ApplySkeletalMeshFileName(const FString& SkeletalMeshFileName);
	void ApplyRagdollStartupOptions();

private:
	UPROPERTY(Edit, Save, Category = "RagdollActor", DisplayName = "Initial Skeletal Mesh File")
	FString InitialSkeletalMeshFileName = "Content/Data/Samba Dancing/Yeoul.fbx";

	UPROPERTY(Edit, Save, Category = "RagdollActor", DisplayName = "Random Skeletal Mesh File 1")
	FString RandomSkeletalMeshFileName1 = "Content/Data/Mario/Mario.fbx";

	UPROPERTY(Edit, Save, Category = "RagdollActor", DisplayName = "Random Skeletal Mesh File 2")
	FString RandomSkeletalMeshFileName2 = "";

	UPROPERTY(Edit, Save, Category = "RagdollActor", DisplayName = "Random Skeletal Mesh File 3")
	FString RandomSkeletalMeshFileName3 = "";

	UPROPERTY(Edit, Save, Category = "RagdollActor", DisplayName = "Random Skeletal Mesh File 4")
	FString RandomSkeletalMeshFileName4 = "";

	UPROPERTY(Edit, Save, Category = "Physics|Ragdoll", DisplayName = "Auto Activate Ragdoll")
	bool bAutoActivateRagdoll = true;

	UPROPERTY(Edit, Save, Category = "Physics|Ragdoll", DisplayName = "Ragdoll Gravity")
	bool bRagdollGravity = true;

	USkeletalMeshComponent* SkeletalMeshComponent = nullptr;
};
