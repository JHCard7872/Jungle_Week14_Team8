#include "MeshEditorViewportClient.h"

#include "Render/Types/MinimalViewInfo.h"
#include "Viewport/Viewport.h"
#include "Math/MathUtils.h"
#include "Input/InputSystem.h"
#include "Mesh/Skeletal/SkeletalMesh.h"
#include "Mesh/Skeletal/SkeletalMeshAsset.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Component/Debug/GizmoComponent.h"
#include "Component/Debug/SkeletalMeshDebugComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "Component/Debug/BoneDebugComponent.h"
#include "Component/Debug/PhysicsAssetDebugComponent.h"
#include "Collision/Ray/RayUtils.h"
#include "Physics/BodyInstance.h"
#include "PhysicsEngine/BodySetup.h"
#include "PhysicsEngine/PhysicsAsset.h"
#include "Settings/EditorSettings.h"
#include "Slate/SlateApplication.h"

#include <imgui.h>
#include <algorithm>
#include <cmath>
#include <utility>

void FMeshEditorViewportClient::Initialize(ID3D11Device* Device, uint32 Width, uint32 Height)
{
	Viewport = new FViewport();
	Viewport->Initialize(Device, Width, Height);
	Viewport->SetClient(this);

	bIsRenderable = true;
}


void FMeshEditorViewportClient::AddReferencedObjects(FReferenceCollector& Collector)
{
	Collector.AddReferencedObject(SelectedMesh);
	Collector.AddReferencedObject(Gizmo);
	Collector.AddReferencedObject(PreviewMeshComponent);
	Collector.AddReferencedObject(BoneDebugComponent);
	Collector.AddReferencedObject(PhysicsAssetDebugComponent);
	Collector.AddReferencedObject(PreviewWorld);
	Collector.AddReferencedObject(PreviewActor);
}

void FMeshEditorViewportClient::SetPreviewMeshComponent(USkeletalMeshDebugComponent* InComp)
{
	PreviewDebugMeshComponent = InComp;
	PreviewMeshComponent = InComp;

	if (BoneDebugComponent)
	{
		BoneDebugComponent->SetTargetMeshComponent(PreviewMeshComponent);
	}

	if (PhysicsAssetDebugComponent)
	{
		UPhysicsAsset* PhysicsAsset = PhysicsAssetDebugComponent->GetPhysicsAsset();
		const int32 SelectedBodyIndex = PhysicsAssetDebugComponent->GetSelectedBodyIndex();
		const int32 SelectedConstraintIndex = PhysicsAssetDebugComponent->GetSelectedConstraintIndex();
		SyncPhysicsAssetDebugComponent(PhysicsAsset, SelectedBodyIndex, SelectedConstraintIndex);
	}
}

void FMeshEditorViewportClient::Release()
{
	if (Viewport)
	{
		Viewport->Release();
		delete Viewport;
		Viewport = nullptr;
	}

	PreviewWorld = nullptr;
	PreviewActor = nullptr;
	PreviewDebugMeshComponent = nullptr;
	PreviewMeshComponent = nullptr;

	UObjectManager::Get().DestroyObject(Gizmo);
	Gizmo = nullptr;
	BoneDebugComponent = nullptr;
	PhysicsAssetDebugComponent = nullptr;
	PhysicsAssetShapeTarget.Clear();
	PhysicsAssetConstraintTarget.Clear();
	bPhysicsAssetPickingEnabled = false;
	SelectedPhysicsConstraintIndex = -1;
	EndRagdollBodyPan();
	OnPhysicsAssetBodyPicked = nullptr;
	OnPhysicsAssetConstraintPicked = nullptr;
	OnPhysicsAssetShapeEdited = nullptr;
	OnPhysicsAssetConstraintEdited = nullptr;

	bIsRenderable = false;

	SetSelectedBone(nullptr, -1);
}

void FMeshEditorViewportClient::CreatePreviewGizmo()
{
	Gizmo = UObjectManager::Get().CreateObject<UGizmoComponent>();
	Gizmo->SetScene(&PreviewWorld->GetScene());
	Gizmo->CreateRenderState();
	Gizmo->Deactivate();
}

void FMeshEditorViewportClient::CreateBoneDebugComponent()
{
	BoneDebugComponent = PreviewActor->AddComponent<UBoneDebugComponent>();
	BoneDebugComponent->SetTargetMeshComponent(PreviewMeshComponent);
	BoneDebugComponent->SetSelectedBoneIndex(SelectedBoneIndex);
	BoneDebugComponent->CreateRenderState();
}

void FMeshEditorViewportClient::CreatePhysicsAssetDebugComponent()
{
	if (!PreviewActor)
	{
		return;
	}

	if (!PhysicsAssetDebugComponent)
	{
		PhysicsAssetDebugComponent = PreviewActor->AddComponent<UPhysicsAssetDebugComponent>();
	}

	SyncPhysicsAssetDebugComponent(
		PreviewMeshComponent && PreviewMeshComponent->GetSkeletalMesh()
			? PreviewMeshComponent->GetSkeletalMesh()->GetPhysicsAsset()
			: nullptr,
		-1);
	if (PhysicsAssetDebugComponent)
	{
		PhysicsAssetDebugComponent->CreateRenderState();
	}
}

void FMeshEditorViewportClient::SyncPhysicsAssetDebugComponent(
	UPhysicsAsset* PhysicsAsset,
	int32 SelectedBodyIndex,
	int32 SelectedConstraintIndex)
{
	if (!PhysicsAssetDebugComponent && PreviewActor)
	{
		PhysicsAssetDebugComponent = PreviewActor->AddComponent<UPhysicsAssetDebugComponent>();
	}

	if (!PhysicsAssetDebugComponent)
	{
		return;
	}

	PhysicsAssetDebugComponent->SetTarget(PreviewMeshComponent, PhysicsAsset);
	PhysicsAssetDebugComponent->SetSelectedBodyIndex(SelectedBodyIndex);
	PhysicsAssetDebugComponent->SetSelectedConstraintIndex(SelectedConstraintIndex);
	SelectedPhysicsConstraintIndex = SelectedConstraintIndex;

	if (SelectedConstraintIndex >= 0)
	{
		SyncPhysicsAssetConstraintGizmoTarget(PhysicsAsset, SelectedConstraintIndex);
	}
	else
	{
		SyncPhysicsAssetShapeGizmoTarget(PhysicsAsset, SelectedBodyIndex);
	}
}

void FMeshEditorViewportClient::SetPhysicsAssetPickingEnabled(bool bInEnabled)
{
	bPhysicsAssetPickingEnabled = bInEnabled;
	if (!bPhysicsAssetPickingEnabled)
	{
		EndRagdollBodyPan();
	}
	if (!bPhysicsAssetPickingEnabled && PhysicsAssetDebugComponent)
	{
		PhysicsAssetDebugComponent->SetSelectedBodyIndex(-1);
		PhysicsAssetDebugComponent->SetSelectedConstraintIndex(-1);
		SelectedPhysicsConstraintIndex = -1;
	}
	if (!bPhysicsAssetPickingEnabled && Gizmo && (IsPhysicsAssetShapeGizmoActive() || IsPhysicsAssetConstraintGizmoActive()))
	{
		PhysicsAssetShapeTarget.Clear();
		PhysicsAssetConstraintTarget.Clear();
		Gizmo->Deactivate();
	}
}

void FMeshEditorViewportClient::SetOnPhysicsAssetBodyPicked(TFunction<void(int32)> InCallback)
{
	OnPhysicsAssetBodyPicked = std::move(InCallback);
}

void FMeshEditorViewportClient::SetOnPhysicsAssetConstraintPicked(TFunction<void(int32)> InCallback)
{
	OnPhysicsAssetConstraintPicked = std::move(InCallback);
}

void FMeshEditorViewportClient::SetOnPhysicsAssetShapeEdited(TFunction<void()> InCallback)
{
	OnPhysicsAssetShapeEdited = std::move(InCallback);
}

void FMeshEditorViewportClient::SetOnPhysicsAssetConstraintEdited(TFunction<void()> InCallback)
{
	OnPhysicsAssetConstraintEdited = std::move(InCallback);
}

bool FMeshEditorViewportClient::GetRagdollBodyPanInfo(
	FName& OutBoneName,
	FVector& OutWorldHitPoint,
	FVector& OutLocalHitPoint,
	FVector* OutTargetWorldPoint,
	float* OutPinDistance,
	float* OutBodyMass) const
{
	if (!bRagdollBodyPanning)
	{
		return false;
	}

	const FBodyInstance* Body = FindRagdollBodyForPhysicsAssetBodyIndex(RagdollPanBodyIndex);
	if (!Body)
	{
		return false;
	}

	OutBoneName = RagdollPanBoneName;
	OutLocalHitPoint = RagdollPanLocalHitPoint;

	// 빔 끝점은 숨은 목표점이 아니라 실제 물리 바디 위의 현재 피킹 지점에 붙입니다.
	// 그래야 물체가 늦게 따라와도 빔이 물체를 계속 잡고 있는 것처럼 보입니다.
	OutWorldHitPoint = Body->GetBodyTransform().TransformPosition(RagdollPanLocalHitPoint);
	if (OutTargetWorldPoint)
	{
		*OutTargetWorldPoint = RagdollPanTargetWorldPoint;
	}
	if (OutPinDistance)
	{
		*OutPinDistance = (RagdollPanTargetWorldPoint - OutWorldHitPoint).Length();
	}
	if (OutBodyMass)
	{
		*OutBodyMass = Body->GetMass();
	}
	return true;
}

void FMeshEditorViewportClient::NotifyPhysicsAssetBodyPicked(int32 BodyIndex)
{
	if (PhysicsAssetDebugComponent)
	{
		PhysicsAssetDebugComponent->SetSelectedBodyIndex(BodyIndex);
		PhysicsAssetDebugComponent->SetSelectedConstraintIndex(-1);
		SelectedPhysicsConstraintIndex = -1;
		if (CanUsePhysicsAssetGizmo())
		{
			SyncPhysicsAssetShapeGizmoTarget(PhysicsAssetDebugComponent->GetPhysicsAsset(), BodyIndex);
		}
		else
		{
			DeactivatePhysicsAssetGizmo();
		}
	}

	if (OnPhysicsAssetBodyPicked)
	{
		OnPhysicsAssetBodyPicked(BodyIndex);
	}
}

void FMeshEditorViewportClient::NotifyPhysicsAssetConstraintPicked(int32 ConstraintIndex)
{
	if (PhysicsAssetDebugComponent)
	{
		PhysicsAssetDebugComponent->SetSelectedBodyIndex(-1);
		PhysicsAssetDebugComponent->SetSelectedConstraintIndex(ConstraintIndex);
		SelectedPhysicsConstraintIndex = ConstraintIndex;
		if (CanUsePhysicsAssetGizmo())
		{
			SyncPhysicsAssetConstraintGizmoTarget(PhysicsAssetDebugComponent->GetPhysicsAsset(), ConstraintIndex);
		}
		else
		{
			DeactivatePhysicsAssetGizmo();
		}
	}

	if (OnPhysicsAssetConstraintPicked)
	{
		OnPhysicsAssetConstraintPicked(ConstraintIndex);
	}
}

void FMeshEditorViewportClient::ResetCameraToPreviousBounds()
{
	if (!PreviewActor || !PreviewMeshComponent)
	{
		ViewTransform.ViewLocation = FVector(-5.0f, -5.0f, 3.0f);
		ViewTransform.LookAt(FVector::ZeroVector);
		TargetLocation = ViewTransform.ViewLocation;
		LastAppliedCameraLocation = ViewTransform.ViewLocation;
		bTargetLocationInitialized = true;
		bLastAppliedCameraLocationInitialized = true;
		return;
	}

	FBoundingBox Bounds = PreviewMeshComponent->GetWorldBoundingBox();
	FVector Center = Bounds.GetCenter();
	float Radius = Bounds.GetExtent().Length();

	if (Radius < 0.1f)
	{
		Radius = 1.0f;
	}

	const float FovRadians = ViewTransform.FOV;
	const float Distance = Radius / std::tan(FovRadians * 0.5f) * 1.25f;

	const FVector ViewDir = FVector(-1.0f, -1.0f, -0.6f).Normalized();
	
	ViewTransform.ViewLocation = Center - ViewDir * Distance;
	ViewTransform.LookAt(Center);

	TargetLocation = ViewTransform.ViewLocation;
	LastAppliedCameraLocation = ViewTransform.ViewLocation;
	bTargetLocationInitialized = true;
	bLastAppliedCameraLocationInitialized = true;
}

bool FMeshEditorViewportClient::IsMouseOverViewport() const
{
	if (!bIsRenderable || ViewportScreenRect.Width <= 0.0f || ViewportScreenRect.Height <= 0.0f) return false;

	ImVec2 MousePos = ImGui::GetMousePos();
	return MousePos.x >= ViewportScreenRect.X && MousePos.x <= (ViewportScreenRect.X + ViewportScreenRect.Width) &&
		MousePos.y >= ViewportScreenRect.Y && MousePos.y <= (ViewportScreenRect.Y + ViewportScreenRect.Height);
}

bool FMeshEditorViewportClient::IsGizmoHolding() const
{
	return Gizmo && Gizmo->IsHolding();
}

void FMeshEditorViewportClient::NotifyViewportResized(int32 NewWidth, int32 NewHeight)
{
	if (Viewport)
	{
		ViewTransform.AspectRatio = static_cast<float>(NewWidth) / static_cast<float>(NewHeight);
	}
}

bool FMeshEditorViewportClient::GetCameraView(FMinimalViewInfo& OutPOV) const
{
	OutPOV.Location = ViewTransform.ViewLocation;
	OutPOV.Rotation = ViewTransform.ViewRotation;
	OutPOV.FOV = ViewTransform.FOV;
	OutPOV.AspectRatio = ViewTransform.AspectRatio;
	return true;
}

void FMeshEditorViewportClient::Tick(float DeltaTime)
{
	SyncCameraSmoothingTarget();

	if (bIsFocusAnimating)
	{
		FocusAnimTimer += DeltaTime;
		float Alpha = Clamp(FocusAnimTimer / FocusAnimDuration, 0.0f, 1.0f);
		if (Alpha >= 1.0f)
		{
			Alpha = 1.0f;
			bIsFocusAnimating = false;
		}

		float SmoothAlpha = Alpha * Alpha * (3.0f - 2.0f * Alpha);

		FVector NewLoc = FocusStartLoc * (1.0f - SmoothAlpha) + FocusEndLoc * SmoothAlpha;

		FQuat StartQuat = FocusStartRot.ToQuaternion();
		FQuat EndQuat = FocusEndRot.ToQuaternion();
		FQuat BlendedQuat = FQuat::Slerp(StartQuat, EndQuat, SmoothAlpha);

		ViewTransform.ViewLocation = NewLoc;
		ViewTransform.ViewRotation = FRotator::FromQuaternion(BlendedQuat);

		TargetLocation = NewLoc;
		LastAppliedCameraLocation = NewLoc;
		bLastAppliedCameraLocationInitialized = true;
	}
	else
	{
		ApplySmoothedCameraLocation(DeltaTime);
	}

	TickShortcuts();
	TickInput(DeltaTime);
	TickInteraction(DeltaTime);
}

void FMeshEditorViewportClient::SetSelectedBone(USkeletalMesh* Mesh, int32 BoneIndex)
{
	SelectedMesh = Mesh;
	SelectedBoneIndex = BoneIndex;
	RenderOptions.WeightBoneHeatMapBoneIndex = BoneIndex;

	if (Gizmo && PreviewMeshComponent && BoneIndex >= 0)
	{
		BoneTarget.SetBone(PreviewMeshComponent, BoneIndex);
		Gizmo->SetTarget(&BoneTarget);
	}
	else if (Gizmo)
	{
		Gizmo->Deactivate();
	}

	if (BoneDebugComponent)
	{
		BoneDebugComponent->SetTargetMeshComponent(PreviewMeshComponent);
		BoneDebugComponent->SetSelectedBoneIndex(BoneIndex);
	}
}

const FBone* FMeshEditorViewportClient::GetSelectedBone() const
{
	if (!SelectedMesh) return nullptr;

	FSkeletalMesh* Asset = SelectedMesh->GetSkeletalMeshAsset();
	if (!Asset) return nullptr;

	if (SelectedBoneIndex < 0 || SelectedBoneIndex >= static_cast<int32>(Asset->Bones.size())) return nullptr;

	return &Asset->Bones[SelectedBoneIndex];
}

EBoneDebugDrawMode FMeshEditorViewportClient::GetBoneDebugDrawMode() const
{
	return BoneDebugComponent ? BoneDebugComponent->GetDrawMode() : EBoneDebugDrawMode::SelectedOnly;
}

void FMeshEditorViewportClient::SetBoneDebugDrawMode(EBoneDebugDrawMode InDrawMode)
{
	if (BoneDebugComponent)
	{
		BoneDebugComponent->SetDrawMode(InDrawMode);
	}
}

void FMeshEditorViewportClient::TickShortcuts()
{
	if (!FSlateApplication::Get().DoesClientOwnKeyboardInput(this)) return;

	if (InputSystem::Get().GetKeyDown('F'))
	{
		if (const FBone* SelectedBone = GetSelectedBone())
		{
			FVector TargetLoc = PreviewMeshComponent->GetBoneLocationByIndex(SelectedBoneIndex);

			FVector OriginalLoc = ViewTransform.ViewLocation;
			FRotator OriginalRot = ViewTransform.ViewRotation;

			FBoundingBox Bounds = PreviewMeshComponent->GetWorldBoundingBox();
			FVector Center = Bounds.GetCenter();
			float Radius = Bounds.GetExtent().Length();

			if (Radius < 0.1f)
			{
				Radius = 1.0f;
			}

			float FocusDistance = Radius;
			FVector CameraForward = ViewTransform.ViewRotation.GetForwardVector();
			FVector NewCameraLoc = TargetLoc - CameraForward * FocusDistance;

			ViewTransform.ViewLocation = NewCameraLoc;
			ViewTransform.LookAt(TargetLoc);
			FRotator TargetRot = ViewTransform.ViewRotation;

			ViewTransform.ViewLocation = OriginalLoc;
			ViewTransform.ViewRotation = OriginalRot;

			bIsFocusAnimating = true;
			FocusAnimTimer = 0.0f;
			FocusStartLoc = OriginalLoc;
			FocusStartRot = OriginalRot;
			FocusEndLoc = NewCameraLoc;
			FocusEndRot = TargetRot;
		}
	}
}

void FMeshEditorViewportClient::TickInput(float DeltaTime)
{
	if (!FSlateApplication::Get().DoesClientOwnMouseInput(this)) return;

	// 텍스트 입력 중에는 카메라 키/마우스 조작을 가로채지 않는다.
	if (ImGui::GetIO().WantTextInput) return;

	FViewportCameraControlSettings& ControlSettings = FEditorSettings::Get().MeshEditorViewportSettings.CameraControls;

	InputSystem& Input = InputSystem::Get();
	
	FVector LocalMove = FVector::ZeroVector;
	float WorldVerticalMove = 0.0f;
	float CameraSpeed = ControlSettings.MoveSpeed;

	if (Input.GetKey('W')) LocalMove.X += CameraSpeed;
	if (Input.GetKey('S')) LocalMove.X -= CameraSpeed;
	if (Input.GetKey('D')) LocalMove.Y += CameraSpeed;
	if (Input.GetKey('A')) LocalMove.Y -= CameraSpeed;
	if (Input.GetKey('Q')) WorldVerticalMove -= CameraSpeed;
	if (Input.GetKey('E')) WorldVerticalMove += CameraSpeed;

	const FVector Forward = ViewTransform.ViewRotation.GetForwardVector();
	const FVector Right = ViewTransform.ViewRotation.GetRightVector();
	const FVector Up = ViewTransform.ViewRotation.GetUpVector();

	FVector DeltaMove = (Forward * LocalMove.X + Right * LocalMove.Y) * DeltaTime;
	DeltaMove.Z += WorldVerticalMove * DeltaTime;
	TargetLocation += DeltaMove;

	FVector Rotation = FVector::ZeroVector;

	FVector MouseRotation = FVector::ZeroVector;
	float MouseRotationSpeed = 0.15f * ControlSettings.RotationSpeed;

	if (Input.GetKey(VK_RBUTTON))
	{
		float DeltaX = static_cast<float>(Input.MouseDeltaX());
		float DeltaY = static_cast<float>(Input.MouseDeltaY());

		MouseRotation.Y += DeltaX * MouseRotationSpeed;
		MouseRotation.Z += DeltaY * MouseRotationSpeed;
	}

	Rotation *= DeltaTime;
	ViewTransform.Rotate(Rotation.Y + MouseRotation.Y, Rotation.Z + MouseRotation.Z);

	if (Input.GetKeyUp(VK_SPACE))
	{
		if (!Gizmo)
		{
			return;
		}

		if (IsPhysicsAssetConstraintGizmoActive())
		{
			Gizmo->SetTranslateMode();
		}
		else
		{
			Gizmo->SetNextMode();
		}
	}
}

void FMeshEditorViewportClient::TickInteraction(float DeltaTime)
{
	if (!FSlateApplication::Get().DoesClientOwnMouseInput(this)) return;

	if (!Gizmo || !PreviewWorld) return;

	FViewportCameraControlSettings& ControlSettings = FEditorSettings::Get().MeshEditorViewportSettings.CameraControls;

	Gizmo->ApplyScreenSpaceScaling(ViewTransform.ViewLocation, ViewTransform.bIsOrtho, ViewTransform.OrthoZoom);
	Gizmo->SetAxisMask(UGizmoComponent::ComputeAxisMask(RenderOptions.ViewportType, Gizmo->GetMode()));

	const float ZoomSpeed = ControlSettings.ZoomSpeed;

	float ScrollNotches = InputSystem::Get().GetScrollNotches();
	if (ScrollNotches != 0.0f)
	{
		if (bool bIsRightButtonDown = InputSystem::Get().GetKey(VK_RBUTTON))
		{
			float& MoveSpeed = FEditorSettings::Get().MeshEditorViewportSettings.CameraControls.MoveSpeed;
			if (ScrollNotches < 0.0f)
			{
				MoveSpeed = MoveSpeed * 0.9f;
			}
			else
			{
				MoveSpeed = MoveSpeed * 1.1f;
			}

			if (MoveSpeed > 1000.0f)
			{
				MoveSpeed = 1000.0f;
			}
			if (MoveSpeed < 0.001f)
			{
				MoveSpeed = 0.001f;
			}
		}
		else
		{
			if (ViewTransform.bIsOrtho)
			{
				// D.2: ViewTransform 직접 갱신.
				float NewWidth = ViewTransform.OrthoZoom - ScrollNotches * ZoomSpeed * DeltaTime;
				ViewTransform.OrthoZoom = Clamp(NewWidth, 0.1f, 1000.0f);
			}
			else
			{
				// 발줌은 절대 delta time를 곱하지 않음. 노치당 이동 거리가 일정해야 하기 때문.
				// 바로 이동시키지 않고 TargetLocation을 갱신해서 부드럽게 줌합니다.
				TargetLocation += ViewTransform.ViewRotation.GetForwardVector() * (ScrollNotches * ZoomSpeed * 0.015f);
				// 언리얼 엔진의 마우스 스크롤 카메라 속도는 노치당 5
			}
		}
	}


	ImVec2 MousePos = ImGui::GetIO().MousePos;
	float LocalMouseX = MousePos.x - ViewportScreenRect.X;
	float LocalMouseY = MousePos.y - ViewportScreenRect.Y;

	float VPWidth = Viewport ? static_cast<float>(Viewport->GetWidth()) : 1.0f;
	float VPHeight = Viewport ? static_cast<float>(Viewport->GetHeight()) : 1.0f;

	FMinimalViewInfo POV;
	GetCameraView(POV);
	FRay Ray = POV.DeprojectScreenToWorld(LocalMouseX, LocalMouseY, VPWidth, VPHeight);

	if (!CanUsePhysicsAssetGizmo())
	{
		DeactivatePhysicsAssetGizmo();
	}

	FHitResult HitResult;

	FRayUtils::RaycastComponent(Gizmo, Ray, HitResult);

	InputSystem& Input = InputSystem::Get();

	if (bRagdollBodyPanning)
	{
		if (Input.GetKey(VK_LBUTTON))
		{
			UpdateRagdollBodyPan(Ray, DeltaTime);
		}
		else
		{
			EndRagdollBodyPan();
		}
		return;
	}

	if (Input.GetKeyDown(VK_LBUTTON))
	{
		HandleDragStart(Ray);
	}
	else if (Input.GetLeftDragging())
	{
		if (Gizmo->IsPressedOnHandle() && !Gizmo->IsHolding())
		{
			Gizmo->SetHolding(true);
		}

		if (Gizmo->IsHolding())
		{
			Gizmo->UpdateDrag(Ray);
		}
	}
	else if (Input.GetLeftDragEnd())
	{
		const bool bWasHoldingPhysicsAssetShape = Gizmo->IsHolding() && IsPhysicsAssetShapeGizmoActive();
		const bool bWasHoldingPhysicsAssetConstraint = Gizmo->IsHolding() && IsPhysicsAssetConstraintGizmoActive();
		if (Gizmo->IsHolding())
		{
			Gizmo->DragEnd();
		}
		if (bWasHoldingPhysicsAssetShape && OnPhysicsAssetShapeEdited)
		{
			OnPhysicsAssetShapeEdited();
		}
		if (bWasHoldingPhysicsAssetConstraint && OnPhysicsAssetConstraintEdited)
		{
			OnPhysicsAssetConstraintEdited();
		}
	}
	else if (Input.GetKeyUp(VK_LBUTTON))
	{
		Gizmo->SetPressedOnHandle(false);
	}
}

void FMeshEditorViewportClient::SyncCameraSmoothingTarget()
{
	const FVector CurrentLocation = ViewTransform.ViewLocation;
	const bool bCameraMovedExternally = bLastAppliedCameraLocationInitialized
		&& FVector::DistSquared(CurrentLocation, LastAppliedCameraLocation) > 0.0001f;

	if (!bTargetLocationInitialized || bCameraMovedExternally)
	{
		TargetLocation = CurrentLocation;
		bTargetLocationInitialized = true;
	}

	LastAppliedCameraLocation = CurrentLocation;
	bLastAppliedCameraLocationInitialized = true;
}

void FMeshEditorViewportClient::ApplySmoothedCameraLocation(float DeltaTime)
{
	const FVector CurrentLocation = ViewTransform.ViewLocation;
	const float LerpAlpha = Clamp(DeltaTime * SmoothLocationSpeed, 0.0f, 1.0f);
	const FVector NewLocation = CurrentLocation + (TargetLocation - CurrentLocation) * LerpAlpha;
	ViewTransform.ViewLocation = NewLocation;

	LastAppliedCameraLocation = NewLocation;
	bLastAppliedCameraLocationInitialized = true;
}

void FMeshEditorViewportClient::SyncGizmo()
{
	if (!Gizmo || !PreviewActor) return;

	if (const FBone* SelectedBone = GetSelectedBone())
	{
	}
	else
	{
		Gizmo->Deactivate();
	}
}

void FMeshEditorViewportClient::SyncPhysicsAssetShapeGizmoTarget(UPhysicsAsset* PhysicsAsset, int32 SelectedBodyIndex)
{
	if (!Gizmo)
	{
		return;
	}

	if (!CanUsePhysicsAssetGizmo() || !bPhysicsAssetPickingEnabled || !PhysicsAssetDebugComponent || !PhysicsAsset || SelectedBodyIndex < 0)
	{
		if (IsPhysicsAssetShapeGizmoActive() || IsPhysicsAssetConstraintGizmoActive())
		{
			PhysicsAssetShapeTarget.Clear();
			PhysicsAssetConstraintTarget.Clear();
			Gizmo->Deactivate();
		}
		return;
	}

	PhysicsAssetConstraintTarget.Clear();
	PhysicsAssetShapeTarget.SetShape(PhysicsAssetDebugComponent, SelectedBodyIndex);
	if (!PhysicsAssetShapeTarget.IsValid())
	{
		if (IsPhysicsAssetShapeGizmoActive())
		{
			Gizmo->Deactivate();
		}
		PhysicsAssetShapeTarget.Clear();
		return;
	}

	if (Gizmo->GetTarget() != &PhysicsAssetShapeTarget)
	{
		Gizmo->SetTarget(&PhysicsAssetShapeTarget);
	}
	else
	{
		Gizmo->UpdateGizmoTransform();
	}
	ApplyTransformSettingsToGizmo();
}

void FMeshEditorViewportClient::SyncPhysicsAssetConstraintGizmoTarget(UPhysicsAsset* PhysicsAsset, int32 SelectedConstraintIndex)
{
	if (!Gizmo)
	{
		return;
	}

	if (!CanUsePhysicsAssetGizmo() || !bPhysicsAssetPickingEnabled || !PhysicsAssetDebugComponent || !PhysicsAsset || SelectedConstraintIndex < 0)
	{
		if (IsPhysicsAssetShapeGizmoActive() || IsPhysicsAssetConstraintGizmoActive())
		{
			PhysicsAssetShapeTarget.Clear();
			PhysicsAssetConstraintTarget.Clear();
			Gizmo->Deactivate();
		}
		return;
	}

	PhysicsAssetShapeTarget.Clear();
	PhysicsAssetConstraintTarget.SetConstraint(PhysicsAssetDebugComponent, SelectedConstraintIndex);
	if (!PhysicsAssetConstraintTarget.IsValid())
	{
		if (IsPhysicsAssetConstraintGizmoActive())
		{
			Gizmo->Deactivate();
		}
		PhysicsAssetConstraintTarget.Clear();
		return;
	}

	Gizmo->SetTranslateMode();
	if (Gizmo->GetTarget() != &PhysicsAssetConstraintTarget)
	{
		Gizmo->SetTarget(&PhysicsAssetConstraintTarget);
	}
	else
	{
		Gizmo->UpdateGizmoTransform();
	}
	ApplyTransformSettingsToGizmo();
}

void FMeshEditorViewportClient::ApplyTransformSettingsToGizmo()
{
	if (!Gizmo) return;

	const FGizmoToolSettings& Settings = FEditorSettings::Get().MeshEditorViewportSettings.Gizmo;
	const bool bForceLocalForScale = Gizmo->GetMode() == EGizmoMode::Scale;

	Gizmo->SetWorldSpace(bForceLocalForScale ? false : Settings.CoordSystem == EEditorCoordSystem::World);
	Gizmo->SetSnapSettings(
		Settings.bEnableTranslationSnap, Settings.TranslationSnapSize,
		Settings.bEnableRotationSnap, Settings.RotationSnapSize,
		Settings.bEnableScaleSnap, Settings.ScaleSnapSize
	);
}

bool FMeshEditorViewportClient::IsRagdollPreviewActive() const
{
	return PreviewDebugMeshComponent && PreviewDebugMeshComponent->IsRagdollEnabled();
}

bool FMeshEditorViewportClient::CanUsePhysicsAssetGizmo() const
{
	return !IsRagdollPreviewActive() && !bRagdollBodyPanning;
}

void FMeshEditorViewportClient::DeactivatePhysicsAssetGizmo()
{
	if (Gizmo && (IsPhysicsAssetShapeGizmoActive() || IsPhysicsAssetConstraintGizmoActive()))
	{
		Gizmo->Deactivate();
	}

	PhysicsAssetShapeTarget.Clear();
	PhysicsAssetConstraintTarget.Clear();
}

FBodyInstance* FMeshEditorViewportClient::FindRagdollBodyForPhysicsAssetBodyIndex(int32 BodyIndex) const
{
	if (!PreviewDebugMeshComponent || !PhysicsAssetDebugComponent || BodyIndex < 0)
	{
		return nullptr;
	}

	UPhysicsAsset* PhysicsAsset = PhysicsAssetDebugComponent->GetPhysicsAsset();
	if (!PhysicsAsset)
	{
		return nullptr;
	}

	const TArray<UBodySetup*>& BodySetups = PhysicsAsset->GetBodySetups();
	if (BodyIndex >= static_cast<int32>(BodySetups.size()) || !BodySetups[BodyIndex])
	{
		return nullptr;
	}

	const FName BodyBoneName = BodySetups[BodyIndex]->BoneName;
	// 에디터 피커는 PhysicsAsset 물리 바디 인덱스를 돌려주지만, 힘은 실제 시뮬레이션 중인
	// 랙돌 물리 바디 인스턴스에 적용해야 합니다. BoneName으로 두 대상을 안정적으로 연결합니다.
	for (FBodyInstance* Body : PreviewDebugMeshComponent->GetRagdollBodies())
	{
		if (Body && Body->IsValidBodyInstance() && Body->BoneName == BodyBoneName)
		{
			return Body;
		}
	}

	return nullptr;
}

bool FMeshEditorViewportClient::BeginRagdollBodyPan(const FRay& Ray, const FPhysicsAssetDebugHitResult& Hit)
{
	FBodyInstance* Body = FindRagdollBodyForPhysicsAssetBodyIndex(Hit.BodyIndex);
	if (!Body)
	{
		EndRagdollBodyPan();
		return false;
	}

	const FVector RayDirection = Ray.Direction.GetSafeNormal();
	if (RayDirection.IsNearlyZero())
	{
		EndRagdollBodyPan();
		return false;
	}

	const FTransform BodyTransform = Body->GetBodyTransform();
	const FVector BodyCenterWorld = BodyTransform.GetLocation();
	FVector GrabOffsetWorld = Hit.WorldHitLocation - BodyCenterWorld;

	// 디버그 충돌 지점이 물리 바디 중심에서 너무 멀면 큰 지렛대가 되어 토크가 폭발할 수 있습니다.
	// 초기 패닝 기준 평면의 거리만 제한하고, 실제 피킹 지점은 아래에서 별도로 저장합니다.
	constexpr float MaxInitialGrabOffset = 50.0f;
	const float GrabOffsetLength = GrabOffsetWorld.Length();
	if (GrabOffsetLength > MaxInitialGrabOffset)
	{
		GrabOffsetWorld *= MaxInitialGrabOffset / GrabOffsetLength;
	}

	RagdollPanBodyIndex = Hit.BodyIndex;
	RagdollPanBoneName = Body->BoneName;

	// 정확히 피킹한 지점을 물리 바디의 로컬 좌표로 저장합니다. 매 프레임 다시 월드 좌표로 바꿔
	// 물리 바디가 회전한 뒤에도 같은 표면 지점을 목표 위치로 끌 수 있게 합니다.
	RagdollPanLocalHitPoint = BodyTransform.ToMatrix().GetAffineInverse().TransformPositionWithW(Hit.WorldHitLocation);

	// 잡은 지점을 지나는 카메라 방향 평면을 마우스 드래그 기준면으로 사용합니다.
	// 2D 마우스 이동에서 깊이를 직접 추정하지 않아도 되어 패닝이 안정적입니다.
	RagdollPanPlaneOrigin = BodyCenterWorld + GrabOffsetWorld;
	RagdollPanPlaneNormal = RayDirection;
	RagdollPanTargetWorldPoint = RagdollPanPlaneOrigin;
	RagdollPanGrabOffsetWorld = GrabOffsetWorld;
	RagdollPanDistance = (Hit.WorldHitLocation - Ray.Origin).Dot(RayDirection);
	if (RagdollPanDistance <= 0.0f)
	{
		RagdollPanDistance = Hit.Distance;
	}

	bRagdollBodyPanning = RagdollPanDistance > 0.0f;
	if (!bRagdollBodyPanning)
	{
		EndRagdollBodyPan();
		return false;
	}
	bRagdollPanSpringActive = false;

	Body->WakeUp();
	DeactivatePhysicsAssetGizmo();
	return true;
}

bool FMeshEditorViewportClient::ComputeRagdollBodyPanTarget(const FRay& Ray, FVector& OutTargetWorldPoint) const
{
	const FVector RayDirection = Ray.Direction.GetSafeNormal();
	if (RayDirection.IsNearlyZero() || RagdollPanPlaneNormal.IsNearlyZero())
	{
		return false;
	}

	const float Denom = RayDirection.Dot(RagdollPanPlaneNormal);
	constexpr float ParallelTolerance = 1.0e-4f;
	if (FMath::Abs(Denom) <= ParallelTolerance)
	{
		// ray가 평면과 거의 평행하면 멀리 있는 불안정한 교차점을 만들지 않고
		// 이전 목표점을 유지합니다.
		OutTargetWorldPoint = RagdollPanTargetWorldPoint;
		return true;
	}

	const float PlaneDistance = (RagdollPanPlaneOrigin - Ray.Origin).Dot(RagdollPanPlaneNormal) / Denom;
	if (PlaneDistance <= 0.0f)
	{
		// 카메라 뒤쪽 평면 교차점은 드래그 목표점으로 사용할 수 없습니다.
		OutTargetWorldPoint = RagdollPanTargetWorldPoint;
		return true;
	}

	OutTargetWorldPoint = Ray.Origin + RayDirection * PlaneDistance;
	return !OutTargetWorldPoint.ContainsNaN();
}

void FMeshEditorViewportClient::UpdateRagdollBodyPan(const FRay& Ray, float DeltaTime)
{
	(void)DeltaTime;

	if (!bRagdollBodyPanning)
	{
		return;
	}

	FBodyInstance* Body = FindRagdollBodyForPhysicsAssetBodyIndex(RagdollPanBodyIndex);
	if (!Body && PreviewDebugMeshComponent && RagdollPanBoneName != FName::None)
	{
		for (FBodyInstance* Candidate : PreviewDebugMeshComponent->GetRagdollBodies())
		{
			if (Candidate && Candidate->IsValidBodyInstance() && Candidate->BoneName == RagdollPanBoneName)
			{
				Body = Candidate;
				break;
			}
		}
	}

	if (!Body)
	{
		EndRagdollBodyPan();
		return;
	}

	const FTransform BodyTransform = Body->GetBodyTransform();
	const FVector CurrentBodyCenter = BodyTransform.GetLocation();

	// 저장된 로컬 지점으로 현재 월드 좌표의 잡기 지점을 다시 계산합니다.
	// 화면상으로 마우스 아래에 붙어 있어야 하는 지점입니다.
	const FVector CurrentGrabWorld = BodyTransform.TransformPosition(RagdollPanLocalHitPoint);
	if (!bRagdollPanSpringActive)
	{
		if (!InputSystem::Get().GetLeftDragging())
		{
			return;
		}

		// 실제 드래그가 시작된 뒤에만 스프링을 활성화합니다.
		// 가만히 클릭만 했을 때 힘이 주입되는 것을 막기 위해서입니다.
		bRagdollPanSpringActive = true;
		RagdollPanPlaneOrigin = CurrentGrabWorld;
		RagdollPanTargetWorldPoint = CurrentGrabWorld;
	}

	FVector DesiredGrabWorld = RagdollPanTargetWorldPoint;
	if (!ComputeRagdollBodyPanTarget(Ray, DesiredGrabWorld))
	{
		EndRagdollBodyPan();
		return;
	}
	RagdollPanTargetWorldPoint = DesiredGrabWorld;

	const FVector GrabOffsetWorld = CurrentGrabWorld - CurrentBodyCenter;

	// 1번 방식: DesiredGrabWorld는 보이지 않는 목표점이고, CurrentGrabWorld는 실제 물체 위의 피킹 지점입니다.
	// 두 지점 사이의 거리를 허용하기 때문에 물체가 스프링처럼 늦게 따라오는 느낌이 납니다.
	const FVector Error = DesiredGrabWorld - CurrentGrabWorld;

	// 가속도 단위의 PD 스프링입니다. 기본 grip은 핀포인트에 더 잘 붙도록 강하게 두고,
	// 아래의 질량 스케일로 무거운 물리 바디만 살짝 더 늦게 따라오게 합니다.
	constexpr float SpringAcceleration = 220.0f;
	constexpr float DampingAcceleration = 36.0f;
	constexpr float MaxError = 80.0f;
	constexpr float MaxAcceleration = 20000.0f;
	constexpr float GrabTorqueScale = 0.65f;
	constexpr float GrabAngularDamping = 10.0f;
	constexpr float MaxGrabTorque = 100000.0f;
	constexpr float ReferenceGripMass = 1.0f;
	constexpr float MassGripPower = 0.35f;
	constexpr float MinMassGripScale = 0.45f;
	constexpr float MaxMassGripScale = 1.15f;

	FVector ClampedError = Error;
	const float ErrorLength = ClampedError.Length();
	if (ErrorLength > MaxError)
	{
		ClampedError *= MaxError / ErrorLength;
	}

	const float Mass = std::max(Body->GetMass(), 0.001f);

	// Force = Acceleration * Mass만 쓰면 모든 질량이 거의 같은 반응성을 가집니다.
	// grip 가속도 자체를 질량에 따라 줄여서 무거운 물체는 중력/관성의 영향을 조금 더 받게 합니다.
	const float MassGripScale = std::clamp(
		std::pow(ReferenceGripMass / Mass, MassGripPower),
		MinMassGripScale,
		MaxMassGripScale
	);
	const float EffectiveSpringAcceleration = SpringAcceleration * MassGripScale;
	const float EffectiveDampingAcceleration = DampingAcceleration * MassGripScale;
	const float EffectiveMaxAcceleration = MaxAcceleration * MassGripScale;

	FVector Acceleration = ClampedError * EffectiveSpringAcceleration
		- Body->GetLinearVelocity() * EffectiveDampingAcceleration;
	const float AccelerationLength = Acceleration.Length();
	if (AccelerationLength > EffectiveMaxAcceleration)
	{
		Acceleration *= EffectiveMaxAcceleration / AccelerationLength;
	}

	const FVector Force = Acceleration * Mass;
	Body->AddForce(Force);

	if (GrabOffsetWorld.Length() > 1.0f)
	{
		// 중심에서 벗어난 잡기 토크를 선형 힘과 분리해서 토크만 별도로 제한합니다.
		FVector Torque = GrabOffsetWorld.Cross(Force) * (GrabTorqueScale * MassGripScale)
			- Body->GetAngularVelocity() * (GrabAngularDamping * Mass * MassGripScale);
		const float TorqueLength = Torque.Length();
		const float MaxTorqueForBody = MaxGrabTorque * Mass * MassGripScale;
		if (TorqueLength > MaxTorqueForBody && TorqueLength > FMath::KINDA_SMALL_NUMBER)
		{
			Torque *= MaxTorqueForBody / TorqueLength;
		}
		Body->AddTorque(Torque);
	}
	Body->WakeUp();
}

void FMeshEditorViewportClient::EndRagdollBodyPan()
{
	bRagdollBodyPanning = false;
	bRagdollPanSpringActive = false;
	RagdollPanBodyIndex = -1;
	RagdollPanBoneName = FName::None;
	RagdollPanLocalHitPoint = FVector::ZeroVector;
	RagdollPanPlaneOrigin = FVector::ZeroVector;
	RagdollPanPlaneNormal = FVector::ForwardVector;
	RagdollPanTargetWorldPoint = FVector::ZeroVector;
	RagdollPanGrabOffsetWorld = FVector::ZeroVector;
	RagdollPanDistance = 0.0f;
}

bool FMeshEditorViewportClient::IsPhysicsAssetShapeGizmoActive() const
{
	return Gizmo && Gizmo->GetTarget() == &PhysicsAssetShapeTarget;
}

bool FMeshEditorViewportClient::IsPhysicsAssetConstraintGizmoActive() const
{
	return Gizmo && Gizmo->GetTarget() == &PhysicsAssetConstraintTarget;
}

void FMeshEditorViewportClient::HandleDragStart(const FRay& Ray)
{
	if (bPhysicsAssetPickingEnabled && PhysicsAssetDebugComponent && IsRagdollPreviewActive())
	{
		// 랙돌 미리보기에서는 물리 바디 클릭 시 일반 PhysicsAsset 도형 기즈모 대신
		// 물리 잡기 프로토타입을 시작합니다.
		FPhysicsAssetDebugHitResult PhysicsHit;
		if (PhysicsAssetDebugComponent->PickBody(Ray, PhysicsHit))
		{
			NotifyPhysicsAssetBodyPicked(PhysicsHit.BodyIndex);
			BeginRagdollBodyPan(Ray, PhysicsHit);
		}
		else
		{
			NotifyPhysicsAssetBodyPicked(-1);
			EndRagdollBodyPan();
		}
		return;
	}

	FHitResult Hit;
	if (Gizmo && FRayUtils::RaycastComponent(Gizmo, Ray, Hit))
	{
		Gizmo->SetPressedOnHandle(true);
		return;
	}

	if (bPhysicsAssetPickingEnabled && PhysicsAssetDebugComponent)
	{
		FPhysicsAssetDebugHitResult PhysicsHit;
		if (PhysicsAssetDebugComponent->PickConstraint(
				Ray,
				ViewTransform.ViewLocation,
				ViewTransform.bIsOrtho,
				ViewTransform.OrthoZoom,
				PhysicsHit))
		{
			NotifyPhysicsAssetConstraintPicked(PhysicsHit.ConstraintIndex);
			return;
		}

		const int32 PickedBodyIndex = PhysicsAssetDebugComponent->PickBody(Ray, PhysicsHit)
			? PhysicsHit.BodyIndex
			: -1;
		NotifyPhysicsAssetBodyPicked(PickedBodyIndex);
	}
}
