////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSSound.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS Core Audio sound system implementation
//               Replaces DirectSound/FMOD for cross-platform audio support
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef MACOS_SOUND_H
#define MACOS_SOUND_H

#if defined(__APPLE__) && defined(__MACH__)

#include "ISound.h"
#include "SoundBuffer.h"
#include "SoundSystemCommon.h"
// Undefine BOOL to avoid conflict with macOS definition
#ifdef BOOL
#undef BOOL
#endif
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>
#include <AVFoundation/AVFoundation.h>
#include <map>
#include <vector>
#include <set>
#include <algorithm>

// Forward declarations
@class AVAudioEngine;
@class AVAudioPlayerNode;
@class AVAudioMixerNode;
@class AVAudioUnitReverb;

// macOS-specific sound implementation
class CMacOSSoundBuffer : public CSoundBuffer
{
public:
    CMacOSSoundBuffer();
    virtual ~CMacOSSoundBuffer();
    
    // ISoundBuffer interface
    virtual bool LoadWave(const char* sFileName, int nFlags = 0);
    virtual bool LoadOGG(const char* sFileName, int nFlags = 0);
    virtual void Release();
    virtual int GetLength();
    virtual int GetCurrentPos();
    virtual void SetCurrentPos(int nPos);
    virtual bool IsPlaying();
    virtual bool IsLooping();
    virtual void Play(bool bLoop = false, bool bLocked = false);
    virtual void Stop();
    virtual void Pause(bool bPause);
    virtual void SetVolume(int nVolume);
    virtual int GetVolume();
    virtual void SetPan(int nPan);
    virtual int GetPan();
    virtual void SetFrequency(int nFreq);
    virtual int GetFrequency();
    virtual void Set3DBuffer(bool b3D);
    virtual bool Is3DBuffer();
    virtual void SetPosition(const Vec3& pos);
    virtual void SetVelocity(const Vec3& vel);
    virtual void SetMinMaxDistance(float fMin, float fMax);
    virtual void SetCone(int nInnerAngle, int nOuterAngle, int nOuterVolume);
    
    // Getter and setter for internal use
    AVAudioPlayerNode* GetPlayerNode() const { return m_playerNode; }
    void SetPlayerNode(AVAudioPlayerNode* node) { m_playerNode = node; }
    AVAudioPCMBuffer* GetAudioBuffer() const { return m_audioBuffer; }
    bool IsLoaded() const { return m_audioBuffer != nullptr; }
    float GetMinDistance() const { return m_minDistance; }
    float GetMaxDistance() const { return m_maxDistance; }
    Vec3 GetPosition() const { return m_position; }
    
protected:
    SSoundBufferProps m_props;
    AVAudioPlayerNode* m_playerNode;
    AVAudioPCMBuffer* m_audioBuffer;
    AudioStreamBasicDescription m_format;
    
    // Audio properties
    float m_volume;
    float m_pan;
    float m_frequency;
    bool m_is3D;
    bool m_isPlaying;
    bool m_isLooping;
    
    // 3D audio properties
    Vec3 m_position;
    Vec3 m_velocity;
    float m_minDistance;
    float m_maxDistance;
    
    // Internal methods
    bool LoadAudioFile(const char* fileName);
    void UpdateSpatialAudio();
    
private:
    std::string m_fileName;
    int m_flags;
    int m_length;
    int m_currentPos;
};

// macOS sound implementation
class CMacOSSound : public ISound
{
public:
    CMacOSSound(CMacOSSoundBuffer* pBuffer);
    virtual ~CMacOSSound();
    
    // ISound interface implementation
    virtual void AddEventListener(ISoundEventListener* pListener) override;
    virtual void RemoveEventListener(ISoundEventListener* pListener) override;
    virtual bool IsPlaying() override;
    virtual bool IsPlayingVirtual() override;
    virtual bool IsLoading() override;
    virtual bool IsLoaded() override;
    virtual void Play(float fVolumeScale = 1.0f, bool bForceActiveState = true, bool bSetRatio = true) override;
    virtual void PlayFadeUnderwater(float fVolumeScale = 1.0f, bool bForceActiveState = true, bool bSetRatio = true) override;
    virtual void Stop() override;
    virtual const char* GetName() override;
    virtual const int GetId() override;
    virtual void SetLoopMode(bool bLoop) override;
    virtual bool Preload() override;
    virtual unsigned int GetCurrentSamplePos(bool bMilliSeconds = false) override;
    virtual void SetCurrentSamplePos(unsigned int nPos, bool bMilliSeconds) override;
    virtual void SetPitching(float fPitching) override;
    virtual void SetRatio(float fRatio) override;
    virtual int GetFrequency() override;
    virtual void SetPitch(int nPitch) override;
    virtual void SetPan(int nPan) override;
    virtual void SetMinMaxDistance(float fMinDist, float fMaxDist) override;
    virtual void SetConeAngles(float fInnerAngle, float fOuterAngle) override;
    virtual void AddToScaleGroup(int nGroup) override;
    virtual void RemoveFromScaleGroup(int nGroup) override;
    virtual void SetScaleGroup(unsigned int nGroupBits) override;
    virtual void SetVolume(int nVolume) override;
    virtual int GetVolume() override;
    virtual void SetPosition(const Vec3& pos) override;
    virtual const bool GetPosition(Vec3& vPos) override;
    virtual void SetVelocity(const Vec3& vel) override;
    virtual Vec3 GetVelocity() override;
    virtual void SetDirection(const Vec3& dir) override;
    virtual Vec3 GetDirection() override;
    virtual void SetLoopPoints(const int iLoopStart, const int iLoopEnd) override;
    virtual bool IsRelative() const override;
    virtual int AddRef() override;
    virtual int Release() override;
    
    // Additional pure virtual methods from ISound interface
    virtual void SetSoundProperties(float fFadingValue) override;
    virtual void FXEnable(int nEffectNumber) override;
    virtual void FXSetParamEQ(float fCenter, float fBandwidth, float fGain) override;
    virtual int GetLengthMs() override;
    virtual int GetLength() override;
    virtual void SetSoundPriority(unsigned char nSoundPriority) override;

private:
    CMacOSSoundBuffer* m_pBuffer;
    int m_nRefCount;
    std::string m_sName;
    int m_nId;
    Vec3 m_position;
    Vec3 m_velocity;
    Vec3 m_direction;
    bool m_bLoop;
    int m_nVolume;
    float m_fPitch;
    float m_fPan;
    float m_fMinDistance;
    float m_fMaxDistance;
    float m_fInnerAngle;
    float m_fOuterAngle;
    bool m_bIsRelative;
    
    // Additional member variables for missing functionality
    std::vector<ISoundEventListener*> m_eventListeners;
    std::set<int> m_scaleGroups;
    int m_loopStart;
    int m_loopEnd;
};

// macOS sound system implementation
class CMacOSSoundSystem : public CSoundSystemCommon
{
public:
    CMacOSSoundSystem(ISystem* pSystem);
    virtual ~CMacOSSoundSystem();
    
    // ISoundSystem interface
    virtual void Release() override;
    virtual IMusicSystem* CreateMusicSystem() override;
    virtual ISound* GetSound(int nSoundID) override;
    virtual void PlaySound(int nSoundID) override;
    virtual int SetMinSoundPriority(int nPriority) override;
    virtual void LockResources() override;
    virtual void UnlockResources() override;
    virtual void Update() override;
    virtual void SetListener(const CCamera& camera, const Vec3& vel) override;
    virtual ISound* LoadSound(const char* sFileName, int nFlags = 0) override;
    virtual void Silence() override;
    virtual void Pause(bool bPause, bool bResetVolume = false) override;
    virtual void Mute(bool bMute) override;
    virtual void SetMasterVolume(unsigned char nVol) override;
    virtual void SetMasterVolumeScale(float fScale, bool bForceRecalc = false) override;
    virtual bool SetGroupScale(int nGroup, float fScale) override;
    virtual void RecomputeSoundOcclusion(bool bRecomputeListener, bool bForceRecompute, bool bReset = false) override;
    virtual bool IsEAX(int version) override;
    virtual bool SetEaxListenerEnvironment(int nPreset, CS_REVERB_PROPERTIES* pProps = NULL, int nFlags = 0) override;
    virtual bool GetCurrentEaxEnvironment(int& nPreset, CS_REVERB_PROPERTIES& Props) override;
    virtual void GetSoundMemoryUsageInfo(size_t& nCurrentMemory, size_t& nMaxMemory) override;
    virtual int GetUsedVoices() override;
    virtual float GetCPUUsage() override;
    virtual float GetMusicVolume() override;
    virtual void CalcDirectionalAttenuation(Vec3& Pos, Vec3& Dir, float fConeInRadians) override;
    virtual float GetDirectionalAttenuationMaxScale() override;
    virtual bool UsingDirectionalAttenuation() override;
    virtual void GetMemoryUsage(ICrySizer* pSizer) override;
    virtual IVisArea* GetListenerArea() override;
    virtual Vec3 GetListenerPos() override;
    
protected:
    AVAudioEngine* m_audioEngine;
    AVAudioMixerNode* m_mixerNode;
    AVAudioUnitReverb* m_reverbUnit;
    
    // Audio settings
    int m_masterVolume;
    int m_soundVolume;
    int m_musicVolume;
    bool m_isDeaf;
    int m_minSoundPriority;

    // 3D audio settings
    float m_dopplerFactor;
    float m_distanceFactor;
    float m_rolloffFactor;
    
    // Listener properties
    Vec3 m_listenerPos;
    Vec3 m_listenerForward;
    Vec3 m_listenerUp;
    Vec3 m_listenerVel;
    
    // Sound buffer management
    std::vector<CMacOSSoundBuffer*> m_soundBuffers;
    std::map<std::string, CMacOSSoundBuffer*> m_loadedSounds;
    bool m_isInitialized;
    
    // Internal methods
    bool InitializeAudioEngine();
    void ShutdownAudioEngine();
    void Update3DAudio();
    AVAudioPCMBuffer* LoadAudioFile(const char* fileName, AudioStreamBasicDescription& format);
    
private:
    ISystem* m_pSystem;
};

// Utility functions for audio format conversion
AudioStreamBasicDescription CreateStandardFormat(int sampleRate, int channels, int bitsPerSample);
AVAudioPCMBuffer* ConvertToStandardFormat(AVAudioPCMBuffer* sourceBuffer, 
                                         const AudioStreamBasicDescription& targetFormat);

#endif // __APPLE__ && __MACH__

#endif // MACOS_SOUND_H
