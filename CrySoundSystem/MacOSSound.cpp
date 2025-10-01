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
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "MacOSSound.h"
#include "ISystem.h"
#include <Foundation/Foundation.h>
#include <AVFoundation/AVFoundation.h>

// CMacOSSoundBuffer implementation
CMacOSSoundBuffer::CMacOSSoundBuffer()
    : m_props("MacOSSoundBuffer", 0)
    , CSoundBuffer(nullptr, m_props)
    , m_playerNode(nil)
    , m_audioBuffer(nil)
    , m_volume(1.0f)
    , m_pan(0.0f)
    , m_frequency(44100.0f)
    , m_is3D(false)
    , m_isPlaying(false)
    , m_isLooping(false)
    , m_position(0, 0, 0)
    , m_velocity(0, 0, 0)
    , m_minDistance(1.0f)
    , m_maxDistance(100.0f)
    , m_flags(0)
    , m_length(0)
    , m_currentPos(0)
{
    memset(&m_format, 0, sizeof(m_format));
}

CMacOSSoundBuffer::~CMacOSSoundBuffer()
{
    Release();
}

void CMacOSSoundBuffer::Release()
{
    Stop();
    
    if (m_audioBuffer)
    {
        [m_audioBuffer release];
        m_audioBuffer = nil;
    }
    
    if (m_playerNode)
    {
        [m_playerNode release];
        m_playerNode = nil;
    }
}

bool CMacOSSoundBuffer::LoadWave(const char* sFileName, int nFlags)
{
    if (!sFileName)
        return false;
    
    m_fileName = sFileName;
    m_flags = nFlags;
    
    return LoadAudioFile(sFileName);
}

bool CMacOSSoundBuffer::LoadOGG(const char* sFileName, int nFlags)
{
    // For now, treat OGG the same as other audio files
    // AVAudioEngine can handle various formats including OGG
    return LoadWave(sFileName, nFlags);
}

bool CMacOSSoundBuffer::LoadAudioFile(const char* fileName)
{
    NSString* filePath = [NSString stringWithUTF8String:fileName];
    NSURL* fileURL = [NSURL fileURLWithPath:filePath];
    
    NSError* error = nil;
    AVAudioFile* audioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    
    if (!audioFile || error)
    {
        if (error)
        {
            NSLog(@"Error loading audio file: %@", [error localizedDescription]);
        }
        return false;
    }
    
    // Get audio format
    m_format = *[audioFile processingFormat].streamDescription;
    m_length = (int)[audioFile length];
    
    // Create PCM buffer
    AVAudioFrameCount frameCount = (AVAudioFrameCount)[audioFile length];
    m_audioBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:[audioFile processingFormat]
                                                     frameCapacity:frameCount];
    
    if (!m_audioBuffer)
    {
        [audioFile release];
        return false;
    }
    
    // Read audio data
    BOOL success = [audioFile readIntoBuffer:m_audioBuffer error:&error];
    [audioFile release];
    
    if (!success)
    {
        [m_audioBuffer release];
        m_audioBuffer = nil;
        return false;
    }
    
    return true;
}

void CMacOSSoundBuffer::Play(bool bLoop, bool bLocked)
{
    if (!m_audioBuffer || !m_playerNode)
        return;
    
    m_isLooping = bLoop;
    m_isPlaying = true;
    
    // Schedule the buffer for playback
    if (bLoop)
    {
        [m_playerNode scheduleBuffer:m_audioBuffer atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
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

void CMacOSSoundBuffer::SetPan(int nPan)
{
    m_pan = nPan / 100.0f; // Convert from -100 to 100 to -1.0 to 1.0
    
    if (m_playerNode)
    {
        [m_playerNode setPan:m_pan];
    }
}

void CMacOSSoundBuffer::SetPosition(const Vec3& pos)
{
    m_position = pos;
    UpdateSpatialAudio();
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
void CMacOSSound::AddEventListener(ISoundEventListener* pListener) { /* TODO */ }
void CMacOSSound::RemoveEventListener(ISoundEventListener* pListener) { /* TODO */ }
bool CMacOSSound::IsPlaying() { return m_pBuffer ? m_pBuffer->IsPlaying() : false; }
bool CMacOSSound::IsPlayingVirtual() { return false; }
bool CMacOSSound::IsLoading() { return false; }
bool CMacOSSound::IsLoaded() { return m_pBuffer != nullptr; }
void CMacOSSound::Play(float fVolumeScale, bool bForceActiveState, bool bSetRatio) 
{ 
    if (m_pBuffer) 
    {
        m_pBuffer->Play(m_bLoop, false);
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
const char* CMacOSSound::GetName() { return m_sName.c_str(); }
const int CMacOSSound::GetId() { return m_nId; }
void CMacOSSound::SetLoopMode(bool bLoop) { m_bLoop = bLoop; }
bool CMacOSSound::Preload() { return true; }
unsigned int CMacOSSound::GetCurrentSamplePos(bool bMilliSeconds) { return 0; }
void CMacOSSound::SetCurrentSamplePos(unsigned int nPos, bool bMilliSeconds) { /* TODO */ }
void CMacOSSound::SetPitching(float fPitching) { /* TODO */ }
void CMacOSSound::SetRatio(float fRatio) { /* TODO */ }
int CMacOSSound::GetFrequency() { return 44100; }
void CMacOSSound::SetPitch(int nPitch) { m_fPitch = nPitch / 1000.0f; }
void CMacOSSound::SetPan(int nPan) { m_fPan = nPan / 100.0f; }
void CMacOSSound::SetMinMaxDistance(float fMinDist, float fMaxDist) 
{ 
    m_fMinDistance = fMinDist; 
    m_fMaxDistance = fMaxDist; 
}
void CMacOSSound::SetConeAngles(float fInnerAngle, float fOuterAngle) 
{ 
    m_fInnerAngle = fInnerAngle; 
    m_fOuterAngle = fOuterAngle; 
}
void CMacOSSound::AddToScaleGroup(int nGroup) { /* TODO */ }
void CMacOSSound::RemoveFromScaleGroup(int nGroup) { /* TODO */ }
void CMacOSSound::SetScaleGroup(unsigned int nGroupBits) { /* TODO */ }
void CMacOSSound::SetVolume(int nVolume) { m_nVolume = nVolume; }
int CMacOSSound::GetVolume() { return m_nVolume; }
void CMacOSSound::SetPosition(const Vec3& pos) { m_position = pos; }
const bool CMacOSSound::GetPosition(Vec3& vPos) { vPos = m_position; return true; }
void CMacOSSound::SetVelocity(const Vec3& vel) { m_velocity = vel; }
Vec3 CMacOSSound::GetVelocity() { return m_velocity; }
void CMacOSSound::SetDirection(const Vec3& dir) { m_direction = dir; }
Vec3 CMacOSSound::GetDirection() { return m_direction; }
void CMacOSSound::SetLoopPoints(const int iLoopStart, const int iLoopEnd) { /* TODO */ }
bool CMacOSSound::IsRelative() const { return m_bIsRelative; }
int CMacOSSound::AddRef() { return ++m_nRefCount; }
int CMacOSSound::Release() 
{ 
    int nRef = --m_nRefCount;
    if (nRef <= 0)
    {
        delete this;
    }
    return nRef;
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
    , m_listenerForward(0, 1, 0)
    , m_listenerUp(0, 0, 1)
    , m_listenerVel(0, 0, 0)
    , m_pSystem(nullptr)
    , m_isInitialized(false)
{
}

CMacOSSound::~CMacOSSound()
{
    Release();
}

bool CMacOSSound::Init(ISystem* pSystem)
{
    if (!pSystem)
        return false;
    
    m_pSystem = pSystem;
    
    if (!InitializeAudioEngine())
    {
        pSystem->GetILog()->Log("Error: Failed to initialize Core Audio engine");
        return false;
    }
    
    m_isInitialized = true;
    pSystem->GetILog()->Log("Core Audio sound system initialized successfully");
    return true;
}

bool CMacOSSound::InitializeAudioEngine()
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
    
    return true;
}

void CMacOSSound::Release()
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

void CMacOSSoundSystem::SetListener(const CCamera& camera, const Vec3& vel)
{
    // For now, just store the velocity - we can implement proper 3D audio later
    m_listenerVel = vel;
    
    // TODO: Extract position and orientation from camera and update AVAudio3DMixerNode
    // This would require proper 3D audio implementation
    Update3DAudio();
}

void CMacOSSound::Update3DAudio()
{
    // TODO: Update 3D audio positioning for all playing sounds
    // This would involve updating the 3D mixer nodes based on listener position
}

void CMacOSSound::Update()
{
    if (!m_isInitialized)
        return;
    
    // Update 3D audio
    Update3DAudio();
    
    // TODO: Update streaming sounds, cleanup finished sounds, etc.
}

// Stub implementations for remaining interface methods
void CMacOSSound::UnloadSound(ISound* pSound) { /* TODO */ }
ISound* CMacOSSound::CreateSound() { return nullptr; }
bool CMacOSSound::PlaySound(ISound* pSound, const Vec3* pos, int nFlags) { return false; }
void CMacOSSound::StopSound(ISound* pSound) { /* TODO */ }
void CMacOSSound::PauseSound(ISound* pSound, bool bPause) { /* TODO */ }
void CMacOSSound::SetSoundVolume(int nVolume) { m_soundVolume = nVolume; }
int CMacOSSound::GetSoundVolume() { return m_soundVolume; }
void CMacOSSound::SetMusicVolume(int nVolume) { m_musicVolume = nVolume; }
float CMacOSSound::GetMusicVolume() { return m_musicVolume; }
void CMacOSSound::Silence() { /* TODO */ }
void CMacOSSound::SetMasterVolume(int nVolume) { m_masterVolume = nVolume; }
int CMacOSSound::GetMasterVolume() { return m_masterVolume; }
void CMacOSSound::SetDeafness(bool bDeaf) { m_isDeaf = bDeaf; }
bool CMacOSSound::IsDeaf() { return m_isDeaf; }
void CMacOSSound::SetDopplerFactor(float fFactor) { m_dopplerFactor = fFactor; }
float CMacOSSound::GetDopplerFactor() { return m_dopplerFactor; }
void CMacOSSound::SetDistanceFactor(float fFactor) { m_distanceFactor = fFactor; }
float CMacOSSound::GetDistanceFactor() { return m_distanceFactor; }
void CMacOSSound::SetRolloffFactor(float fFactor) { m_rolloffFactor = fFactor; }
float CMacOSSound::GetRolloffFactor() { return m_rolloffFactor; }
bool CMacOSSound::SetEAX(int nPreset) { return false; }
int CMacOSSound::GetEAX() { return 0; }
void CMacOSSound::LoadSoundBuffers() { /* TODO */ }
void CMacOSSound::FreeSoundBuffers() { /* TODO */ }
void CMacOSSound::CalcSoundMood(SMusicMood* pMood, float fRadius) { /* TODO */ }

// Utility functions
AudioStreamBasicDescription CreateStandardFormat(int sampleRate, int channels, int bitsPerSample)
{
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = sampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    format.mChannelsPerFrame = channels;
    format.mBitsPerChannel = bitsPerSample;
    format.mBytesPerFrame = (bitsPerSample / 8) * channels;
    format.mBytesPerPacket = format.mBytesPerFrame;
    format.mFramesPerPacket = 1;
    
    return format;
}

#endif // __APPLE__ && __MACH__
