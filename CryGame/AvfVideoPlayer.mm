#include "StdAfx.h"
#include "AvfVideoPlayer.h"
#include "UISystem.h"
#include "IRenderer.h"
#include <vector>

#if defined(__APPLE__)

#ifdef BOOL
#undef BOOL
#endif
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

namespace
{
inline double GetHostTimeSeconds()
{
	const CMTime time = CMClockGetTime(CMClockGetHostTimeClock());
	if (time.timescale == 0)
	{
		return 0.0;
	}
	return static_cast<double>(time.value) / static_cast<double>(time.timescale);
}
}

struct CAvfVideoPlayer::Impl
{
	explicit Impl(CUISystem* system)
		: uiSystem(system)
		, player(nil)
		, playerItem(nil)
		, videoOutput(nil)
		, observer(nil)
		, width(0)
		, height(0)
		, finished(false)
		, audioEnabled(true)
	{
	}

	~Impl()
	{
		Release();
	}

	bool Load(const char* path, bool enableAudio)
	{
		Release();
		if (!path || !path[0])
		{
			return false;
		}
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
		NSString* nsPath = [NSString stringWithUTF8String:path];
		if (![[NSFileManager defaultManager] fileExistsAtPath:nsPath])
		{
			[pool release];
			return false;
		}
		NSURL* url = [NSURL fileURLWithPath:nsPath];
		AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url options:nil];
		NSArray<AVAssetTrack*>* tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
		if (tracks.count == 0)
		{
			[pool release];
			return false;
		}
		AVAssetTrack* track = tracks.firstObject;
		width = static_cast<int>(track.naturalSize.width);
		height = static_cast<int>(track.naturalSize.height);
		NSDictionary* attributes = @{
			(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
		};
		playerItem = [[AVPlayerItem alloc] initWithAsset:asset];
		videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attributes];
		[playerItem addOutput:videoOutput];
		player = [[AVPlayer alloc] initWithPlayerItem:playerItem];
		player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
		player.muted = enableAudio ? NO : YES;
		audioEnabled = enableAudio;
		finished = false;
		__block Impl* weakSelf = this;
		observer = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
			object:playerItem
			queue:[NSOperationQueue mainQueue]
			usingBlock:^(NSNotification*) {
				if (weakSelf)
				{
					weakSelf->finished = true;
				}
			}];
		[pool release];
		return true;
	}

	void Release()
	{
		if (observer)
		{
			[[NSNotificationCenter defaultCenter] removeObserver:observer];
			observer = nil;
		}
		if (player)
		{
			[player pause];
			[player release];
			player = nil;
		}
		if (videoOutput)
		{
			[videoOutput release];
			videoOutput = nil;
		}
		if (playerItem)
		{
			[playerItem release];
			playerItem = nil;
		}
		width = 0;
		height = 0;
		finished = false;
		frameBuffer.clear();
	}

	bool Play()
	{
		if (!player)
		{
			return false;
		}
		finished = false;
		[player seekToTime:kCMTimeZero];
		[player play];
		return true;
	}

	void Stop()
	{
		if (player)
		{
			[player pause];
		}
	}

	bool Pause(bool pause)
	{
		if (!player)
		{
			return false;
		}
		if (pause)
		{
			[player pause];
		}
		else
		{
			[player play];
		}
		return true;
	}

	bool IsPlaying() const
	{
		if (!player)
		{
			return false;
		}
		return player.rate > 0.0f;
	}

	bool UpdateTexture(int textureId, IRenderer* renderer)
	{
		if (!player || !videoOutput || textureId < 0 || !renderer)
		{
			return false;
		}
		const double hostTime = GetHostTimeSeconds();
		CMTime itemTime = [videoOutput itemTimeForHostTime:hostTime];
		CVPixelBufferRef buffer = [videoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:nil];
		if (!buffer)
		{
			return false;
		}
		CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
		const size_t bufferWidth = CVPixelBufferGetWidth(buffer);
		const size_t bufferHeight = CVPixelBufferGetHeight(buffer);
		const size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
		uint8_t* base = static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(buffer));
		if (bufferWidth == 0 || bufferHeight == 0 || !base)
		{
			CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
			CFRelease(buffer);
			return false;
		}
		frameBuffer.resize(bufferWidth * bufferHeight * 4);
		for (size_t y = 0; y < bufferHeight; ++y)
		{
			const uint8_t* srcRow = base + y * bytesPerRow;
			uint8_t* dstRow = frameBuffer.data() + y * bufferWidth * 4;
			for (size_t x = 0; x < bufferWidth; ++x)
			{
				const uint8_t b = srcRow[x * 4 + 0];
				const uint8_t g = srcRow[x * 4 + 1];
				const uint8_t r = srcRow[x * 4 + 2];
				const uint8_t a = srcRow[x * 4 + 3];
				dstRow[x * 4 + 0] = r;
				dstRow[x * 4 + 1] = g;
				dstRow[x * 4 + 2] = b;
				dstRow[x * 4 + 3] = a;
			}
		}
		CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
		CFRelease(buffer);
		renderer->UpdateTextureInVideoMemory(textureId, frameBuffer.data(), 0, 0, static_cast<unsigned int>(bufferWidth), static_cast<unsigned int>(bufferHeight), eTF_8888);
		return true;
	}

	void SetAudioEnabled(bool enabled)
	{
		audioEnabled = enabled;
		if (player)
		{
			player.muted = enabled ? NO : YES;
		}
	}

	int width;
	int height;
	bool finished;
	bool audioEnabled;
	CUISystem* uiSystem;
	AVPlayer* player;
	AVPlayerItem* playerItem;
	AVPlayerItemVideoOutput* videoOutput;
	id observer;
	std::vector<uint8_t> frameBuffer;
};

#else

struct CAvfVideoPlayer::Impl
{
	explicit Impl(CUISystem*) {}
	bool Load(const char*, bool) { return false; }
	void Release() {}
	bool Play() { return false; }
	void Stop() {}
	bool Pause(bool) { return false; }
	bool IsPlaying() const { return false; }
	bool UpdateTexture(int, IRenderer*) { return false; }
	void SetAudioEnabled(bool) {}
	int width = 0;
	int height = 0;
	bool finished = false;
	bool audioEnabled = true;
};

#endif

CAvfVideoPlayer::CAvfVideoPlayer(CUISystem* system)
{
	m_impl = new Impl(system);
}

CAvfVideoPlayer::~CAvfVideoPlayer()
{
	delete m_impl;
	m_impl = nullptr;
}

bool CAvfVideoPlayer::Load(const char* path, bool enableAudio)
{
	return m_impl->Load(path, enableAudio);
}

void CAvfVideoPlayer::Release()
{
	m_impl->Release();
}

bool CAvfVideoPlayer::Play()
{
	return m_impl->Play();
}

void CAvfVideoPlayer::Stop()
{
	m_impl->Stop();
}

bool CAvfVideoPlayer::Pause(bool pause)
{
	return m_impl->Pause(pause);
}

bool CAvfVideoPlayer::IsPlaying() const
{
	return m_impl->IsPlaying();
}

bool CAvfVideoPlayer::UpdateTexture(int textureId, IRenderer* renderer)
{
	return m_impl->UpdateTexture(textureId, renderer);
}

int CAvfVideoPlayer::GetWidth() const
{
	return m_impl->width;
}

int CAvfVideoPlayer::GetHeight() const
{
	return m_impl->height;
}

bool CAvfVideoPlayer::HasFinished() const
{
	return m_impl->finished;
}

void CAvfVideoPlayer::SetAudioEnabled(bool enabled)
{
	m_impl->SetAudioEnabled(enabled);
}


