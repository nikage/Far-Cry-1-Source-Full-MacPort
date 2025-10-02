////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSSound.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS Core Audio sound system implementation
//               Replaces DirectSound/FMOD for cross-platform audio support
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#include "MacOSSound.h"
#include "ISound.h"
#include "SoundBuffer.h"
#include "SoundSystemCommon.h"
#include <algorithm>
#include <iostream>

// CMacOSSoundBuffer implementation
CMacOSSoundBuffer::CMacOSSoundBuffer()
    : CSoundBuffer(nullptr, m_props)
    , m_props("", 0)
    , m_playerNode(nil)
    , m_audioBuffer(nil)
    , m_volume(1.0f)
    , m_pan(0.0f)
    , m_frequency(44100.0f)
    , m_is3D(false)
    , m_isPlaying(false)
    , m_isLooping(false)
    , m_minDistance(1.0f)
    , m_maxDistance(100.0f)
    , m_flags(0)
    , m_length(0)
    , m_currentPos(0)
{
    // Initialize audio format
    m_format.mSampleRate = 44100.0;
    m_format.mFormatID = kAudioFormatLinearPCM;
    m_format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    m_format.mBytesPerPacket = 4;
    m_format.mFramesPerPacket = 1;
    m_format.mBytesPerFrame = 4;
    m_format.mChannelsPerFrame = 2;
    m_format.mBitsPerChannel = 16;
}

CMacOSSoundBuffer::~CMacOSSoundBuffer()
{
    if (m_playerNode)
    {
        [m_playerNode stop];
        [m_playerNode release];
    }
    
    if (m_audioBuffer)
    {
        [m_audioBuffer release];
    }
}

bool CMacOSSoundBuffer::LoadWave(const char* sFileName, int nFlags)
{
    if (!sFileName)
        return false;
    
    m_fileName = sFileName;
    m_flags = nFlags;
    
    // Load audio file using AVAudioFile
    NSError* error = nil;
    NSURL* fileURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:sFileName]];
    AVAudioFile* audioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    
    if (!audioFile || error)
    {
        if (error)
        {
            NSLog(@"Error loading audio file: %@", [error localizedDescription]);
        }
        return false;
    }
    
    // Get the format
    AVAudioFormat* format = [audioFile processingFormat];
    // Store the format for later use - use a simpler approach
    m_format.mSampleRate = [format sampleRate];
    m_format.mFormatID = kAudioFormatLinearPCM;
    m_format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    m_format.mBytesPerPacket = 4;
    m_format.mFramesPerPacket = 1;
    m_format.mBytesPerFrame = 4;
    m_format.mChannelsPerFrame = [format channelCount];
    m_format.mBitsPerChannel = 16;
    
    // Read the entire file into a buffer
    AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:(AVAudioFrameCount)[audioFile length]];
    
    if (![audioFile readIntoBuffer:buffer error:&error])
    {
        NSLog(@"Error reading audio file: %@", [error localizedDescription]);
        return false;
    }
    
    m_audioBuffer = buffer;
    m_length = (int)[buffer frameLength];
    
    [audioFile release];
    return true;
}

bool CMacOSSoundBuffer::LoadOGG(const char* sFileName, int nFlags)
{
    // For now, treat OGG files the same as WAV files
    // TODO: Implement proper OGG decoding
    return LoadWave(sFileName, nFlags);
}

void CMacOSSoundBuffer::Release()
{
    if (m_playerNode)
    {
        [m_playerNode stop];
        [m_playerNode release];
        m_playerNode = nil;
    }
    
    if (m_audioBuffer)
    {
        [m_audioBuffer release];
        m_audioBuffer = nil;
    }
}

int CMacOSSoundBuffer::GetLength()
{
    return m_length;
}

int CMacOSSoundBuffer::GetCurrentPos()
{
    return m_currentPos;
}

void CMacOSSoundBuffer::SetCurrentPos(int nPos)
{
    m_currentPos = nPos;
    // TODO: Implement seeking in AVAudioPlayerNode
}

bool CMacOSSoundBuffer::IsPlaying()
{
    return m_isPlaying && m_playerNode && [m_playerNode isPlaying];
}

bool CMacOSSoundBuffer::IsLooping()
{
    return m_isLooping;
}

void CMacOSSoundBuffer::Play(bool bLoop, bool bLocked)
{
    if (!m_playerNode || !m_audioBuffer)
        return;
    
    m_isLooping = bLoop;
    m_isPlaying = true;
    
    if (bLoop)
    {
        [m_playerNode scheduleBuffer:m_audioBuffer atTime:nil 
            options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
    }
    else
    {
        [m_playerNode scheduleBuffer:m_audioBuffer atTime:nil options:0 completionHandler:^{
            this->m_isPlaying = false;
        }];
    }
    
    [m_playerNode play];
}

void CMacOSSoundBuffer::Stop()
{
    if (m_playerNode)
    {
        [m_playerNode stop];
        m_isPlaying = false;
    }
}

void CMacOSSoundBuffer::Pause(bool bPause)
{
    if (!m_playerNode)
        return;
    
    if (bPause)
    {
        [m_playerNode pause];
    }
    else
    {
        [m_playerNode play];
    }
}

void CMacOSSoundBuffer::SetVolume(int nVolume)
{
    m_volume = nVolume / 100.0f; // Convert from 0-100 to 0.0-1.0
    
    if (m_playerNode)
    {
        [m_playerNode setVolume:m_volume];
    }
}

int CMacOSSoundBuffer::GetVolume()
{
    return (int)(m_volume * 100.0f);
}

void CMacOSSoundBuffer::SetPan(int nPan)
{
    m_pan = nPan / 100.0f; // Convert from -100 to 100 to -1.0 to 1.0
    
    if (m_playerNode)
    {
        [m_playerNode setPan:m_pan];
    }
}

int CMacOSSoundBuffer::GetPan()
{
    return (int)(m_pan * 100.0f);
}

void CMacOSSoundBuffer::SetFrequency(int nFreq)
{
    m_frequency = (float)nFreq;
    // TODO: Implement frequency change in AVAudioPlayerNode
}

int CMacOSSoundBuffer::GetFrequency()
{
    return (int)m_frequency;
}

void CMacOSSoundBuffer::Set3DBuffer(bool b3D)
{
    m_is3D = b3D;
}

bool CMacOSSoundBuffer::Is3DBuffer()
{
    return m_is3D;
}

void CMacOSSoundBuffer::SetPosition(const Vec3& pos)
{
    m_position = pos;
    UpdateSpatialAudio();
}

void CMacOSSoundBuffer::SetVelocity(const Vec3& vel)
{
    m_velocity = vel;
}

void CMacOSSoundBuffer::SetMinMaxDistance(float fMin, float fMax)
{
    m_minDistance = fMin;
    m_maxDistance = fMax;
}

void CMacOSSoundBuffer::SetCone(int nInnerAngle, int nOuterAngle, int nOuterVolume)
{
    // TODO: Implement cone parameters
}

void CMacOSSoundBuffer::UpdateSpatialAudio()
{
    // TODO: Implement 3D spatial audio using AVAudio3DMixerNode
    // This would require integration with the main audio engine
}

// CMacOSSound implementation
CMacOSSound::CMacOSSound(CMacOSSoundBuffer* pBuffer)
    : m_pBuffer(pBuffer)
    , m_nRefCount(1)
    , m_sName("")
    , m_nId(0)
    , m_position(0, 0, 0)
    , m_velocity(0, 0, 0)
    , m_direction(0, 0, 1)
    , m_bLoop(false)
    , m_nVolume(100)
    , m_fPitch(1.0f)
    , m_fPan(0.0f)
    , m_fMinDistance(1.0f)
    , m_fMaxDistance(100.0f)
    , m_fInnerAngle(360.0f)
    , m_fOuterAngle(360.0f)
    , m_bIsRelative(false)
    , m_loopStart(0)
    , m_loopEnd(0)
{
    if (m_pBuffer)
    {
        m_pBuffer->AddRef();
    }
}

CMacOSSound::~CMacOSSound()
{
    if (m_pBuffer)
    {
        m_pBuffer->Release();
    }
}

// ISound interface implementation
void CMacOSSound::AddEventListener(ISoundEventListener* pListener) 
{
    if (pListener)
    {
        m_eventListeners.push_back(pListener);
    }
}

void CMacOSSound::RemoveEventListener(ISoundEventListener* pListener) 
{
    if (pListener)
    {
        auto it = std::find(m_eventListeners.begin(), m_eventListeners.end(), pListener);
        if (it != m_eventListeners.end())
        {
            m_eventListeners.erase(it);
        }
    }
}

bool CMacOSSound::IsPlaying()
{
    return m_pBuffer && m_pBuffer->IsPlaying();
}

bool CMacOSSound::IsPlayingVirtual()
{
    return IsPlaying();
}

bool CMacOSSound::IsLoading()
{
    return false; // For now, loading is synchronous
}

bool CMacOSSound::IsLoaded()
{
    return m_pBuffer != nullptr;
}

void CMacOSSound::Play(float fVolumeScale, bool bForceActiveState, bool bSetRatio)
{
    if (m_pBuffer)
    {
        m_pBuffer->Play(m_bLoop);
    }
}

void CMacOSSound::PlayFadeUnderwater(float fVolumeScale, bool bForceActiveState, bool bSetRatio)
{
    Play(fVolumeScale, bForceActiveState, bSetRatio);
}

void CMacOSSound::Stop()
{
    if (m_pBuffer)
    {
        m_pBuffer->Stop();
    }
}

const char* CMacOSSound::GetName()
{
    return m_sName.c_str();
}

const int CMacOSSound::GetId()
{
    return m_nId;
}

void CMacOSSound::SetLoopMode(bool bLoop)
{
    m_bLoop = bLoop;
}

bool CMacOSSound::Preload()
{
    return m_pBuffer != nullptr;
}

unsigned int CMacOSSound::GetCurrentSamplePos(bool bMilliSeconds)
{
    return m_pBuffer ? m_pBuffer->GetCurrentPos() : 0;
}

void CMacOSSound::SetCurrentSamplePos(unsigned int nPos, bool bMilliSeconds) 
{
    if (m_pBuffer)
    {
        m_pBuffer->SetCurrentPos(nPos);
    }
}

void CMacOSSound::SetPitching(float fPitching) 
{
    m_fPitch = fPitching;
    if (m_pBuffer && m_pBuffer->GetPlayerNode())
    {
        [m_pBuffer->GetPlayerNode() setRate:fPitching];
    }
}

void CMacOSSound::SetRatio(float fRatio) 
{
    int newVolume = (int)(m_nVolume * fRatio);
    SetVolume(newVolume);
}

int CMacOSSound::GetFrequency()
{
    return m_pBuffer ? m_pBuffer->GetFrequency() : 44100;
}

void CMacOSSound::SetPitch(int nPitch)
{
    m_fPitch = nPitch / 100.0f;
    SetPitching(m_fPitch);
}

void CMacOSSound::SetPan(int nPan)
{
    m_fPan = nPan / 100.0f;
    if (m_pBuffer)
    {
        m_pBuffer->SetPan(nPan);
    }
}

void CMacOSSound::SetMinMaxDistance(float fMinDist, float fMaxDist)
{
    m_fMinDistance = fMinDist;
    m_fMaxDistance = fMaxDist;
    if (m_pBuffer)
    {
        m_pBuffer->SetMinMaxDistance(fMinDist, fMaxDist);
    }
}

void CMacOSSound::SetConeAngles(float fInnerAngle, float fOuterAngle)
{
    m_fInnerAngle = fInnerAngle;
    m_fOuterAngle = fOuterAngle;
}

void CMacOSSound::AddToScaleGroup(int nGroup) 
{
    if (nGroup >= 0 && nGroup < MAX_SOUNDSCALE_GROUPS)
    {
        m_scaleGroups.insert(nGroup);
    }
}

void CMacOSSound::RemoveFromScaleGroup(int nGroup) 
{
    m_scaleGroups.erase(nGroup);
}

void CMacOSSound::SetScaleGroup(unsigned int nGroupBits) 
{
    m_scaleGroups.clear();
    for (int i = 0; i < MAX_SOUNDSCALE_GROUPS; i++)
    {
        if (nGroupBits & (1 << i))
        {
            m_scaleGroups.insert(i);
        }
    }
}

void CMacOSSound::SetVolume(int nVolume)
{
    m_nVolume = nVolume;
    if (m_pBuffer)
    {
        m_pBuffer->SetVolume(nVolume);
    }
}

int CMacOSSound::GetVolume()
{
    return m_nVolume;
}

void CMacOSSound::SetPosition(const Vec3& pos)
{
    m_position = pos;
    if (m_pBuffer)
    {
        m_pBuffer->SetPosition(pos);
    }
}

const bool CMacOSSound::GetPosition(Vec3& vPos)
{
    vPos = m_position;
    return true;
}

void CMacOSSound::SetVelocity(const Vec3& vel)
{
    m_velocity = vel;
    if (m_pBuffer)
    {
        m_pBuffer->SetVelocity(vel);
    }
}

Vec3 CMacOSSound::GetVelocity()
{
    return m_velocity;
}

void CMacOSSound::SetDirection(const Vec3& dir)
{
    m_direction = dir;
}

Vec3 CMacOSSound::GetDirection()
{
    return m_direction;
}

void CMacOSSound::SetLoopPoints(const int iLoopStart, const int iLoopEnd) 
{
    m_loopStart = iLoopStart;
    m_loopEnd = iLoopEnd;
}

bool CMacOSSound::IsRelative() const
{
    return m_bIsRelative;
}

int CMacOSSound::AddRef()
{
    return ++m_nRefCount;
}

int CMacOSSound::Release()
{
    int refCount = --m_nRefCount;
    if (refCount <= 0)
    {
        delete this;
    }
    return refCount;
}

// Additional missing pure virtual methods
void CMacOSSound::SetSoundProperties(float fFadingValue)
{
    // TODO: Implement sound properties
}

void CMacOSSound::FXEnable(int nEffectNumber)
{
    // TODO: Implement FX effects
}

void CMacOSSound::FXSetParamEQ(float fCenter, float fBandwidth, float fGain)
{
    // TODO: Implement parametric EQ
}

int CMacOSSound::GetLengthMs()
{
    return m_pBuffer ? (m_pBuffer->GetLength() * 1000) / 44100 : 0;
}

int CMacOSSound::GetLength()
{
    return m_pBuffer ? m_pBuffer->GetLength() : 0;
}

void CMacOSSound::SetSoundPriority(unsigned char nSoundPriority)
{
    // TODO: Implement sound priority
}

// CMacOSSoundSystem implementation
CMacOSSoundSystem::CMacOSSoundSystem(ISystem* pSystem)
    : CSoundSystemCommon(pSystem)
    , m_audioEngine(nil)
    , m_mixerNode(nil)
    , m_reverbUnit(nil)
    , m_masterVolume(100)
    , m_soundVolume(100)
    , m_musicVolume(100)
    , m_isDeaf(false)
    , m_dopplerFactor(1.0f)
    , m_distanceFactor(1.0f)
    , m_rolloffFactor(1.0f)
    , m_listenerPos(0, 0, 0)
    , m_listenerForward(0, 0, 1)
    , m_listenerUp(0, 0, 1)
    , m_listenerVel(0, 0, 0)
    , m_pSystem(pSystem)
    , m_isInitialized(false)
{
    if (pSystem)
    {
        InitializeAudioEngine();
    }
}

CMacOSSoundSystem::~CMacOSSoundSystem()
{
    ShutdownAudioEngine();
}

bool CMacOSSoundSystem::InitializeAudioEngine()
{
    // Create audio engine
    m_audioEngine = [[AVAudioEngine alloc] init];
    if (!m_audioEngine)
        return false;
    
    // Get the mixer node
    m_mixerNode = [m_audioEngine mainMixerNode];
    
    // Create reverb unit for environmental effects
    m_reverbUnit = [[AVAudioUnitReverb alloc] init];
    if (m_reverbUnit)
    {
        [m_audioEngine attachNode:m_reverbUnit];
        [[m_audioEngine mainMixerNode] connect:m_reverbUnit to:[m_audioEngine outputNode] format:nil];
    }
    
    // Start the engine
    NSError* error = nil;
    BOOL success = [m_audioEngine startAndReturnError:&error];
    
    if (!success || error)
    {
        if (error)
        {
            NSLog(@"Error starting audio engine: %@", [error localizedDescription]);
        }
        return false;
    }
    
    m_isInitialized = true;
    return true;
}

void CMacOSSoundSystem::ShutdownAudioEngine()
{
    if (m_audioEngine)
    {
        [m_audioEngine stop];
        [m_audioEngine release];
        m_audioEngine = nil;
    }
    
    if (m_reverbUnit)
    {
        [m_reverbUnit release];
        m_reverbUnit = nil;
    }
    
    // Clean up sound buffers
    for (auto buffer : m_soundBuffers)
    {
        if (buffer)
            delete buffer;
    }
    m_soundBuffers.clear();
    m_loadedSounds.clear();
    
    m_isInitialized = false;
}

void CMacOSSoundSystem::Update()
{
    if (!m_isInitialized)
        return;
    
    // Update 3D audio
    Update3DAudio();
}

void CMacOSSoundSystem::SetListener(const CCamera& camera, const Vec3& vel)
{
    // Store listener velocity
    m_listenerVel = vel;
    
    // Extract position and orientation from camera
    // TODO: Implement proper camera access when CCamera is fully defined
    m_listenerPos = Vec3(0, 0, 0); // camera.GetPos();
    m_listenerForward = Vec3(0, 0, 1); // camera.GetAngles();
    m_listenerUp = Vec3(0, 0, 1); // Default up vector
    
    // Update 3D audio for all sounds
    Update3DAudio();
}

ISound* CMacOSSoundSystem::LoadSound(const char* sFileName, int nFlags)
{
    if (!sFileName || !m_isInitialized)
        return nullptr;
    
    // Check if already loaded
    auto it = m_loadedSounds.find(sFileName);
    if (it != m_loadedSounds.end())
    {
        return new CMacOSSound(it->second);
    }
    
    // Create new sound buffer
    CMacOSSoundBuffer* buffer = new CMacOSSoundBuffer();
    
    if (!buffer->LoadWave(sFileName, nFlags))
    {
        delete buffer;
        return nullptr;
    }
    
    // Create player node for this buffer
    AVAudioPlayerNode* playerNode = [[AVAudioPlayerNode alloc] init];
    [m_audioEngine attachNode:playerNode];
    [m_audioEngine connect:playerNode to:m_mixerNode format:nil];
    
    buffer->SetPlayerNode(playerNode);
    
    // Store in collections
    m_soundBuffers.push_back(buffer);
    m_loadedSounds[sFileName] = buffer;
    
    return new CMacOSSound(buffer);
}

void CMacOSSoundSystem::Silence()
{
    // Stop all playing sounds
    for (auto buffer : m_soundBuffers)
    {
        if (buffer)
        {
            buffer->Stop();
        }
    }
}

void CMacOSSoundSystem::Pause(bool bPause, bool bResetVolume)
{
    // Pause/resume all sounds
    for (auto buffer : m_soundBuffers)
    {
        if (buffer)
        {
            buffer->Pause(bPause);
        }
    }
}

void CMacOSSoundSystem::Mute(bool bMute)
{
    m_isDeaf = bMute;
    // TODO: Implement muting
}

void CMacOSSoundSystem::SetMasterVolume(unsigned char nVol)
{
    m_masterVolume = nVol;
    // TODO: Apply master volume to all sounds
}

void CMacOSSoundSystem::SetMasterVolumeScale(float fScale, bool bForceRecalc)
{
    // TODO: Implement master volume scaling
}

bool CMacOSSoundSystem::SetGroupScale(int nGroup, float fScale)
{
    // TODO: Implement group volume scaling
    return true;
}

void CMacOSSoundSystem::RecomputeSoundOcclusion(bool bRecomputeListener, bool bForceRecompute, bool bReset)
{
    // TODO: Implement sound occlusion
}

bool CMacOSSoundSystem::IsEAX(int version)
{
    return false; // EAX not available on macOS
}

bool CMacOSSoundSystem::SetEaxListenerEnvironment(int nPreset, CS_REVERB_PROPERTIES* pProps, int nFlags)
{
    return false; // EAX not available on macOS
}

bool CMacOSSoundSystem::GetCurrentEaxEnvironment(int& nPreset, CS_REVERB_PROPERTIES& Props)
{
    return false; // EAX not available on macOS
}

void CMacOSSoundSystem::GetSoundMemoryUsageInfo(size_t& nCurrentMemory, size_t& nMaxMemory)
{
    nCurrentMemory = 0;
    nMaxMemory = 0;
    // TODO: Calculate actual memory usage
}

int CMacOSSoundSystem::GetUsedVoices()
{
    int count = 0;
    for (auto buffer : m_soundBuffers)
    {
        if (buffer && buffer->IsPlaying())
        {
            count++;
        }
    }
    return count;
}

float CMacOSSoundSystem::GetCPUUsage()
{
    return 0.0f; // TODO: Calculate actual CPU usage
}

float CMacOSSoundSystem::GetMusicVolume()
{
    return m_musicVolume / 100.0f;
}

void CMacOSSoundSystem::CalcDirectionalAttenuation(Vec3& Pos, Vec3& Dir, float fConeInRadians)
{
    // TODO: Implement directional attenuation
}

float CMacOSSoundSystem::GetDirectionalAttenuationMaxScale()
{
    return 1.0f;
}

bool CMacOSSoundSystem::UsingDirectionalAttenuation()
{
    return false;
}

void CMacOSSoundSystem::GetMemoryUsage(ICrySizer* pSizer)
{
    // TODO: Calculate memory usage
}

IVisArea* CMacOSSoundSystem::GetListenerArea()
{
    return nullptr; // TODO: Implement vis area support
}

Vec3 CMacOSSoundSystem::GetListenerPos()
{
    return m_listenerPos;
}

void CMacOSSoundSystem::Update3DAudio()
{
    // Update 3D audio for all loaded sounds
    for (auto& soundBuffer : m_soundBuffers)
    {
        if (soundBuffer && soundBuffer->IsPlaying())
        {
            // Calculate relative position to listener
            Vec3 relativePos = soundBuffer->GetPosition() - m_listenerPos;
            float distance = relativePos.GetLength();
            
            // Apply distance attenuation
            float attenuation = 1.0f;
            if (distance > soundBuffer->GetMinDistance())
            {
                if (distance >= soundBuffer->GetMaxDistance())
                {
                    attenuation = 0.0f;
                }
                else
                {
                    float range = soundBuffer->GetMaxDistance() - soundBuffer->GetMinDistance();
                    float factor = (distance - soundBuffer->GetMinDistance()) / range;
                    attenuation = 1.0f - factor;
                }
            }
            
            // Update volume based on attenuation
            float baseVolume = soundBuffer->GetVolume() / 100.0f;
            soundBuffer->SetVolume((int)(baseVolume * attenuation * 100.0f));
        }
    }
}


// Utility functions
AudioStreamBasicDescription CreateStandardFormat(int sampleRate, int channels, int bitsPerSample)
{
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = sampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = (bitsPerSample / 8) * channels;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = (bitsPerSample / 8) * channels;
    format.mChannelsPerFrame = channels;
    format.mBitsPerChannel = bitsPerSample;
    return format;
}

AVAudioPCMBuffer* ConvertToStandardFormat(AVAudioPCMBuffer* sourceBuffer, 
                                         const AudioStreamBasicDescription& targetFormat)
{
    if (!sourceBuffer)
        return nil;
    
    // For now, just return the source buffer
    // TODO: Implement proper format conversion
    return sourceBuffer;
}