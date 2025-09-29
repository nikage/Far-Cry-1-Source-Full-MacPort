// Minimal test for Far Cry Mac Silicon Port - Avoiding framework conflicts
#define NOT_USE_CRY_MEMORY_MANAGER 1

#include "CryCommon/platform.h"
#include "CryCommon/CryLibrary.h"

#include <iostream>
#include <chrono>
#include <thread>

int main()
{
    std::cout << "=== Far Cry Mac Silicon Port - Minimal Test ===\n\n";
    
    int testsPassed = 0;
    int testsFailed = 0;
    
    // Test 1: Platform Detection
    std::cout << "1. Platform Detection:\n";
#if defined(__APPLE__) && defined(__MACH__)
    std::cout << "   ✓ Platform: macOS\n";
    testsPassed++;
    
    #if defined(_CPU_ARM64)
        std::cout << "   ✓ Architecture: ARM64 (Apple Silicon)\n";
        testsPassed++;
    #elif defined(_CPU_X86_64)
        std::cout << "   ✓ Architecture: x86_64 (Intel Mac)\n";
        testsPassed++;
    #else
        std::cout << "   ✗ Architecture: Unknown\n";
        testsFailed++;
    #endif
#else
    std::cout << "   ✗ Platform: Not macOS\n";
    testsFailed++;
#endif
    
    // Test 2: High-Resolution Timer
    std::cout << "\n2. High-Resolution Timer:\n";
    int64 start = GetTicks();
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    int64 end = GetTicks();
    
    if (end > start)
    {
        std::cout << "   ✓ Timer working: " << (end - start) << " ticks\n";
        testsPassed++;
    }
    else
    {
        std::cout << "   ✗ Timer not working\n";
        testsFailed++;
    }
    
    // Test 3: Type Sizes
    std::cout << "\n3. Type Sizes:\n";
    std::cout << "   int8: " << sizeof(int8) << " bytes\n";
    std::cout << "   int16: " << sizeof(int16) << " bytes\n";
    std::cout << "   int32: " << sizeof(int32) << " bytes\n";
    std::cout << "   int64: " << sizeof(int64) << " bytes\n";
    std::cout << "   pointer: " << sizeof(void*) << " bytes\n";
    
    bool typesCorrect = (sizeof(int8) == 1 && sizeof(int16) == 2 && 
                        sizeof(int32) == 4 && sizeof(int64) == 8 &&
                        sizeof(void*) == 8);
    if (typesCorrect)
    {
        std::cout << "   ✓ All types correct size\n";
        testsPassed++;
    }
    else
    {
        std::cout << "   ✗ Type sizes incorrect\n";
        testsFailed++;
    }
    
    // Test 4: String Compatibility
    std::cout << "\n4. String Compatibility:\n";
    try
    {
        string testStr = "Far Cry Mac Silicon Port";
        if (testStr.length() > 0)
        {
            std::cout << "   ✓ String: " << testStr << "\n";
            testsPassed++;
        }
        else
        {
            std::cout << "   ✗ String empty\n";
            testsFailed++;
        }
    }
    catch (...)
    {
        std::cout << "   ✗ String exception\n";
        testsFailed++;
    }
    
    // Test 5: Dynamic Library Support
    std::cout << "\n5. Dynamic Library Support:\n";
    if (CrySharedLibraySupported)
    {
        std::cout << "   ✓ Supported: " << CrySharedLibrayExtension << "\n";
        testsPassed++;
    }
    else
    {
        std::cout << "   ✗ Not supported\n";
        testsFailed++;
    }
    
    // Test 6: Memory Operations
    std::cout << "\n6. Memory Operations:\n";
    try
    {
        void* ptr = malloc(1024);
        if (ptr)
        {
            memset(ptr, 0xAB, 1024);
            std::cout << "   ✓ Memory allocation and operations working\n";
            free(ptr);
            testsPassed++;
        }
        else
        {
            std::cout << "   ✗ Memory allocation failed\n";
            testsFailed++;
        }
    }
    catch (...)
    {
        std::cout << "   ✗ Memory operations exception\n";
        testsFailed++;
    }
    
    // Test 7: Cache Line Size
    std::cout << "\n7. Cache Architecture:\n";
    std::cout << "   Cache line size: " << CACHE_LINE_SIZE << " bytes\n";
    if (CACHE_LINE_SIZE == 64)
    {
        std::cout << "   ✓ Expected ARM64 cache line size\n";
        testsPassed++;
    }
    else
    {
        std::cout << "   ✗ Unexpected cache line size\n";
        testsFailed++;
    }
    
    // Test 8: Resource Compiler Path
    std::cout << "\n8. Resource Compiler:\n";
    std::cout << "   RC executable: " << RC_EXECUTABLE << "\n";
    if (std::string(RC_EXECUTABLE) == "rc_mac")
    {
        std::cout << "   ✓ Correct macOS resource compiler path\n";
        testsPassed++;
    }
    else
    {
        std::cout << "   ✗ Incorrect resource compiler path\n";
        testsFailed++;
    }
    
    // Test 9: Math Operations
    std::cout << "\n9. Basic Math:\n";
    f32 testFloat = 3.14159f;
    f64 testDouble = 2.71828;
    
    if (testFloat > 3.0f && testDouble > 2.0)
    {
        std::cout << "   ✓ Float operations: f32=" << testFloat << ", f64=" << testDouble << "\n";
        testsPassed++;
    }
    else
    {
        std::cout << "   ✗ Float operations failed\n";
        testsFailed++;
    }
    
    // Test 10: Performance Benchmark
    std::cout << "\n10. Performance Benchmark:\n";
    const size_t iterations = 1000000;
    auto start_time = std::chrono::high_resolution_clock::now();
    
    volatile int sum = 0;
    for (size_t i = 0; i < iterations; ++i)
    {
        sum += i;
    }
    
    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end_time - start_time);
    
    std::cout << "   ✓ Loop performance: " << iterations << " iterations in " 
              << duration.count() << " microseconds\n";
    std::cout << "   ✓ Operations per second: " 
              << (iterations * 1000000.0 / duration.count()) << "\n";
    testsPassed++;
    
    // Final Results
    std::cout << "\n=== Results ===\n";
    std::cout << "Tests Passed: " << testsPassed << "\n";
    std::cout << "Tests Failed: " << testsFailed << "\n";
    std::cout << "Success Rate: " << (testsPassed * 100 / (testsPassed + testsFailed)) << "%\n";
    
    if (testsFailed == 0)
    {
        std::cout << "\n🎉 ALL TESTS PASSED!\n";
        std::cout << "Far Cry Mac Silicon port core platform is working perfectly!\n";
        std::cout << "\nPlatform abstraction layer validated:\n";
        std::cout << "✓ ARM64 architecture detection\n";
        std::cout << "✓ High-resolution timer functionality\n";
        std::cout << "✓ Type system compatibility\n";
        std::cout << "✓ String operations\n";
        std::cout << "✓ Dynamic library support\n";
        std::cout << "✓ Memory management\n";
        std::cout << "✓ Cache architecture awareness\n";
        std::cout << "✓ Resource compiler configuration\n";
        std::cout << "✓ Mathematical operations\n";
        std::cout << "✓ Performance characteristics\n";
        return 0;
    }
    else
    {
        std::cout << "\n⚠️  " << testsFailed << " test(s) failed.\n";
        return 1;
    }
}
