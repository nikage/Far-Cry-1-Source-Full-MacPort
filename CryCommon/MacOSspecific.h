////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSspecific.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM
//  Description: Specific to macOS declarations, inline functions etc.
//               Provides cross-platform compatibility layer
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////
#ifndef _CRY_COMMON_MACOS_SPECIFIC_HDR_
#define _CRY_COMMON_MACOS_SPECIFIC_HDR_

#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>
#include <unistd.h>
#include <pthread.h>
#include <stdlib.h>  // for malloc/free on macOS
#include <mach/mach_time.h>
#include <mach-o/dyld.h>  // for _NSGetExecutablePath
#include <string.h>       // for string functions
#include <stdio.h>        // for FILE type
#include <dlfcn.h>        // for dlopen/dlsym
#include <fcntl.h>        // for O_* file flags
#include <sys/stat.h>     // for stat function

#ifdef __cplusplus
extern "C" {
#endif

// Type definitions matching Windows types
typedef int8_t          int8;
typedef int16_t         int16;
typedef int32_t         int32;
typedef int64_t         int64;
typedef uint8_t         uint8;
typedef uint16_t        uint16;
typedef uint32_t        uint32;
typedef uint64_t        uint64;

typedef float           f32;
typedef double          f64;

// Old-style (compatible with existing code)
typedef int8_t          s8;
typedef int16_t         s16;
typedef int32_t         s32;
typedef int64_t         s64;
typedef uint8_t         u8;
typedef uint16_t        u16;
typedef uint32_t        u32;
typedef uint64_t        u64;

// Windows compatibility types (avoid conflicts with system headers)
typedef void*           THREAD_HANDLE;
typedef void*           EVENT_HANDLE;
// Define BOOL before any system headers are included
#define BOOL int
#ifndef DWORD
typedef uint32_t        DWORD;
#endif
typedef int32_t         LONG;
typedef uint32_t        HRESULT;  // COM HRESULT type
typedef void*           HMODULE;
typedef void*           HINSTANCE;
typedef void*           HWND;
typedef void*           HDC;
typedef void*           HGLRC;
typedef void*           LPVOID;
typedef char*           LPSTR;
typedef uint8_t         BYTE;
typedef uint16_t        WORD;
typedef uintptr_t       WPARAM;
typedef intptr_t        LPARAM;
typedef intptr_t        LRESULT;
typedef void*           HBRUSH;
typedef void*           HICON;
typedef void*           HCURSOR;
#define CALLBACK        // Empty macro for macOS

// Window class constants
#define CS_OWNDC        0x0020
#define CS_HREDRAW      0x0002
#define CS_VREDRAW      0x0001
#define BLACK_BRUSH     4
#define IDI_ICON        1

// MessageBox constants
#define MB_OK                   0x00000000L
#define MB_ICONERROR           0x00000010L
#define MB_DEFAULT_DESKTOP_ONLY 0x00020000L

// Window procedure function pointer type
typedef LRESULT (*WNDPROC)(HWND, uint32_t, WPARAM, LPARAM);

// Window class structure
typedef struct tagWNDCLASS {
    uint32_t    style;
    WNDPROC     lpfnWndProc;  // Window procedure
    int         cbClsExtra;
    int         cbWndExtra;
    HINSTANCE   hInstance;
    HICON       hIcon;
    HCURSOR     hCursor;
    HBRUSH      hbrBackground;
    const char* lpszMenuName;
    const char* lpszClassName;
} WNDCLASS;

// Windows message constants (stubs for macOS)
#define WM_MOVE             0x0003
#define WM_SIZE             0x0005  
#define WM_ACTIVATE         0x0006
#define WM_SETFOCUS         0x0007
#define WM_KILLFOCUS        0x0008
#define WM_DESTROY          0x0002
#define WM_DISPLAYCHANGE    0x007E
#define WM_ACTIVATEAPP      0x001C
#define WM_MOUSEACTIVATE    0x0021
#define WM_ENTERSIZEMOVE    0x0231
#define WM_ENTERMENULOOP    0x0211
#define WM_HOTKEY           0x0312
#define WM_SYSKEYDOWN       0x0104
#define WM_SYSKEYUP         0x0105
#define WM_KEYDOWN          0x0100
#define WM_KEYUP            0x0101
#define WM_CHAR             0x0102
#define WM_QUIT             0x0012
#define WM_CLOSE            0x0010
#define SIZE_MAXHIDE       4
#define SIZE_MINIMIZED     1
#define MA_ACTIVATEANDEAT   2
#define WA_INACTIVE        0
#define WA_ACTIVE          1
#define WA_CLICKACTIVE     2

// Windows utility macros
#define LOWORD(l) ((uint16_t)(((uintptr_t)(l)) & 0xffff))
#define HIWORD(l) ((uint16_t)((((uintptr_t)(l)) >> 16) & 0xffff))

// Windows SAL annotations (Source Code Annotation Language)
#define IN          // Input parameter annotation
#define OUT         // Output parameter annotation

// Windows heap debugging types (stubs for macOS)
typedef struct _HEAPLIST32 {
    uint32_t dwSize;
    uint32_t th32ProcessID;
    uint32_t th32HeapID;
    uint32_t dwFlags;
} HEAPLIST32;

// Windows time structures
typedef union _LARGE_INTEGER {
    struct {
        uint32_t LowPart;
        int32_t HighPart;
    };
    int64_t QuadPart;
} LARGE_INTEGER;

// Rectangle structure
typedef struct tagRECT {
    int32_t left;
    int32_t top;
    int32_t right;
    int32_t bottom;
} RECT;

// Boolean values
#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

// Memory debugging function for debug builds (renamed to avoid Carbon conflict)
#ifdef __cplusplus
inline int CryIsHeapValid()
{
#ifdef _DEBUG
    // On macOS, we can use malloc_zone_check_all for heap validation
    // For now, just return true - can be enhanced with actual validation
    return true;
#else
    return true;
#endif
}

// Note: IsHeapValid macro removed to avoid conflict with Carbon framework

// Windows compatibility macros
#define ILINE inline
#define _inline inline
#define APIENTRY
#define WINAPI
#define _ACCESS_POOL   // Empty macro for macOS
#define __forceinline inline
#define __declspec(x)  // Empty macro for macOS - ignore Windows DLL specifications

// Windows API compatibility
#define GetProcAddress(hModule, lpProcName) dlsym(hModule, lpProcName)
#define HINSTANCE void*

// Windows file/module API compatibility
inline void* GetModuleHandle(void* lpModuleName) { 
    // For main executable, return a dummy handle
    return (void*)1; 
}

inline uint32_t GetModuleFileName(void* hModule, char* lpFilename, uint32_t nSize) {
    // Get the executable path on macOS
    uint32_t size = nSize;
    if (_NSGetExecutablePath(lpFilename, &size) == 0) {
        return strlen(lpFilename);
    }
    return 0;
}

// Path manipulation functions (Windows compatibility)
inline void _splitpath(const char* path, char* drive, char* dir, char* fname, char* ext) {
    // macOS doesn't have drive letters, so drive is always empty
    if (drive) drive[0] = '\0';
    
    const char* last_slash = strrchr(path, '/');
    const char* last_dot = strrchr(path, '.');
    
    // Extract directory
    if (dir) {
        if (last_slash) {
            size_t dir_len = last_slash - path + 1;
            strncpy(dir, path, dir_len);
            dir[dir_len] = '\0';
        } else {
            strcpy(dir, "./");
        }
    }
    
    // Extract filename and extension
    const char* name_start = last_slash ? last_slash + 1 : path;
    
    if (fname) {
        if (last_dot && last_dot > name_start) {
            size_t name_len = last_dot - name_start;
            strncpy(fname, name_start, name_len);
            fname[name_len] = '\0';
        } else {
            strcpy(fname, name_start);
        }
    }
    
    if (ext && last_dot && last_dot > name_start) {
        strcpy(ext, last_dot);
    } else if (ext) {
        ext[0] = '\0';
    }
}

inline void _makepath(char* path, const char* drive, const char* dir, const char* fname, const char* ext) {
    // Ignore drive on macOS
    path[0] = '\0';
    
    if (dir && dir[0]) {
        strcat(path, dir);
    }
    
    if (fname && fname[0]) {
        strcat(path, fname);
    }
    
    if (ext && ext[0]) {
        strcat(path, ext);
    }
}

inline int SetCurrentDirectory(const char* lpPathName) {
    return chdir(lpPathName) == 0 ? 1 : 0;
}

inline uint32_t GetCurrentDirectory(uint32_t nBufferLength, char* lpBuffer) {
    if (getcwd(lpBuffer, nBufferLength) != NULL) {
        return strlen(lpBuffer);
    }
    return 0;
}

// Windows GUI API stubs (not functional on macOS)
inline void* FindWindow(const char* lpClassName, const char* lpWindowName) {
    return NULL;  // No equivalent on macOS console app
}

inline int SetForegroundWindow(void* hWnd) {
    return 0;  // Stub - no equivalent for console app
}

inline int GetClientRect(void* hWnd, RECT* lpRect) {
    // Stub implementation - return a default rectangle
    if (lpRect) {
        lpRect->left = 0;
        lpRect->top = 0;
        lpRect->right = 800;  // Default width
        lpRect->bottom = 600; // Default height
    }
    return 1;
}

inline LRESULT DefWindowProc(void* hWnd, uint32_t Msg, WPARAM wParam, LPARAM lParam) {
    // Default window procedure stub for macOS
    return 0;  // Return 0 for all messages
}

// Resource and GDI function stubs
inline void* MAKEINTRESOURCE(int id) {
    return (void*)(uintptr_t)id;
}

inline void* LoadIcon(void* hInstance, void* lpIconName) {
    return NULL;  // No icon loading on macOS console
}

inline void* GetStockObject(int i) {
    return (void*)1;  // Return dummy brush handle
}

inline uint16_t RegisterClass(const WNDCLASS* lpWndClass) {
    return 1;  // Always succeed on macOS stub
}

inline uint32_t GetLastError() {
    return 0;  // No error on macOS stub
}

// Windows process/thread functions (stubs for macOS)
inline void* GetCurrentProcess() {
    return (void*)1;  // Dummy process handle
}

inline void* GetCurrentThread() {
    return (void*)2;  // Dummy thread handle
}

inline uint32_t GetPriorityClass(void* hProcess) {
    return 0x00000020;  // NORMAL_PRIORITY_CLASS
}

inline int GetThreadPriority(void* hThread) {
    return 0;  // THREAD_PRIORITY_NORMAL
}

// Windows priority constants
#define REALTIME_PRIORITY_CLASS     0x00000100
#define THREAD_PRIORITY_TIME_CRITICAL 15

// Windows type definitions
typedef int64_t INT64;
typedef void VOID;

// Windows file time structure
typedef struct _FILETIME {
    uint32_t dwLowDateTime;
    uint32_t dwHighDateTime;
} FILETIME;

// Windows synchronization structures
typedef struct _CRITICAL_SECTION {
    void* DebugInfo;
    int32_t LockCount;
    int32_t RecursionCount;
    void* OwningThread;
    void* LockSemaphore;
    uintptr_t SpinCount;
} CRITICAL_SECTION;

// Windows system information structure
typedef struct _SYSTEM_INFO {
    uint16_t wProcessorArchitecture;
    uint16_t wReserved;
    uint32_t dwPageSize;
    void* lpMinimumApplicationAddress;
    void* lpMaximumApplicationAddress;
    uintptr_t dwActiveProcessorMask;
    uint32_t dwNumberOfProcessors;
    uint32_t dwProcessorType;
    uint32_t dwAllocationGranularity;
    uint16_t wProcessorLevel;
    uint16_t wProcessorRevision;
} SYSTEM_INFO;

// Windows constants
#define INFINITE 0xFFFFFFFF
#define CREATE_SUSPENDED 0x00000004

// Windows file opening flags (macOS equivalents)
#define _O_RANDOM       0x0000  // No direct equivalent on macOS
#define _O_TEXT         0x4000  // Text mode
#define _O_BINARY       0x8000  // Binary mode  
#define _O_RDONLY       O_RDONLY // Read only
#define _O_WRONLY       O_WRONLY // Write only
#define _O_RDWR         O_RDWR   // Read/write
#define _O_SEQUENTIAL   0x0020   // Sequential access hint
#define _O_SHORT_LIVED  0x1000   // Short-lived file hint
#define _O_TEMPORARY    0x0040   // Temporary file

// Windows file mode global variable
extern int _fmode;

// Windows file attribute constants
#define INVALID_FILE_ATTRIBUTES 0xFFFFFFFF

// Windows overlapped I/O structures
typedef struct _OVERLAPPED {
    uintptr_t Internal;
    uintptr_t InternalHigh;
    union {
        struct {
            uint32_t Offset;
            uint32_t OffsetHigh;
        };
        void* Pointer;
    };
    void* hEvent;
} OVERLAPPED;

typedef OVERLAPPED* LPOVERLAPPED;

// Windows performance timing functions
inline int QueryPerformanceFrequency(LARGE_INTEGER* lpFrequency) {
    // Use mach timebase for macOS
    if (lpFrequency) {
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        // Convert to frequency (ticks per second)
        lpFrequency->QuadPart = 1000000000LL * timebase.denom / timebase.numer;
    }
    return 1;
}

inline int QueryPerformanceCounter(LARGE_INTEGER* lpPerformanceCount) {
    // Use mach_absolute_time for macOS high-resolution timing
    if (lpPerformanceCount) {
        lpPerformanceCount->QuadPart = mach_absolute_time();
    }
    return 1;
}

inline int SetPriorityClass(void* hProcess, uint32_t dwPriorityClass) {
    // macOS doesn't have direct equivalent, return success
    return 1;
}

inline int SetThreadPriority(void* hThread, int nPriority) {
    // macOS thread priority setting would be complex, stub for now
    return 1;
}

// Windows process affinity functions
inline int GetProcessAffinityMask(void* hProcess, uintptr_t* lpProcessAffinityMask, uintptr_t* lpSystemAffinityMask) {
    // macOS doesn't have direct process affinity, return all CPUs available
    if (lpProcessAffinityMask) *lpProcessAffinityMask = 0xFFFFFFFF;
    if (lpSystemAffinityMask) *lpSystemAffinityMask = 0xFFFFFFFF;
    return 1;
}

// Windows thread creation function - use proper function pointer type
typedef unsigned long (*LPTHREAD_START_ROUTINE)(void*);

inline void* CreateThread(void* lpThreadAttributes, size_t dwStackSize, LPTHREAD_START_ROUTINE lpStartAddress, void* lpParameter, uint32_t dwCreationFlags, unsigned long* lpThreadId) {
    // This is a complex function that would need proper pthread implementation
    // For now, return a dummy handle since this is used for CPU detection
    if (lpThreadId) *lpThreadId = 1;
    return (void*)1;
}

// Windows thread control functions
inline uint32_t ResumeThread(void* hThread) {
    // Return previous suspend count (0 = wasn't suspended)
    return 0;
}

inline int CloseHandle(void* hObject) {
    // macOS equivalent would depend on handle type, return success for now
    return 1;
}

// Windows synchronization function
inline uint32_t WaitForSingleObject(void* hHandle, uint32_t dwMilliseconds) {
    // Simplified implementation - just sleep for the timeout period
    if (dwMilliseconds != INFINITE) {
        usleep(dwMilliseconds * 1000);  // Use usleep directly to avoid circular dependency
    }
    return 0;  // WAIT_OBJECT_0 (success)
}

// Windows system information function
inline void GetSystemInfo(SYSTEM_INFO* lpSystemInfo) {
    if (lpSystemInfo) {
        // Fill with basic macOS system info
        lpSystemInfo->dwNumberOfProcessors = sysconf(_SC_NPROCESSORS_ONLN);
        lpSystemInfo->dwPageSize = getpagesize();
        lpSystemInfo->wProcessorArchitecture = 0; // Generic
        lpSystemInfo->dwActiveProcessorMask = (1 << lpSystemInfo->dwNumberOfProcessors) - 1;
    }
}

// Windows thread affinity function
inline uintptr_t SetThreadAffinityMask(void* hThread, uintptr_t dwThreadAffinityMask) {
    // macOS doesn't have direct thread affinity control, return success mask
    return dwThreadAffinityMask;
}

// Windows critical section functions - implement using pthread mutex
inline void InitializeCriticalSection(CRITICAL_SECTION* lpCriticalSection) {
    if (lpCriticalSection) {
        pthread_mutex_t* mutex = (pthread_mutex_t*)malloc(sizeof(pthread_mutex_t));
        pthread_mutex_init(mutex, NULL);
        lpCriticalSection->DebugInfo = mutex;
        lpCriticalSection->LockCount = 0;
    }
}

inline void DeleteCriticalSection(CRITICAL_SECTION* lpCriticalSection) {
    if (lpCriticalSection && lpCriticalSection->DebugInfo) {
        pthread_mutex_destroy((pthread_mutex_t*)lpCriticalSection->DebugInfo);
        free(lpCriticalSection->DebugInfo);
        lpCriticalSection->DebugInfo = NULL;
    }
}

inline void EnterCriticalSection(CRITICAL_SECTION* lpCriticalSection) {
    if (lpCriticalSection && lpCriticalSection->DebugInfo) {
        pthread_mutex_lock((pthread_mutex_t*)lpCriticalSection->DebugInfo);
    }
}

inline void LeaveCriticalSection(CRITICAL_SECTION* lpCriticalSection) {
    if (lpCriticalSection && lpCriticalSection->DebugInfo) {
        pthread_mutex_unlock((pthread_mutex_t*)lpCriticalSection->DebugInfo);
    }
}

inline int MessageBox(void* hWnd, const char* lpText, const char* lpCaption, uint32_t uType) {
    // Print to console instead of showing message box on macOS
    printf("[MessageBox] %s: %s\n", lpCaption ? lpCaption : "Message", lpText ? lpText : "");
    return 1; // IDOK
}

// Windows debug output function
inline void OutputDebugString(const char* lpOutputString) {
    // Print to console on macOS
    if (lpOutputString) {
        printf("[DEBUG] %s", lpOutputString);
    }
}

// Windows file path functions
inline char* _fullpath(char* absPath, const char* relPath, size_t maxLength) {
    // Use realpath for macOS
    return realpath(relPath, absPath);
}

// Windows file attribute functions
inline uint32_t GetFileAttributes(const char* lpFileName) {
    struct stat st;
    if (stat(lpFileName, &st) == 0) {
        return 0;  // FILE_ATTRIBUTE_NORMAL
    }
    return INVALID_FILE_ATTRIBUTES;
}

inline void* LoadLibrary(const char* lpLibFileName) {
    // Use dlopen for dynamic library loading on macOS
    return dlopen(lpLibFileName, RTLD_LAZY);
}

// Math functions compatibility
#include <math.h>
inline void cry_sincos(double angle, double* pCosSin) 
{
    pCosSin[0] = cos(angle);
    pCosSin[1] = sin(angle);
}

inline void cry_sincosf(float angle, float* pCosSin)
{
    pCosSin[0] = cosf(angle);
    pCosSin[1] = sinf(angle);
}

inline float cry_cosf(float op) { return cosf(op); }
inline float cry_sinf(float op) { return sinf(op); }
inline float cry_acosf(float op) { return acosf(op); }
inline float cry_asinf(float op) { return asinf(op); }
inline float cry_atanf(float op) { return atanf(op); }
inline float cry_atan2f(float y, float x) { return atan2f(y, x); }
inline float cry_expf(float op) { return expf(op); }
inline float cry_logf(float op) { return logf(op); }
inline float cry_sqrtf(float op) { return sqrtf(op); }
inline float cry_fabsf(float op) { return fabsf(op); }
inline float cry_floorf(float op) { return floorf(op); }
inline float cry_ceilf(float op) { return ceilf(op); }
inline float cry_tanf(float op) { return tanf(op); }

// Handle declaration
typedef void* HANDLE;

// Missing Windows types
typedef intptr_t INT_PTR;
typedef uintptr_t UINT_PTR;
typedef uintptr_t DWORD_PTR;

// Additional math functions - use function overloading properly
inline float cry_fmodf(float x, float y) { return fmodf(x, y); }
inline double cry_fmod(double x, double y) { return fmod(x, y); }

// Windows min/max macros
#define __min(a,b) ((a) < (b) ? (a) : (b))
#define __max(a,b) ((a) > (b) ? (a) : (b))

// Additional missing functions
inline float cry_powf(float base, float exp) { return powf(base, exp); }
inline double cry_pow(double base, double exp) { return pow(base, exp); }

// File operations - macOS doesn't use CryPak by default
// Note: fxopen is defined in ILog.h, but we need fopen_nocase for Linux-style behavior
inline FILE* fopen_nocase(const char* file, const char* mode) { 
    // macOS is case-sensitive like Linux, so just use regular fopen
    return fopen(file, mode); 
}
inline void fxclose(FILE* f) { fclose(f); }

// String comparison functions
#define stricmp strcasecmp
#define strnicmp strncasecmp
#define _stricmp strcasecmp
#define _strnicmp strncasecmp

// Windows sleep function (Sleep vs sleep - different parameters)
inline void Sleep(uint32_t dwMilliseconds) {
    usleep(dwMilliseconds * 1000);  // usleep takes microseconds
}

// Moved to earlier in file

// Windows memory comparison function
inline int memicmp(const void* buf1, const void* buf2, size_t count) {
    return strncasecmp((const char*)buf1, (const char*)buf2, count);
}

// Path constants
#define _MAX_PATH 1024
#define MAX_PATH 1024
#define _MAX_DRIVE 3
#define _MAX_DIR 256
#define _MAX_FNAME 256
#define _MAX_EXT 256

// Atomic operations moved to C++ section

// CPU intrinsics compatibility
#if defined(__aarch64__) || defined(__arm64__)
// ARM64 doesn't have SSE, but we can define these for compatibility
#define _MM_HINT_NTA 0
inline void _mm_prefetch(const char* p, int i) { __builtin_prefetch(p, 0, 0); }
// ARM64 doesn't have RDTSC, use mach_absolute_time instead
inline uint64_t __rdtsc() { return mach_absolute_time(); }
#else
// Intel Mac
#include <xmmintrin.h>
#ifndef _MM_HINT_NTA
#define _MM_HINT_NTA _MM_HINT_T0
#endif
// Intel Mac has RDTSC
inline uint64_t __rdtsc() { return __builtin_ia32_rdtsc(); }
#endif

#endif

#ifdef __cplusplus
}

// Atomic operations for multi-threading - template approach like Linux
template<typename T>
inline T InterlockedIncrement(volatile T* target) {
    return __sync_add_and_fetch(target, 1);
}

template<typename T>  
inline T InterlockedDecrement(volatile T* target) {
    return __sync_sub_and_fetch(target, 1);
}

// Math function support will be handled by proper include order

// macOS-specific global variables for compatibility
extern void* g_hSystemHandle;
extern int _fmode;  // Global file mode variable
#define DLL_SYSTEM "libCrySystem.dylib"  // macOS shared library name
#define DLL_GAME   "libCryGame.dylib"

// Forward declarations for CryEngine math functions (defined in headers)
template <class F> struct Vec3_tpl;
template <class F> struct Quaternion_tpl;
template <class F, int SI, int SJ> struct Matrix33_tpl;

// These will be properly defined when the math headers are included
template<class F> 
F GetLengthSquared( const Vec3_tpl<F> &v );
template<class F> 
F GetLength( const Vec3_tpl<F>& v );

// Quaternion from matrix conversion
template<class F,int SI,int SJ> 
Quaternion_tpl<F> GetQuatFromMat33(const Matrix33_tpl<F,SI,SJ>& m);
#endif

#endif //_CRY_COMMON_MACOS_SPECIFIC_HDR_
