#include "Mesh/Importer/Fbx/FbxSceneLoader.h"
#include "Platform/Paths.h"
#include "Core/Logging/Log.h"

#include <chrono>
#include <vector>

namespace
{
	using FFbxClock = std::chrono::steady_clock;

	static double GetElapsedSeconds(const FFbxClock::time_point& Start)
	{
		return std::chrono::duration<double>(FFbxClock::now() - Start).count();
	}

	struct FFbxSharedSdkContext
	{
		FbxManager* Manager = nullptr;
		FbxIOSettings* IoSettings = nullptr;

		FFbxSharedSdkContext()
		{
			Manager = FbxManager::Create();
			if (!Manager)
			{
				return;
			}

			IoSettings = FbxIOSettings::Create(Manager, IOSROOT);
			if (!IoSettings)
			{
				Manager->Destroy();
				Manager = nullptr;
				return;
			}

			Manager->SetIOSettings(IoSettings);
		}

		~FFbxSharedSdkContext()
		{
			if (Manager)
			{
				Manager->Destroy();
				Manager = nullptr;
				IoSettings = nullptr;
			}
		}

		bool IsValid() const
		{
			return Manager != nullptr && IoSettings != nullptr;
		}
	};

	static FFbxSharedSdkContext& GetSharedSdkContext()
	{
		static FFbxSharedSdkContext Context;
		return Context;
	}
}

FFbxSceneHandle::~FFbxSceneHandle()
{
	Reset();
}

void FFbxSceneHandle::Reset()
{
	if (Scene)
	{
		const auto Start = FFbxClock::now();
		Scene->Destroy(true);
		Scene = nullptr;

		UE_LOG("FBX scene cleanup timing: SceneDestroy=%.3fs", GetElapsedSeconds(Start));
	}

	// Manager is a shared process-lifetime SDK context owned by FbxSceneLoader.cpp.
	Manager = nullptr;
}

namespace
{
	static void ApplyFbxImportOptions(FbxIOSettings* IoSettings, const FFbxSceneLoadOptions& Options)
	{
		if (!IoSettings)
		{
			return;
		}

		IoSettings->SetBoolProp(IMP_FBX_MATERIAL, Options.bImportMaterials);
		IoSettings->SetBoolProp(IMP_FBX_TEXTURE, Options.bImportTextures);
		IoSettings->SetBoolProp(IMP_FBX_LINK, Options.bImportLinks);
		IoSettings->SetBoolProp(IMP_FBX_SHAPE, Options.bImportShapes);
		IoSettings->SetBoolProp(IMP_FBX_GOBO, Options.bImportGobos);
		IoSettings->SetBoolProp(IMP_FBX_ANIMATION, Options.bImportAnimations);
		IoSettings->SetBoolProp(IMP_FBX_GLOBAL_SETTINGS, Options.bImportGlobalSettings);
	}

	static void ApplyFbxAnimationStackSelection(FbxImporter* Importer, const FFbxSceneLoadOptions& Options)
	{
		if (!Importer || !Options.bImportAnimations || Options.SelectedAnimationStackIndices.empty())
		{
			return;
		}

		const int32 AnimStackCount = Importer->GetAnimStackCount();
		for (int32 StackIndex = 0; StackIndex < AnimStackCount; ++StackIndex)
		{
			if (FbxTakeInfo* TakeInfo = Importer->GetTakeInfo(StackIndex))
			{
				TakeInfo->mSelect = Options.SelectedAnimationStackIndices.find(StackIndex) != Options.
				SelectedAnimationStackIndices.end();
			}
		}
	}
}

bool FFbxSceneLoader::Load(const FString& SourcePath, FFbxSceneHandle& OutScene, FString* OutMessage)
{
	return Load(SourcePath, FFbxSceneLoadOptions(), OutScene, OutMessage);
}

bool FFbxSceneLoader::Load(
	const FString&              SourcePath,
	const FFbxSceneLoadOptions& Options,
	FFbxSceneHandle&            OutScene,
	FString*                    OutMessage
	)
{
	OutScene.Reset();

	FFbxSharedSdkContext& SdkContext = GetSharedSdkContext();
	if (!SdkContext.IsValid())
	{
		if (OutMessage) *OutMessage = "FBX SDK manager creation failed.";
		return false;
	}

	FbxManager* SdkManager = SdkContext.Manager;
	FbxIOSettings* IoSettings = SdkContext.IoSettings;
	ApplyFbxImportOptions(IoSettings, Options);

	FbxScene* Scene = FbxScene::Create(SdkManager, "FBX Scene");
	FbxImporter* Importer = FbxImporter::Create(SdkManager, "");
	if (!Scene || !Importer)
	{
		if (Importer) Importer->Destroy();
		if (Scene) Scene->Destroy(true);
		if (OutMessage) *OutMessage = "FBX scene/importer creation failed.";
		return false;
	}

	const FString FullPath = FPaths::ToUtf8(FPaths::Combine(FPaths::RootDir(), FPaths::ToWide(SourcePath)));
	if (!Importer->Initialize(FullPath.c_str(), -1, SdkManager->GetIOSettings()))
	{
		Importer->Destroy();
		Scene->Destroy(true);
		if (OutMessage) *OutMessage = FString("FBX importer initialize failed: ") + SourcePath;
		return false;
	}

	ApplyFbxAnimationStackSelection(Importer, Options);

	if (!Importer->Import(Scene))
	{
		Importer->Destroy();
		Scene->Destroy(true);
		if (OutMessage) *OutMessage = FString("FBX scene import failed: ") + SourcePath;
		return false;
	}

	Importer->Destroy();
	OutScene.Manager = SdkManager;
	OutScene.Scene = Scene;
	return true;
}

void FFbxSceneLoader::NormalizeScene(FbxScene* Scene)
{
	if (!Scene)
	{
		return;
	}

	FbxSystemUnit::m.ConvertScene(Scene);

	FbxAxisSystem UnrealAxisSystem(
		FbxAxisSystem::eZAxis,
		FbxAxisSystem::eParityEven,
		FbxAxisSystem::eLeftHanded
	);
	UnrealAxisSystem.DeepConvertScene(Scene);
}

namespace
{
	// The FBX SDK triangulator dereferences a null pointer on some malformed meshes (most often
	// bad blend-shape/skin data), raising a hardware access violation (read at 0x10) instead of
	// returning an error. Isolate the call behind SEH so a single bad asset cannot crash the editor.
	// EXCEPTION_EXECUTE_HANDLER == 1; using the literal avoids depending on <excpt.h>/<windows.h>.
	static bool TriangulateAttributeGuarded(FbxGeometryConverter& Converter, FbxNodeAttribute* Attribute)
	{
		__try
		{
			return Converter.Triangulate(Attribute, /*pReplace*/ true) != nullptr;
		}
		__except (/*EXCEPTION_EXECUTE_HANDLER*/ 1)
		{
			return false;
		}
	}

	static int32 RemoveBlendShapeDeformers(FbxMesh* Mesh)
	{
		if (!Mesh)
		{
			return 0;
		}

		int32 Removed = 0;
		for (int32 Index = Mesh->GetDeformerCount() - 1; Index >= 0; --Index)
		{
			FbxDeformer* Deformer = Mesh->GetDeformer(Index);
			if (Deformer && Deformer->GetDeformerType() == FbxDeformer::eBlendShape)
			{
				Mesh->RemoveDeformer(Index);
				++Removed;
			}
		}
		return Removed;
	}

	// Skin clusters that influence zero control points (empty Indexes/Weights arrays) crash the
	// SDK triangulator when it remaps skin weights to the triangulated mesh: it dereferences the
	// cluster's null index array (access violation at 0x10). Such clusters contribute nothing to
	// deformation, so dropping them is safe and removes the crash trigger.
	static int32 RemoveEmptySkinClusters(FbxMesh* Mesh)
	{
		if (!Mesh)
		{
			return 0;
		}

		int32 Removed = 0;
		const int32 SkinCount = Mesh->GetDeformerCount(FbxDeformer::eSkin);
		for (int32 SkinIndex = 0; SkinIndex < SkinCount; ++SkinIndex)
		{
			FbxSkin* Skin = static_cast<FbxSkin*>(Mesh->GetDeformer(SkinIndex, FbxDeformer::eSkin));
			if (!Skin)
			{
				continue;
			}

			for (int32 ClusterIndex = Skin->GetClusterCount() - 1; ClusterIndex >= 0; --ClusterIndex)
			{
				FbxCluster* Cluster = Skin->GetCluster(ClusterIndex);
				if (Cluster && Cluster->GetControlPointIndicesCount() <= 0)
				{
					Skin->RemoveCluster(Cluster);
					++Removed;
				}
			}
		}
		return Removed;
	}
}

void FFbxSceneLoader::Triangulate(FbxManager* Manager, FbxScene* Scene)
{
	if (!Manager || !Scene)
	{
		return;
	}

	FbxGeometryConverter Converter(Manager);

	// Do NOT use FbxGeometryConverter::Triangulate(Scene, true): the SDK's whole-scene path
	// iterates every node attribute and dereferences a null pointer (access violation at 0x10)
	// when the scene contains an empty/degenerate mesh (zero control points or polygons).
	// Triangulating per node attribute lets us validate each mesh and skip the bad ones.

	// The scene node list is stable across triangulation (only attributes are swapped), but a
	// node's attribute list is mutated by Triangulate(..., pReplace=true), so collect the mesh
	// attributes up front and triangulate them afterwards.
	std::vector<FbxNodeAttribute*> MeshAttributes;

	const int32 NodeCount = Scene->GetNodeCount();
	for (int32 NodeIndex = 0; NodeIndex < NodeCount; ++NodeIndex)
	{
		FbxNode* Node = Scene->GetNode(NodeIndex);
		if (!Node)
		{
			continue;
		}

		const int32 AttributeCount = Node->GetNodeAttributeCount();
		for (int32 AttrIndex = 0; AttrIndex < AttributeCount; ++AttrIndex)
		{
			FbxNodeAttribute* Attribute = Node->GetNodeAttributeByIndex(AttrIndex);
			if (!Attribute || Attribute->GetAttributeType() != FbxNodeAttribute::eMesh)
			{
				continue;
			}

			const FbxMesh* Mesh = static_cast<const FbxMesh*>(Attribute);
			if (Mesh->GetControlPointsCount() <= 0 || Mesh->GetPolygonCount() <= 0)
			{
				UE_LOG("FBX triangulate: skipping empty mesh on node '%s'.", Node->GetName());
				continue;
			}

			if (Mesh->IsTriangleMesh())
			{
				continue;
			}

			MeshAttributes.push_back(Attribute);
		}
	}

	for (FbxNodeAttribute* Attribute : MeshAttributes)
	{
		if (TriangulateAttributeGuarded(Converter, Attribute))
		{
			continue;
		}

		// Triangulation failed or crashed inside the SDK. Strip the data its skin/shape
		// preservation chokes on — empty skin clusters (bones influencing zero vertices) and
		// blend shapes — then retry once. Neither affects the imported skin weights. The original
		// (untriangulated) mesh is still intact at this point.
		FbxNode* Owner = Attribute->GetNode();
		const char* NodeName = Owner ? Owner->GetName() : "<unknown>";
		FbxMesh* Mesh = static_cast<FbxMesh*>(Attribute);

		const int32 RemovedClusters = RemoveEmptySkinClusters(Mesh);
		const int32 RemovedShapes = RemoveBlendShapeDeformers(Mesh);
		if ((RemovedClusters > 0 || RemovedShapes > 0) && TriangulateAttributeGuarded(Converter, Attribute))
		{
			UE_LOG("FBX triangulate: node '%s' triangulated after removing %d empty cluster(s), %d blend shape(s).", NodeName, RemovedClusters, RemovedShapes);
			continue;
		}

		UE_LOG("FBX triangulate: failed to triangulate mesh on node '%s'; importing it untriangulated.", NodeName);
	}
}
