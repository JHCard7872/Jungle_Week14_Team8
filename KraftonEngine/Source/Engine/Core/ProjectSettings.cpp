#include "Core/ProjectSettings.h"
#include "SimpleJSON/json.hpp"
#include "Core/Logging/Log.h"

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <filesystem>

namespace PSKey
{
	constexpr const char* Shadow = "Shadow";
	constexpr const char* bShadows = "bShadows";
	constexpr const char* CSMResolution = "CSMResolution";
	constexpr const char* SpotAtlasResolution = "SpotAtlasResolution";
	constexpr const char* PointAtlasResolution = "PointAtlasResolution";
	constexpr const char* MaxSpotAtlasPages = "MaxSpotAtlasPages";
	constexpr const char* MaxPointAtlasPages = "MaxPointAtlasPages";

	constexpr const char* GameSection = "Game";
	constexpr const char* StartLevelName = "StartLevelName";
	constexpr const char* GameModeClassName = "GameModeClassName";
	constexpr const char* GameWindowWidth = "GameWindowWidth";
	constexpr const char* GameWindowHeight = "GameWindowHeight";
	constexpr const char* bStartFullscreen = "bStartFullscreen";
	constexpr const char* bLockEditorPIEResolution = "bLockEditorPIEResolution";
}

namespace
{
	constexpr int MinGameWindowWidth = 320;
	constexpr int MinGameWindowHeight = 240;
	constexpr int MaxGameWindowDimension = 8192;

	uint32 ClampGameWindowWidth(int Value)
	{
		return static_cast<uint32>(std::clamp(Value, MinGameWindowWidth, MaxGameWindowDimension));
	}

	uint32 ClampGameWindowHeight(int Value)
	{
		return static_cast<uint32>(std::clamp(Value, MinGameWindowHeight, MaxGameWindowDimension));
	}
}

FString FProjectSettings::GetDefaultPath()
{
	// CWD 기준 경로가 실제로 존재하면 그쪽을 우선 사용 (개발 환경에서 소스 트리 파일을 직접 수정)
	std::filesystem::path CwdPath = std::filesystem::current_path() / L"Settings/ProjectSettings.ini";
	if (std::filesystem::exists(CwdPath))
		return FPaths::ToUtf8(CwdPath.wstring());

	return FPaths::ToUtf8(FPaths::ProjectSettingsFilePath());
}

void FProjectSettings::SaveToFile(const FString& Path) const
{
	using namespace json;

	JSON Root = Object();

	JSON ShadowObj = Object();
	ShadowObj[PSKey::bShadows] = Shadow.bEnabled;
	ShadowObj[PSKey::CSMResolution] = static_cast<int>(Shadow.CSMResolution);
	ShadowObj[PSKey::SpotAtlasResolution] = static_cast<int>(Shadow.SpotAtlasResolution);
	ShadowObj[PSKey::PointAtlasResolution] = static_cast<int>(Shadow.PointAtlasResolution);
	ShadowObj[PSKey::MaxSpotAtlasPages] = static_cast<int>(Shadow.MaxSpotAtlasPages);
	ShadowObj[PSKey::MaxPointAtlasPages] = static_cast<int>(Shadow.MaxPointAtlasPages);
	Root[PSKey::Shadow] = ShadowObj;

	JSON GameObj = Object();
	GameObj[PSKey::StartLevelName] = Game.StartLevelName;
	GameObj[PSKey::GameModeClassName] = Game.GameModeClassName;
	GameObj[PSKey::GameWindowWidth] = static_cast<int>(Game.GameWindowWidth);
	GameObj[PSKey::GameWindowHeight] = static_cast<int>(Game.GameWindowHeight);
	GameObj[PSKey::bStartFullscreen] = Game.bStartFullscreen;
	GameObj[PSKey::bLockEditorPIEResolution] = Game.bLockEditorPIEResolution;
	Root[PSKey::GameSection] = GameObj;

	std::wstring WPath = FPaths::ToWide(Path);
	std::filesystem::path FilePath(WPath);
	if (FilePath.has_parent_path())
		std::filesystem::create_directories(FilePath.parent_path());

	FILE* File = nullptr;
	_wfopen_s(&File, WPath.c_str(), L"w");
	if (!File)
	{
		UE_LOG("[ProjectSettings] SaveToFile failed: cannot open '%s' (errno=%d)", Path.c_str(), errno);
		return;
	}
	FString Dumped = Root.dump();
	fwrite(Dumped.c_str(), 1, Dumped.size(), File);
	fclose(File);
	UE_LOG("[ProjectSettings] Saved to '%s'", Path.c_str());
}

void FProjectSettings::LoadFromFile(const FString& Path)
{
	using namespace json;

	std::ifstream File(std::filesystem::path(FPaths::ToWide(Path)));
	if (!File.is_open())
		return;

	FString Content((std::istreambuf_iterator<char>(File)),
		std::istreambuf_iterator<char>());

	JSON Root = JSON::Load(Content);

	if (Root.hasKey(PSKey::GameSection))
	{
		JSON G = Root[PSKey::GameSection];
		if (G.hasKey(PSKey::StartLevelName))
			Game.StartLevelName = G[PSKey::StartLevelName].ToString();
		if (G.hasKey(PSKey::GameModeClassName))
			Game.GameModeClassName = G[PSKey::GameModeClassName].ToString();
		if (G.hasKey(PSKey::GameWindowWidth))
			Game.GameWindowWidth = ClampGameWindowWidth(G[PSKey::GameWindowWidth].ToInt());
		if (G.hasKey(PSKey::GameWindowHeight))
			Game.GameWindowHeight = ClampGameWindowHeight(G[PSKey::GameWindowHeight].ToInt());
		if (G.hasKey(PSKey::bStartFullscreen))
			Game.bStartFullscreen = G[PSKey::bStartFullscreen].ToBool();
		if (G.hasKey(PSKey::bLockEditorPIEResolution))
			Game.bLockEditorPIEResolution = G[PSKey::bLockEditorPIEResolution].ToBool();
	}

	if (Root.hasKey(PSKey::Shadow))
	{
		JSON S = Root[PSKey::Shadow];
		if (S.hasKey(PSKey::bShadows))
			Shadow.bEnabled = S[PSKey::bShadows].ToBool();
		if (S.hasKey(PSKey::CSMResolution))
		{
			int v = S[PSKey::CSMResolution].ToInt();
			Shadow.CSMResolution = static_cast<uint32>((std::max)(64, (std::min)(v, 8192)));
		}
		if (S.hasKey(PSKey::SpotAtlasResolution))
		{
			int v = S[PSKey::SpotAtlasResolution].ToInt();
			Shadow.SpotAtlasResolution = static_cast<uint32>((std::max)(64, (std::min)(v, 8192)));
		}
		if (S.hasKey(PSKey::PointAtlasResolution))
		{
			int v = S[PSKey::PointAtlasResolution].ToInt();
			Shadow.PointAtlasResolution = static_cast<uint32>((std::max)(64, (std::min)(v, 8192)));
		}
		if (S.hasKey(PSKey::MaxSpotAtlasPages))
		{
			int v = S[PSKey::MaxSpotAtlasPages].ToInt();
			Shadow.MaxSpotAtlasPages = static_cast<uint32>(v > 1 ? v : 1);
		}
		if (S.hasKey(PSKey::MaxPointAtlasPages))
		{
			int v = S[PSKey::MaxPointAtlasPages].ToInt();
			Shadow.MaxPointAtlasPages = static_cast<uint32>(v > 1 ? v : 1);
		}
	}
}
