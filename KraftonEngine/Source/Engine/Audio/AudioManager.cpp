#include "AudioManager.h"
#include "Core/Logging/Log.h"
#include "Platform/Paths.h"
#include <algorithm>

bool FAudioManager::Initialize()
{
	if (FMOD::System_Create(&System) != FMOD_OK || !System)
	{
		UE_LOG("Failed to create FMOD system.");
		return false;
	}

	if (System->init(512, FMOD_INIT_NORMAL, nullptr) != FMOD_OK)
	{
		UE_LOG("Failed to initialize FMOD system.");
		Shutdown();
		return false;
	}

	System->getMasterChannelGroup(&MasterGroup);

	LoadDefaultAudios();

	return true;
}

void FAudioManager::Shutdown()
{
	if (!System)
	{
		MasterGroup = nullptr;
		BGMChannel = nullptr;
		ManagedChannels.clear();
		LoopChannels.clear();
		Audios.clear();
		return;
	}

	StopAllPlayback();
	MasterGroup = nullptr;
	System->update();

	for (auto& Pair : Audios)
	{
		if (Pair.second.Sound)
		{
			Pair.second.Sound->release();
		}
	}
	Audios.clear();

	System->update();
	System->close();
	System->release();
	System = nullptr;
}

void FAudioManager::Tick()
{
	if (System)
	{
		System->update();
	}
}

bool FAudioManager::LoadAudio(const FString& Key, const FString& Path, bool bLoop)
{
	if (!System)
	{
		return false;
	}

	// 같은 키가 같은 파일/루프 모드로 이미 로드돼 있으면 그대로 재사용 —
	// 씬 BeginPlay마다 AudioData 전체를 다시 Load해도 재디코드가 없어
	// PIE 시작/씬 전환 렉을 막는다. 경로나 루프 모드가 바뀐 경우에만 재로드.
	auto It = Audios.find(Key);
	if (It != Audios.end() && It->second.Sound
		&& It->second.Path == Path && It->second.bLoop == bLoop)
	{
		return true;
	}

	FString FullPath = FPaths::ToUtf8(FPaths::Combine(FPaths::AudioDir(), FPaths::ToWide(Path)));

	FMOD::Sound* Sound = nullptr;
	const FMOD_MODE Mode = FMOD_DEFAULT | (bLoop ? FMOD_LOOP_NORMAL : FMOD_LOOP_OFF);

	if (System->createSound(FullPath.c_str(), Mode, nullptr, &Sound) != FMOD_OK)
	{
		return false;
	}

	if (It != Audios.end() && It->second.Sound)
	{
		It->second.Sound->release();
	}

	Audios[Key] = { Sound, Path, bLoop };
	return true;
}

void FAudioManager::PlayAudio(const FString& Key, float Volume)
{
	if (!System || !Audios.contains(Key))
	{
		return;
	}

	FMOD::Channel* Channel = nullptr;
	System->playSound(Audios[Key].Sound, nullptr, false, &Channel);

	if (Channel)
	{
		Channel->setVolume(Volume);
	}
}

void FAudioManager::PlayManagedAudio(const FString& Key, const FString& ChannelName, float Volume)
{
	if (!System || !Audios.contains(Key) || ChannelName.empty())
	{
		return;
	}

	if (FMOD::Channel* ExistingChannel = FindPlayingManagedChannel(ChannelName))
	{
		ExistingChannel->stop();
		ManagedChannels.erase(ChannelName);
	}

	FMOD::Channel* Channel = nullptr;
	System->playSound(Audios[Key].Sound, nullptr, false, &Channel);

	if (Channel)
	{
		Channel->setVolume(std::clamp(Volume, 0.0f, 1.0f));
		ManagedChannels[ChannelName] = Channel;
	}
}

void FAudioManager::PlayBGM(const FString& Key, float Volume)
{
	if (!System || !Audios.contains(Key))
	{
		return;
	}

	StopBGM();
	System->playSound(Audios[Key].Sound, nullptr, false, &BGMChannel);

	if (BGMChannel)
	{
		BGMChannel->setVolume(Volume);
	}
}

void FAudioManager::SetBGMVolume(float Volume)
{
	if (!BGMChannel)
	{
		return;
	}

	bool bIsPlaying = false;
	if (BGMChannel->isPlaying(&bIsPlaying) != FMOD_OK || !bIsPlaying)
	{
		BGMChannel = nullptr;
		return;
	}

	BGMChannel->setVolume(std::clamp(Volume, 0.0f, 1.0f));
}

void FAudioManager::StopBGM()
{
	if (BGMChannel)
	{
		BGMChannel->stop();
		BGMChannel = nullptr;
	}
}

void FAudioManager::StopAllPlayback()
{
	if (!System)
	{
		BGMChannel = nullptr;
		ManagedChannels.clear();
		LoopChannels.clear();
		return;
	}

	StopBGM();
	for (auto& Pair : ManagedChannels)
	{
		if (Pair.second)
		{
			Pair.second->stop();
		}
	}
	ManagedChannels.clear();
	StopAllLoops();

	// Master group stop catches fire-and-forget one-shot channels that are not
	// individually tracked by the audio manager. This keeps PIE end / scene
	// teardown from leaking sound across world boundaries.
	if (MasterGroup)
	{
		MasterGroup->stop();
	}

	System->update();
}

void FAudioManager::PlayLoop(const FString& Key, const FString& LoopName, float Volume, float Pitch)
{
	if (!System || !Audios.contains(Key) || LoopName.empty())
	{
		return;
	}

	if (FMOD::Channel* ExistingChannel = FindPlayingLoopChannel(LoopName))
	{
		ExistingChannel->setVolume(std::clamp(Volume, 0.0f, 1.0f));
		ExistingChannel->setPitch(std::clamp(Pitch, 0.1f, 3.0f));
		return;
	}

	FMOD::Channel* Channel = nullptr;
	System->playSound(Audios[Key].Sound, nullptr, false, &Channel);

	if (Channel)
	{
		Channel->setMode(FMOD_LOOP_NORMAL);
		Channel->setVolume(std::clamp(Volume, 0.0f, 1.0f));
		Channel->setPitch(std::clamp(Pitch, 0.1f, 3.0f));
		LoopChannels[LoopName] = Channel;
	}
}

void FAudioManager::StopLoop(const FString& LoopName)
{
	if (!LoopChannels.contains(LoopName))
	{
		return;
	}

	if (LoopChannels[LoopName])
	{
		LoopChannels[LoopName]->stop();
	}
	LoopChannels.erase(LoopName);
}

void FAudioManager::StopManagedAudio(const FString& ChannelName)
{
	if (!ManagedChannels.contains(ChannelName))
	{
		return;
	}

	if (ManagedChannels[ChannelName])
	{
		ManagedChannels[ChannelName]->stop();
	}
	ManagedChannels.erase(ChannelName);
}

void FAudioManager::StopAllLoops()
{
	for (auto& Pair : LoopChannels)
	{
		if (Pair.second)
		{
			Pair.second->stop();
		}
	}
	LoopChannels.clear();
}

void FAudioManager::SetLoopVolume(const FString& LoopName, float Volume)
{
	if (FMOD::Channel* Channel = FindPlayingLoopChannel(LoopName))
	{
		Channel->setVolume(std::clamp(Volume, 0.0f, 1.0f));
	}
}

void FAudioManager::SetLoopPitch(const FString& LoopName, float Pitch)
{
	if (FMOD::Channel* Channel = FindPlayingLoopChannel(LoopName))
	{
		Channel->setPitch(std::clamp(Pitch, 0.1f, 3.0f));
	}
}

bool FAudioManager::IsLoopPlaying(const FString& LoopName)
{
	return FindPlayingLoopChannel(LoopName) != nullptr;
}

FMOD::Channel* FAudioManager::FindPlayingManagedChannel(const FString& ChannelName)
{
	if (!ManagedChannels.contains(ChannelName))
	{
		return nullptr;
	}

	FMOD::Channel* Channel = ManagedChannels[ChannelName];
	bool bIsPlaying = false;
	if (!Channel || Channel->isPlaying(&bIsPlaying) != FMOD_OK || !bIsPlaying)
	{
		ManagedChannels.erase(ChannelName);
		return nullptr;
	}

	return Channel;
}

FMOD::Channel* FAudioManager::FindPlayingLoopChannel(const FString& LoopName)
{
	if (!LoopChannels.contains(LoopName))
	{
		return nullptr;
	}

	FMOD::Channel* Channel = LoopChannels[LoopName];
	bool bIsPlaying = false;
	if (!Channel || Channel->isPlaying(&bIsPlaying) != FMOD_OK || !bIsPlaying)
	{
		LoopChannels.erase(LoopName);
		return nullptr;
	}

	return Channel;
}

void FAudioManager::SetMasterVolume(float Volume)
{
	if (MasterGroup)
	{
		MasterGroup->setVolume(Volume);
	}
}

void FAudioManager::LoadDefaultAudios()
{
	LoadAudio("CityBgm", "city_bgm.mp3", true);
	LoadAudio("Phase_EscapePolice", "phase_escapepolice.wav", true);
	LoadAudio("Phase_Meteor", "phase_meteor.mp3", true);
	LoadAudio("Click", "pop.mp3");
	LoadAudio("CarEngineLoop", "car_engine_loop.mp3", true);
	LoadAudio("Notify", "notify.mp3");
	LoadAudio("Complete", "complete.mp3");
	LoadAudio("Crash", "crash.mp3");
	LoadAudio("Water", "water.mp3", true);
	LoadAudio("Siren", "siren.mp3", true);
	LoadAudio("Fueling", "fueling.mp3", true);
	LoadAudio("ScoreUp", "score_up.mp3");
	LoadAudio("MeteorBoom", "meteor_boom.mp3");
	LoadAudio("MeteorFall", "meteor_fall.mp3");
	LoadAudio("Whoosh", "whoosh.mp3");

	LoadAudio("bgm_title_0", "BgmTitle_0.mp3", true);
	LoadAudio("bgm_title_1", "BgmTitle_1.mp3", true);
	LoadAudio("bgm_gameplay_0", "BgmGameplay_0.mp3", true);
	LoadAudio("bgm_gameplay_1", "BgmGameplay_1.mp3", true);
	LoadAudio("bgm_main_0", "BgmMain_0.mp3", true);
	LoadAudio("bgm_cutscene", "BgmCutScene.mp3", true);
	LoadAudio("bgm_collector_truck", "BgmCollectorTruck.mp3", true);
	LoadAudio("sfx_foot", "SfxFootstep.mp3");
	LoadAudio("sfx_result_high", "SfxResultHigh.mp3");
	LoadAudio("sfx_result_medium", "SfxResultMedium.mp3");
	LoadAudio("sfx_result_low", "SfxResultLow.mp3");
	LoadAudio("sfx_gun_shoot", "SfxGunCollectShoot.mp3");
	LoadAudio("sfx_gun_attack_shoot", "SfxGunAttackShoot.mp3");
	LoadAudio("sfx_gun_mode_change", "SfxGunModeChange.mp3");
	LoadAudio("sfx_beam_grab", "SfxBeamGrab.mp3");
	LoadAudio("sfx_collect", "SfxCollect.mp3");
	LoadAudio("sfx_hit", "SfxHit.mp3");
	LoadAudio("sfx_ui_click", "SfxUiClick.mp3");
	LoadAudio("sfx_ui_hover", "SfxUiHover.mp3");
	LoadAudio("sfx_game_over", "SfxGameOver.mp3");
	LoadAudio("sfx_revive", "SfxRevivedRagdoll.mp3");
}
