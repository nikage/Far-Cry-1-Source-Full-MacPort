////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacARM64Memory.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for ARM64
//  Description: ARM64-specific memory management optimizations
//               Optimized for Apple Silicon unified memory architecture
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef MAC_ARM64_MEMORY_H
#define MAC_ARM64_MEMORY_H

#if defined(__APPLE__) && defined(__MACH__) && (defined(__aarch64__) || defined(__arm64__))

#include "MacOSspecific.h"
#include <arm_neon.h>
#include <mach/mach.h>
#include <sys/mman.h>

// ARM64 cache characteristics for Apple Silicon
#define ARM64_L1_CACHE_LINE_SIZE    64
#define ARM64_L2_CACHE_LINE_SIZE    128
#define ARM64_PAGE_SIZE             16384   // 16KB pages on Apple Silicon
#define ARM64_HUGE_PAGE_SIZE        (2 * 1024 * 1024)  // 2MB huge pages

// Memory alignment macros for optimal ARM64 performance
#define ARM64_CACHE_ALIGNED         __attribute__((aligned(ARM64_L1_CACHE_LINE_SIZE)))
#define ARM64_PAGE_ALIGNED          __attribute__((aligned(ARM64_PAGE_SIZE)))
#define ARM64_SIMD_ALIGNED          __attribute__((aligned(16)))

// Memory barriers and synchronization for ARM64
#define ARM64_DMB_ISH()             __dmb(0xB)  // Data Memory Barrier - Inner Shareable
#define ARM64_DMB_ISHST()           __dmb(0xA)  // Data Memory Barrier - Store, Inner Shareable
#define ARM64_DMB_ISHLD()           __dmb(0x9)  // Data Memory Barrier - Load, Inner Shareable
#define ARM64_DSB_ISH()             __dsb(0xB)  // Data Sync Barrier - Inner Shareable
#define ARM64_ISB()                 __isb(0xF)  // Instruction Sync Barrier

// Prefetch instructions for ARM64
#define ARM64_PREFETCH_READ(addr)   __builtin_prefetch((addr), 0, 3)
#define ARM64_PREFETCH_WRITE(addr)  __builtin_prefetch((addr), 1, 3)

#ifdef __cplusplus
extern "C" {
#endif

// ARM64-optimized memory allocation
typedef struct
{
    void* base_address;
    size_t size;
    size_t alignment;
    uint32_t flags;
    vm_prot_t protection;
} arm64_memory_region_t;

// Memory allocation flags for ARM64
#define ARM64_MEM_CACHEABLE         0x01
#define ARM64_MEM_UNCACHEABLE       0x02
#define ARM64_MEM_WRITE_THROUGH     0x04
#define ARM64_MEM_WRITE_BACK        0x08
#define ARM64_MEM_COHERENT          0x10
#define ARM64_MEM_GPU_ACCESSIBLE    0x20

// ARM64-specific memory management functions
void* arm64_aligned_alloc(size_t size, size_t alignment);
void arm64_aligned_free(void* ptr);
void* arm64_cache_aligned_alloc(size_t size);
void* arm64_page_aligned_alloc(size_t size);

// Large page allocation for better performance
void* arm64_huge_page_alloc(size_t size);
void arm64_huge_page_free(void* ptr, size_t size);

// Memory mapping with specific attributes
void* arm64_mmap_with_attributes(size_t size, uint32_t flags);
int arm64_munmap_with_attributes(void* addr, size_t size);

// Cache management functions
void arm64_cache_flush_range(void* start, size_t size);
void arm64_cache_invalidate_range(void* start, size_t size);
void arm64_cache_clean_range(void* start, size_t size);

// Memory copy optimizations using ARM64 NEON
void arm64_memcpy_neon(void* dest, const void* src, size_t size);
void arm64_memset_neon(void* dest, int value, size_t size);
int arm64_memcmp_neon(const void* ptr1, const void* ptr2, size_t size);

// SIMD memory operations
void arm64_copy_128bit_aligned(void* dest, const void* src, size_t count);
void arm64_zero_128bit_aligned(void* dest, size_t count);

// Memory bandwidth optimization
void arm64_streaming_copy(void* dest, const void* src, size_t size);
void arm64_non_temporal_copy(void* dest, const void* src, size_t size);

// Apple Silicon specific optimizations
bool arm64_is_apple_silicon(void);
size_t arm64_get_unified_memory_size(void);
size_t arm64_get_cache_line_size(void);
size_t arm64_get_page_size(void);

// Memory pool for small allocations
typedef struct arm64_memory_pool arm64_memory_pool_t;

arm64_memory_pool_t* arm64_create_memory_pool(size_t pool_size, size_t block_size);
void arm64_destroy_memory_pool(arm64_memory_pool_t* pool);
void* arm64_pool_alloc(arm64_memory_pool_t* pool);
void arm64_pool_free(arm64_memory_pool_t* pool, void* ptr);

// Statistics and monitoring
typedef struct
{
    uint64_t total_allocated;
    uint64_t total_freed;
    uint64_t peak_usage;
    uint64_t current_usage;
    uint32_t allocation_count;
    uint32_t free_count;
    uint32_t cache_hits;
    uint32_t cache_misses;
} arm64_memory_stats_t;

void arm64_get_memory_stats(arm64_memory_stats_t* stats);
void arm64_reset_memory_stats(void);

#ifdef __cplusplus
}

// C++ optimized memory operations
namespace ARM64Memory
{
    // Template-based SIMD operations
    template<typename T>
    void copy_simd_aligned(T* dest, const T* src, size_t count)
    {
        static_assert(sizeof(T) % 16 == 0, "Type must be 16-byte aligned for SIMD");
        arm64_copy_128bit_aligned(dest, src, count * sizeof(T) / 16);
    }
    
    template<typename T>
    void zero_simd_aligned(T* dest, size_t count)
    {
        static_assert(sizeof(T) % 16 == 0, "Type must be 16-byte aligned for SIMD");
        arm64_zero_128bit_aligned(dest, count * sizeof(T) / 16);
    }
    
    // Smart pointer with ARM64 optimizations
    template<typename T>
    class aligned_unique_ptr
    {
    public:
        aligned_unique_ptr() : ptr_(nullptr) {}
        
        explicit aligned_unique_ptr(size_t alignment = ARM64_L1_CACHE_LINE_SIZE)
        {
            ptr_ = static_cast<T*>(arm64_aligned_alloc(sizeof(T), alignment));
        }
        
        ~aligned_unique_ptr()
        {
            if (ptr_)
                arm64_aligned_free(ptr_);
        }
        
        T* get() const { return ptr_; }
        T& operator*() const { return *ptr_; }
        T* operator->() const { return ptr_; }
        
        aligned_unique_ptr(const aligned_unique_ptr&) = delete;
        aligned_unique_ptr& operator=(const aligned_unique_ptr&) = delete;
        
        aligned_unique_ptr(aligned_unique_ptr&& other) noexcept
            : ptr_(other.ptr_)
        {
            other.ptr_ = nullptr;
        }
        
        aligned_unique_ptr& operator=(aligned_unique_ptr&& other) noexcept
        {
            if (this != &other)
            {
                if (ptr_)
                    arm64_aligned_free(ptr_);
                ptr_ = other.ptr_;
                other.ptr_ = nullptr;
            }
            return *this;
        }
        
    private:
        T* ptr_;
    };
    
    // RAII wrapper for memory pools
    class MemoryPool
    {
    public:
        MemoryPool(size_t pool_size, size_t block_size)
            : pool_(arm64_create_memory_pool(pool_size, block_size))
        {
        }
        
        ~MemoryPool()
        {
            if (pool_)
                arm64_destroy_memory_pool(pool_);
        }
        
        void* allocate()
        {
            return pool_ ? arm64_pool_alloc(pool_) : nullptr;
        }
        
        void deallocate(void* ptr)
        {
            if (pool_ && ptr)
                arm64_pool_free(pool_, ptr);
        }
        
        MemoryPool(const MemoryPool&) = delete;
        MemoryPool& operator=(const MemoryPool&) = delete;
        
    private:
        arm64_memory_pool_t* pool_;
    };
}
#endif // __cplusplus

#endif // __APPLE__ && __MACH__ && ARM64

#endif // MAC_ARM64_MEMORY_H
