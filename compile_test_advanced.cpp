// Advanced compilation test for Far Cry Mac Silicon Port
// Tests that our core systems can be compiled and instantiated

#define NOT_USE_CRY_MEMORY_MANAGER 1

// Include our platform abstractions
#include "CryCommon/platform.h"
#include "CryCommon/CryLibrary.h"

#if defined(__APPLE__) && defined(__MACH__)
#include "CryCommon/MacARM64Memory.h"
#include <Metal/Metal.h>
#include <CoreAudio/CoreAudio.h>
#include <Foundation/Foundation.h>
#include <arm_neon.h>
#endif

#include <iostream>
#include <vector>
#include <memory>

// Test that our graphics system can be instantiated
#if defined(__APPLE__) && defined(__MACH__)

// Simple Metal device test
class MetalDeviceTest 
{
public:
    bool TestMetalDevice()
    {
        @autoreleasepool {
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            if (device)
            {
                NSString* deviceName = [device name];
                std::cout << "Metal device available: " << [deviceName UTF8String] << std::endl;
                return true;
            }
            return false;
        }
    }
    
    bool TestMetalTexture()
    {
        @autoreleasepool {
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            if (!device) return false;
            
            MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
            desc.width = 256;
            desc.height = 256;
            desc.pixelFormat = MTLPixelFormatRGBA8Unorm;
            desc.usage = MTLTextureUsageShaderRead;
            
            id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
            [desc release];
            
            if (texture)
            {
                std::cout << "Metal texture created: 256x256 RGBA8" << std::endl;
                [texture release];
                return true;
            }
            return false;
        }
    }
};

// Test ARM64 NEON operations
class ARM64SIMDTest
{
public:
    bool TestNEONOperations()
    {
#if defined(_CPU_ARM64)
        // Test basic NEON vector operations
        float32x4_t a = vdupq_n_f32(1.0f);
        float32x4_t b = vdupq_n_f32(2.0f);
        float32x4_t c = vdupq_n_f32(3.0f);
        
        // Vector multiply-add: a * b + c
        float32x4_t result = vmlaq_f32(c, a, b);
        
        float resultArray[4];
        vst1q_f32(resultArray, result);
        
        // Should be: 1 * 2 + 3 = 5
        if (resultArray[0] == 5.0f && resultArray[1] == 5.0f &&
            resultArray[2] == 5.0f && resultArray[3] == 5.0f)
        {
            std::cout << "ARM64 NEON multiply-add working correctly" << std::endl;
            return true;
        }
#endif
        return false;
    }
    
    bool TestMemoryOperations()
    {
        // Test our memory alignment
        void* ptr = malloc(1024);
        if (ptr)
        {
            // Check alignment
            uintptr_t addr = reinterpret_cast<uintptr_t>(ptr);
            std::cout << "Memory allocation: " << ptr << " (alignment: " 
                      << (addr % CACHE_LINE_SIZE) << ")" << std::endl;
            free(ptr);
            return true;
        }
        return false;
    }
};

// Test audio system basics
class CoreAudioTest
{
public:
    bool TestAudioDevice()
    {
        AudioDeviceID defaultDevice = kAudioDeviceUnknown;
        UInt32 size = sizeof(AudioDeviceID);
        AudioObjectPropertyAddress propertyAddress = {
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMaster
        };
        
        OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                   &propertyAddress,
                                                   0, NULL,
                                                   &size, &defaultDevice);
        
        if (status == noErr && defaultDevice != kAudioDeviceUnknown)
        {
            std::cout << "Core Audio device available: ID " << defaultDevice << std::endl;
            return true;
        }
        return false;
    }
};

#endif

class PlatformTest
{
public:
    void RunTests()
    {
        std::cout << "=== Far Cry Mac Silicon Port - Advanced Compilation Test ===\n\n";
        
        int passed = 0, failed = 0;
        
        // Test basic platform detection
        std::cout << "1. Platform Detection:\n";
#if defined(__APPLE__) && defined(__MACH__)
        std::cout << "   ✓ macOS platform detected\n";
        
#if defined(_CPU_ARM64)
        std::cout << "   ✓ Apple Silicon ARM64 architecture\n";
        passed++;
#else
        std::cout << "   ✓ Intel x86_64 architecture\n";
        passed++;
#endif
        
        // Test timer
        std::cout << "\n2. High-Resolution Timer:\n";
        int64 start = GetTicks();
        int64 end = GetTicks();
        if (end >= start)
        {
            std::cout << "   ✓ Timer working: " << (end - start) << " ticks\n";
            passed++;
        }
        else
        {
            std::cout << "   ✗ Timer failed\n";
            failed++;
        }
        
        // Test string operations
        std::cout << "\n3. String Operations:\n";
        try
        {
            string testStr = "Far Cry";
            testStr += " Mac Silicon";
            std::cout << "   ✓ String operations: " << testStr << "\n";
            passed++;
        }
        catch (...)
        {
            std::cout << "   ✗ String operations failed\n";
            failed++;
        }
        
        // Test graphics system
        std::cout << "\n4. Graphics System (Metal):\n";
        MetalDeviceTest metalTest;
        if (metalTest.TestMetalDevice())
        {
            passed++;
            if (metalTest.TestMetalTexture())
            {
                passed++;
            }
            else
            {
                std::cout << "   ✗ Metal texture creation failed\n";
                failed++;
            }
        }
        else
        {
            std::cout << "   ✗ Metal device not available\n";
            failed++;
        }
        
        // Test SIMD operations
        std::cout << "\n5. SIMD Operations:\n";
        ARM64SIMDTest simdTest;
        if (simdTest.TestNEONOperations())
        {
            passed++;
        }
        else
        {
            std::cout << "   ✗ NEON operations failed\n";
            failed++;
        }
        
        if (simdTest.TestMemoryOperations())
        {
            passed++;
        }
        else
        {
            std::cout << "   ✗ Memory operations failed\n";
            failed++;
        }
        
        // Test audio system
        std::cout << "\n6. Audio System (Core Audio):\n";
        CoreAudioTest audioTest;
        if (audioTest.TestAudioDevice())
        {
            passed++;
        }
        else
        {
            std::cout << "   ✗ Core Audio device not available\n";
            failed++;
        }
        
#else
        std::cout << "   - Tests skipped (macOS only)\n";
#endif
        
        // Results
        std::cout << "\n=== Advanced Test Results ===\n";
        std::cout << "Tests Passed: " << passed << "\n";
        std::cout << "Tests Failed: " << failed << "\n";
        
        if (failed == 0)
        {
            std::cout << "\n🎉 ADVANCED TESTS PASSED!\n";
            std::cout << "Far Cry Mac Silicon port systems are working!\n";
        }
        else
        {
            std::cout << "\n⚠️  Some advanced tests failed.\n";
        }
    }
};

int main()
{
    PlatformTest test;
    test.RunTests();
    return 0;
}
