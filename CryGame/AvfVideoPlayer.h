#pragma once

#include "ISystem.h"

class CUISystem;
class IRenderer;

class CAvfVideoPlayer
{
public:
	explicit CAvfVideoPlayer(CUISystem* system);
	~CAvfVideoPlayer();

	bool Load(const char* path, bool enableAudio);
	void Release();
	bool Play();
	void Stop();
	bool Pause(bool pause);
	bool IsPlaying() const;
	bool UpdateTexture(int textureId, IRenderer* renderer);
	int GetWidth() const;
	int GetHeight() const;
	bool HasFinished() const;
	void SetAudioEnabled(bool enabled);

private:
	struct Impl;
	Impl* m_impl;
};

