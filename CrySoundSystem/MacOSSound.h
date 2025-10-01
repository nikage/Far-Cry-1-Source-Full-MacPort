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
// Undefine BOOL to avoid conflict with macOS definition
#ifdef BOOL
#undef BOOL
#endif
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>
#include <AVFoundation/AVFoundation.h>
#include <map>
#include <vector>

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
    virtual bool LoadWave(const char* sFileName, int nFlags = 0) override;
    virtual bool LoadOGG(const char* sFileName, int nFlags = 0) override;
    virtual void Release() override;
    virtual int GetLength() override;
    virtual int GetCurrentPos() override;
    virtual void SetCurrentPos(int nPos) override;
    virtual bool IsPlaying() override;
    virtual bool IsLooping() override;
    virtual void Play(bool bLoop = false, bool bLocked = false) override;
    virtual void Stop() override;
    virtual void Pause(bool bPause) override;
    virtual void SetVolume(int nVolume) override;
    virtual int GetVolume() override;
    virtual void SetPan(int nPan) override;
    virtual int GetPan() override;
    virtual void SetFrequency(int nFreq) override;
    virtual int GetFrequency() override;
    virtual void Set3DBuffer(bool b3D) override;
    virtual bool Is3DBuffer() override;
    virtual void SetPosition(const Vec3& pos) override;
    virtual void SetVelocity(const Vec3& vel) override;
    virtual void SetMinMaxDistance(float fMin, float fMax) override;
    virtual void SetCone(int nInnerAngle, int nOuterAngle, int nOuterVolume) override;
    
protected:
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

// macOS sound system implementation
class CMacOSSound : public ISound
{
public:
    CMacOSSound();
    virtual ~CMacOSSound();
    
    // ISound interface
    virtual bool Init(ISystem* pSystem) override;
    virtual void Release() override;
    virtual void Update() override;
    virtual void SetListener(const CCamera& camera, const Vec3& vel) override;
    virtual ISoundBuffer* LoadSound(const char* sFileName, int nFlags = 0) override;
    virtual void UnloadSound(ISoundBuffer* pBuffer) override;
    virtual ISoundBuffer* CreateSoundBuffer() override;
    virtual bool PlaySound(ISoundBuffer* pBuffer, const Vec3* pos = NULL, int nFlags = 0) override;
    virtual void StopSound(ISoundBuffer* pBuffer) override;
    virtual void PauseSound(ISoundBuffer* pBuffer, bool bPause) override;
    virtual void SetSoundVolume(int nVolume) override;
    virtual int GetSoundVolume() override;
    virtual void SetMusicVolume(int nVolume) override;
    virtual int GetMusicVolume() override;
    virtual void Silence() override;
    virtual void SetMasterVolume(int nVolume) override;
    virtual int GetMasterVolume() override;
    virtual void SetDeafness(bool bDeaf) override;
    virtual bool IsDeaf() override;
    virtual void SetDopplerFactor(float fFactor) override;
    virtual float GetDopplerFactor() override;
    virtual void SetDistanceFactor(float fFactor) override;
    virtual float GetDistanceFactor() override;
    virtual void SetRolloffFactor(float fFactor) override;
    virtual float GetRolloffFactor() override;
    virtual bool SetEAX(int nPreset) override;
    virtual int GetEAX() override;
    virtual void LoadSoundBuffers() override;
    virtual void FreeSoundBuffers() override;
    virtual void CalcSoundMood(IMusicMood* pMood, float fRadius) override;
    
protected:
    AVAudioEngine* m_audioEngine;
    AVAudioMixerNode* m_mixerNode;
    AVAudioUnitReverb* m_reverbUnit;
    
    // Audio settings
    int m_masterVolume;
    int m_soundVolume;
    int m_musicVolume;
    bool m_isDeaf;
    
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
    
    // Internal methods
    bool InitializeAudioEngine();
    void ShutdownAudioEngine();
    void Update3DAudio();
    AVAudioPCMBuffer* LoadAudioFile(const char* fileName, AudioStreamBasicDescription& format);
    
private:
    ISystem* m_pSystem;
    bool m_isInitialized;
};

// Utility functions for audio format conversion
AudioStreamBasicDescription CreateStandardFormat(int sampleRate, int channels, int bitsPerSample);
AVAudioPCMBuffer* ConvertToStandardFormat(AVAudioPCMBuffer* sourceBuffer, 
                                         const AudioStreamBasicDescription& targetFormat);

#endif // __APPLE__ && __MACH__

#endif // MACOS_SOUND_H
