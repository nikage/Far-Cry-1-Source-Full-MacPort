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

// Define BOOL before any system headers to avoid conflicts
#ifndef BOOL
#define BOOL int
#endif

// Define __noop for compatibility
#ifndef __noop
#define __noop ((void)0)
#endif

// Define DebugBreak for compatibility
#ifndef DebugBreak
#define DebugBreak() __builtin_trap()
#endif

#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>
#include <unistd.h>
#include <pthread.h>
#include <stdlib.h>  // for malloc/free on macOS
#include <mach/mach_time.h>
#include <dirent.h>
#include <fnmatch.h>
#include <string.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>  // for _NSGetExecutablePath
#include <stdio.h>        // for FILE type
#include <dlfcn.h>        // for dlopen/dlsym
#include <fcntl.h>        // for O_* file flags
#include <sys/stat.h>     // for stat function
#include <ctype.h>        // for tolower function
#include <stdarg.h>       // for va_list
#include <malloc/malloc.h> // for malloc_zone_check

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
// BOOL is defined at the top of the file
#ifndef DWORD
typedef uint32_t        DWORD;
#endif
typedef int32_t         LONG;
// HRESULT is defined by macOS system headers as SInt32 (int)
// But we need to ensure it's available for our code
#ifndef HRESULT
typedef int HRESULT;
#endif
typedef void*           HMODULE;
typedef void*           HINSTANCE;
typedef void*           HWND;
typedef void*           HDC;
typedef void*           HGLRC;
typedef void*           LPVOID;
typedef char*           LPSTR;
typedef const char*     LPCSTR;
typedef uint8_t         BYTE;
typedef uint16_t        WORD;
typedef uintptr_t       WPARAM;
typedef intptr_t        LPARAM;
typedef intptr_t        LRESULT;
typedef void*           HBRUSH;
typedef void*           HICON;
typedef void*           HCURSOR;
typedef void*           HINTERNET;  // Windows Internet handle type
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

#define INVALID_HANDLE_VALUE (HANDLE)-1l

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

#if defined(_DEBUG)
inline int CryIsHeapValid()
{
    malloc_zone_t *zone = malloc_default_zone();
    if (!zone)
        return 1;
    return malloc_zone_check(zone) != 0;
}
#else
inline int CryIsHeapValid() { return 1; }
#endif

inline BOOL IsBadReadPtr(const void* lp, size_t ucb)
{
    // Stub implementation - assume all pointers are valid on macOS
    // In a real implementation, this would check if the memory is readable
    return FALSE;
}

// Windows directory functions with POSIX alternatives
#include <sys/stat.h>
#include <errno.h>

inline BOOL CreateDirectory(LPCSTR lpPathName, void* lpSecurityAttributes) {
    // POSIX implementation using mkdir
    if (mkdir(lpPathName, 0755) == 0) {
        return TRUE;  // Success
    } else if (errno == EEXIST) {
        return TRUE;  // Directory already exists, consider this success
    } else {
        return FALSE; // Failed to create directory
    }
}

// Windows file attribute constants
#ifndef FILE_ATTRIBUTE_NORMAL
#define FILE_ATTRIBUTE_NORMAL 0x00000080
#endif

#ifndef FILE_ATTRIBUTE_READONLY
#define FILE_ATTRIBUTE_READONLY 0x00000001
#endif

#ifndef FILE_ATTRIBUTE_SYSTEM
#define FILE_ATTRIBUTE_SYSTEM 0x00000004
#endif

#ifndef FILE_ATTRIBUTE_DIRECTORY
#define FILE_ATTRIBUTE_DIRECTORY 0x00000010
#endif

#ifndef FILE_ATTRIBUTE_EXECUTABLE
#define FILE_ATTRIBUTE_EXECUTABLE 0x00000040
#endif

inline BOOL SetFileAttributes(LPCSTR lpFileName, DWORD dwFileAttributes) {
    // macOS implementation using chmod for basic file attributes
    if (!lpFileName) return FALSE;
    
    // Convert Windows file attributes to POSIX permissions
    mode_t mode = 0;
    
    // Basic permissions - most files should be readable/writable by owner
    mode = S_IRUSR | S_IWUSR;
    
    // Add group and other permissions if not system-only
    if (!(dwFileAttributes & FILE_ATTRIBUTE_SYSTEM)) {
        mode |= S_IRGRP | S_IROTH;
        if (!(dwFileAttributes & FILE_ATTRIBUTE_READONLY)) {
            mode |= S_IWGRP | S_IWOTH;
        }
    }
    
    // Set executable permission for certain file types
    if (dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY || 
        dwFileAttributes & FILE_ATTRIBUTE_EXECUTABLE) {
        mode |= S_IXUSR | S_IXGRP | S_IXOTH;
    }
    
    return chmod(lpFileName, mode) == 0;
}

// Windows compatibility macros
#define ILINE inline
#define _inline inline
#define APIENTRY

// Windows four-character code macro
#ifndef MAKEFOURCC
#define MAKEFOURCC(ch0, ch1, ch2, ch3) \
    ((DWORD)(BYTE)(ch0) | ((DWORD)(BYTE)(ch1) << 8) | \
     ((DWORD)(BYTE)(ch2) << 16) | ((DWORD)(BYTE)(ch3) << 24))
#endif
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
// inline void* GetCurrentProcess() {
//     return (void*)1;  // Dummy process handle
// }

// Windows thread functions - avoid conflicts with Carbon framework
// Only define if not already defined by system headers
// Commented out due to conflicts with system headers
// #ifndef GetCurrentThread
// #ifndef WIN32GETCURRENTTHREAD_DEFINED
// #define WIN32GETCURRENTTHREAD_DEFINED
// inline void* Win32GetCurrentThread() {
//     return (void*)pthread_self();
// }
// #endif
// #define GetCurrentThread Win32GetCurrentThread
// #endif

#ifndef GetCurrentThreadId
inline uint32_t Win32GetCurrentThreadId() {
    // Use mach_thread_self() on macOS for a proper thread ID
    #ifdef __APPLE__
        return (uint32_t)mach_thread_self();
    #else
        // Fallback: use a hash of pthread_t to avoid truncation
        pthread_t tid = pthread_self();
        return (uint32_t)((uintptr_t)tid ^ ((uintptr_t)tid >> 32));
    #endif
}
#define GetCurrentThreadId Win32GetCurrentThreadId
#endif

// Old stub implementations removed - replaced with proper implementations below

// Windows priority constants
#define REALTIME_PRIORITY_CLASS     0x00000100
#define THREAD_PRIORITY_TIME_CRITICAL 15

// Windows type definitions
typedef int64_t INT64;
typedef int64_t LONGLONG;
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
#define FILE_ATTRIBUTE_DIRECTORY 0x10
#define _A_SUBDIR               0x10
#define _A_RDONLY               0x01

// Windows file search structures
struct __finddata64_t {
    uint32_t attrib;
    int64_t time_create;
    int64_t time_access; 
    int64_t time_write;
    int64_t size;
    char name[260];
};

// Windows 32-bit finddata structure
struct _finddata_t {
    uint32_t attrib;
    int32_t time_create;
    int32_t time_access;
    int32_t time_write;
    int32_t size;
    char name[260];
};

// Windows stat structure
#ifndef __STAT64_DEFINED
#define __STAT64_DEFINED
// Use macOS stat structure directly by defining it as an alias
#define __stat64 stat
#endif

// Windows file search functions
typedef struct FindHandle64 {
    DIR* dir;
    char directory[PATH_MAX];
    char pattern[PATH_MAX];
} FindHandle64;

inline bool FillFindData64(FindHandle64* state, struct __finddata64_t* fileinfo) {
    if (!state || !state->dir || !fileinfo)
        return false;

    struct dirent* entry = NULL;
    while ((entry = readdir(state->dir)) != NULL) {
        const char* name = entry->d_name;
        if (!name || name[0] == '\0')
            continue;
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0)
            continue;
        if (fnmatch(state->pattern, name, FNM_CASEFOLD) != 0)
            continue;

        char fullPath[PATH_MAX * 2];
        size_t len = strlen(state->directory);
        strncpy(fullPath, state->directory, sizeof(fullPath) - 1);
        fullPath[sizeof(fullPath) - 1] = '\0';
        if (len > 0 && state->directory[len - 1] != '/')
            strncat(fullPath, "/", sizeof(fullPath) - strlen(fullPath) - 1);
        strncat(fullPath, name, sizeof(fullPath) - strlen(fullPath) - 1);

        struct stat st;
        if (stat(fullPath, &st) != 0)
            continue;

        memset(fileinfo, 0, sizeof(*fileinfo));
        fileinfo->attrib = S_ISDIR(st.st_mode) ? _A_SUBDIR : 0;
        fileinfo->time_create = (int64_t)st.st_ctimespec.tv_sec;
        fileinfo->time_access = (int64_t)st.st_atimespec.tv_sec;
        fileinfo->time_write = (int64_t)st.st_mtimespec.tv_sec;
        fileinfo->size = (int64_t)st.st_size;
        strncpy(fileinfo->name, name, sizeof(fileinfo->name) - 1);
        fileinfo->name[sizeof(fileinfo->name) - 1] = '\0';
        return true;
    }

    return false;
}

inline intptr_t _findfirst64(const char* filespec, struct __finddata64_t* fileinfo) {
    if (!filespec || !fileinfo)
        return -1;

    char directory[PATH_MAX];
    char pattern[PATH_MAX];
    const char* sep = strrchr(filespec, '/');
    const char* sepAlt = strrchr(filespec, '\\');
    if (!sep || (sepAlt && sepAlt > sep))
        sep = sepAlt;

    if (!sep) {
        strcpy(directory, ".");
        strncpy(pattern, filespec, sizeof(pattern) - 1);
        pattern[sizeof(pattern) - 1] = '\0';
    } else {
        size_t dirLen = (size_t)(sep - filespec);
        if (dirLen >= sizeof(directory))
            dirLen = sizeof(directory) - 1;
        memcpy(directory, filespec, dirLen);
        directory[dirLen] = '\0';
        strncpy(pattern, sep + 1, sizeof(pattern) - 1);
        pattern[sizeof(pattern) - 1] = '\0';
        if (directory[0] == '\0')
            strcpy(directory, ".");
    }

    DIR* dir = opendir(directory);
    if (!dir)
        return -1;

    FindHandle64* state = (FindHandle64*)malloc(sizeof(FindHandle64));
    if (!state) {
        closedir(dir);
        return -1;
    }
    state->dir = dir;
    strncpy(state->directory, directory, sizeof(state->directory) - 1);
    state->directory[sizeof(state->directory) - 1] = '\0';
    if (pattern[0] == '\0')
        strcpy(state->pattern, "*");
    else {
        strncpy(state->pattern, pattern, sizeof(state->pattern) - 1);
        state->pattern[sizeof(state->pattern) - 1] = '\0';
    }

    if (!FillFindData64(state, fileinfo)) {
        closedir(state->dir);
        free(state);
        return -1;
    }

    return (intptr_t)state;
}

inline int _findnext64(intptr_t handle, struct __finddata64_t* fileinfo) {
    FindHandle64* state = (FindHandle64*)handle;
    if (!state || !fileinfo)
        return -1;
    if (!FillFindData64(state, fileinfo))
        return -1;
    return 0;
}

inline int _findclose(intptr_t handle) {
    FindHandle64* state = (FindHandle64*)handle;
    if (!state)
        return -1;
    if (state->dir)
        closedir(state->dir);
    free(state);
    return 0;
}

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
} OVERLAPPED, *LPOVERLAPPED;

// Windows overlapped I/O functions
inline bool GetOverlappedResult(void* hFile, LPOVERLAPPED lpOverlapped, uint32_t* lpNumberOfBytesTransferred, bool bWait) {
    // For macOS, we don't have overlapped I/O, so just return success
    if (lpNumberOfBytesTransferred) {
        *lpNumberOfBytesTransferred = 0;
    }
    return true;
}

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

// Windows GetTickCount function - returns milliseconds since system start
static inline uint32_t GetTickCount() {
    // Use mach_absolute_time and convert to milliseconds
    static mach_timebase_info_data_t timebase = {0, 0};
    if (timebase.denom == 0) {
        mach_timebase_info(&timebase);
    }
    uint64_t time_ns = mach_absolute_time() * timebase.numer / timebase.denom;
    return (uint32_t)(time_ns / 1000000);  // Convert nanoseconds to milliseconds
}

inline int SetPriorityClass(void* hProcess, uint32_t dwPriorityClass) {
    // macOS doesn't have direct equivalent, return success
    return 1;
}

// Old stub implementations removed - replaced with proper implementations below

// Windows thread creation function - use proper function pointer type
typedef unsigned long (*LPTHREAD_START_ROUTINE)(void*);

// CreateThread implementation - generic version
inline void* CreateThreadImpl(void* lpThreadAttributes, size_t dwStackSize, LPTHREAD_START_ROUTINE lpStartAddress, void* lpParameter, uint32_t dwCreationFlags, void* lpThreadId) {
    // This is a complex function that would need proper pthread implementation
    // For now, return a dummy handle since this is used for CPU detection
    if (lpThreadId) {
        // Handle different thread ID types
        if (sizeof(unsigned long) == sizeof(uint32_t)) {
            // Same size, can safely cast
            *(uint32_t*)lpThreadId = 1;
        } else {
            // Different sizes, handle as unsigned long
            *(unsigned long*)lpThreadId = 1;
        }
    }
    return (void*)1;
}

// Macro to handle different thread ID types
#define CreateThread(attrs, stack, func, param, flags, threadId) \
    CreateThreadImpl(attrs, stack, (LPTHREAD_START_ROUTINE)(func), param, flags, (void*)(threadId))

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
    auto mutex = (pthread_mutex_t*)malloc(sizeof(pthread_mutex_t));
        if (!mutex) {
            lpCriticalSection->DebugInfo = NULL;
            lpCriticalSection->LockCount = 0;
            return;
        }
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(mutex, &attr);
        pthread_mutexattr_destroy(&attr);
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
#ifndef OutputDebugString
inline void OutputDebugString(const char* lpOutputString) {
    // Print to console on macOS
    if (lpOutputString) {
        printf("[DEBUG] %s", lpOutputString);
    }
}
#endif

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

// Windows file number function
inline int _fileno(FILE* stream) {
    return fileno(stream);  // macOS has fileno, not _fileno
}

// Windows string conversion function
inline char* strlwr(char* str) {
    // Convert string to lowercase
    if (str) {
        for (char* p = str; *p; p++) {
            *p = tolower(*p);
        }
    }
    return str;
}

// Windows 64-bit multiplication function
inline int64_t Int32x32To64(int32_t a, int32_t b) {
    return (int64_t)a * (int64_t)b;
}

// Windows directory creation function
inline int _mkdir(const char* dirname) {
    return mkdir(dirname, 0755);  // Create directory with standard permissions
}

// Windows heap minimization function
inline int _heapmin() {
    // macOS doesn't have direct heap minimization, but malloc_zone_pressure_relief can help
    // For now, just return success - the system will handle memory management
    return 0;
}

// Windows file stat function - just use fstat since __stat64 is aliased to stat
inline int _fstat64(int fd, struct stat* buf) {
    return fstat(fd, buf);
}

// Windows string formatting functions
inline int _snprintf(char* buffer, size_t count, const char* format, ...) {
    va_list args;
    va_start(args, format);
    int result = vsnprintf(buffer, count, format, args);
    va_end(args);
    return result;
}

inline int _vsnprintf(char* buffer, size_t count, const char* format, va_list args) {
    return vsnprintf(buffer, count, format, args);
}

inline void* LoadLibrary(const char* lpLibFileName) {
    // Use dlopen for dynamic library loading on macOS
    return dlopen(lpLibFileName, RTLD_LAZY);
}

// Note: macOS uses USE_CRT=1 so it doesn't need Windows heap functions

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
inline float cry_tanhf(float op) { return tanhf(op); }

// Handle declaration
typedef void* HANDLE;

// Missing Windows types
typedef intptr_t INT_PTR;
typedef uintptr_t UINT_PTR;
typedef uintptr_t ULONG_PTR;
typedef intptr_t LONG_PTR;
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

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus

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

// Additional Windows API functions needed for RefStreamEngine
// File access constants
#define GENERIC_READ 0x80000000
#define GENERIC_WRITE 0x40000000
#define GENERIC_EXECUTE 0x20000000
#define GENERIC_ALL 0x10000000

#define FILE_SHARE_READ 0x00000001
#define FILE_SHARE_WRITE 0x00000002
#define FILE_SHARE_DELETE 0x00000004

#define CREATE_NEW 1
#define CREATE_ALWAYS 2
#define OPEN_EXISTING 3
#define OPEN_ALWAYS 4
#define TRUNCATE_EXISTING 5

#define INVALID_FILE_SIZE 0xFFFFFFFF

// Additional Windows API constants
#define FILE_FLAG_OVERLAPPED 0x40000000
#define ERROR_NOT_ENOUGH_MEMORY 8
#define ERROR_INVALID_USER_BUFFER 1784
#define ERROR_NO_SYSTEM_RESOURCES 1450
#define FILE_BEGIN 0
#define INVALID_SET_FILE_POINTER 0xFFFFFFFF

// Additional Windows API functions for file operations
inline int DeleteFile(const char* lpFileName) {
    return unlink(lpFileName) == 0 ? 1 : 0;
}

inline int RemoveDirectory(const char* lpPathName) {
    return rmdir(lpPathName) == 0 ? 1 : 0;
}

inline void* GetFocus() {
    // Simplified implementation - just return a dummy window handle
    return (void*)1;
}

// Version info functions - simplified implementations
typedef struct {
    uint32_t dwSignature;
    uint32_t dwStrucVersion;
    uint32_t dwFileVersionMS;
    uint32_t dwFileVersionLS;
    uint32_t dwProductVersionMS;
    uint32_t dwProductVersionLS;
    uint32_t dwFileFlagsMask;
    uint32_t dwFileFlags;
    uint32_t dwFileOS;
    uint32_t dwFileType;
    uint32_t dwFileSubtype;
    uint32_t dwFileDateMS;
    uint32_t dwFileDateLS;
} VS_FIXEDFILEINFO;

inline int VerQueryValue(void* pBlock, const char* lpSubBlock, void** lplpBuffer, uint32_t* puLen) {
    // Simplified implementation - just return failure
    return 0;
}

inline int GetFileVersionInfoSize(const char* lptstrFilename, uint32_t* lpdwHandle) {
    // Simplified implementation - return 0 (no version info)
    return 0;
}

inline int GetFileVersionInfo(const char* lptstrFilename, uint32_t dwHandle, uint32_t dwLen, void* lpData) {
    // Simplified implementation - return failure
    return 0;
}

inline void SetLastError(uint32_t dwErrCode) {
    // Simplified implementation - just store the error code
    extern int errno;
    errno = dwErrCode;
}

// DirectX stubs for macOS
struct IDirectDraw7 {
    virtual void Release() = 0;
    virtual int GetDeviceIdentifier(void* pIdentifier, uint32_t dwFlags) = 0;
    virtual HRESULT GetAvailableVidMem(void* lpDDSCaps, uint32_t* lpdwTotal, uint32_t* lpdwFree) = 0;
};

typedef IDirectDraw7* LPDIRECTDRAW7;
typedef void* LPDIRECTDRAWSURFACE7;
typedef struct {
    uint32_t dwSize;
    char szDriver[512];
    char szDescription[512];
    char szName[512];
    char szComment[512];
    uint32_t dwVersion;
    uint32_t dwVersion2;
    char szDate[512];
    char szVDD[512];
    uint32_t dwDeviceId;
    uint32_t dwRevision;
    uint32_t dwSubSysId;
    uint32_t dwVendorId;
} DDDEVICEIDENTIFIER2;

typedef struct {
    uint32_t dwLength;
    uint32_t dwMemoryLoad;
    uint32_t dwTotalPhys;
    uint32_t dwAvailPhys;
    uint32_t dwTotalPageFile;
    uint32_t dwAvailPageFile;
    uint32_t dwTotalVirtual;
    uint32_t dwAvailVirtual;
} MEMORYSTATUS;

// DirectX function stubs
#define IID_IDirectDraw7 {0x15e65ec0, 0x3b9c, 0x11d2, {0xb9, 0x2f, 0x00, 0x60, 0x97, 0x97, 0xea, 0x5b}}
#define SUCCEEDED(hr) ((hr) >= 0)
#define FAILED(hr) ((hr) < 0)

// FreeLibrary defined later in Windows library functions section

// Additional Windows types
typedef struct {
    uint32_t Data1;
    uint16_t Data2;
    uint16_t Data3;
    uint8_t Data4[8];
} GUID;

// IID, REFIID, and IUnknown are defined by macOS system headers

// Time types
typedef time_t __time64_t;

// Additional Windows types
typedef char TCHAR;
typedef uint32_t DWORD;

typedef struct {
    uint16_t wYear;
    uint16_t wMonth;
    uint16_t wDayOfWeek;
    uint16_t wDay;
    uint16_t wHour;
    uint16_t wMinute;
    uint16_t wSecond;
    uint16_t wMilliseconds;
} SYSTEMTIME;

// FILETIME already defined above

// DirectX callback types
typedef int (*LPDDENUMCALLBACKEXA)(void*, void*, void*, void*, void*);

// Windows string macros
#define _T(x) x
#define TEXT(x) x

// Windows min/max macros
#ifndef min
#define min(a,b) (((a) < (b)) ? (a) : (b))
#endif
#ifndef max
#define max(a,b) (((a) > (b)) ? (a) : (b))
#endif

// Windows socket constants and functions
#ifndef INVALID_SOCKET
#define INVALID_SOCKET (-1)
#endif

#ifndef SOCKET_ERROR
#define SOCKET_ERROR (-1)
#endif

// Windows socket error codes
#ifndef WSAEWOULDBLOCK
#define WSAEWOULDBLOCK EAGAIN
#endif

#ifndef WSAEMSGSIZE
#define WSAEMSGSIZE EMSGSIZE
#endif

// Windows socket type
typedef int SOCKET;

// Windows POINT structure
typedef struct tagPOINT {
    LONG x;
    LONG y;
} POINT;

// Windows socket error function
extern int errno;
inline int WSAGetLastError() {
    // On macOS, use errno for socket errors
    return errno;
}

// Windows math functions
#include <cmath>
inline int _isnan(double x) {
    return std::isnan(x);
}

inline int _finite(double x) {
    return std::isfinite(x);
}

// Windows input functions with POSIX alternatives
typedef short SHORT;

// Windows virtual key constants
#define VK_NUMPAD1 0x61
#define VK_NUMPAD2 0x62
#define VK_NUMPAD4 0x64
#define VK_NUMPAD6 0x66
#define VK_INSERT 0x2D
#define VK_DELETE 0x2E
#define VK_PRIOR 0x21
#define VK_NEXT 0x22
#define VK_HOME 0x24
#define VK_END 0x23
#define VK_LEFT 0x25
#define VK_UP 0x26
#define VK_RIGHT 0x27
#define VK_DOWN 0x28
#define VK_ESCAPE 0x1B
#define VK_BACK 0x08
#define VK_TAB 0x09
#define VK_SUBTRACT 0x6D
#define VK_OEM_PLUS 0xBB
#define VK_OEM_4 0xDB
#define VK_OEM_6 0xDD
#define VK_RETURN 0x0D
#define VK_LCONTROL 0xA2
#define VK_OEM_1 0xBA
#define VK_OEM_7 0xDE
#define VK_OEM_3 0xC0
#define VK_LSHIFT 0xA0
#define VK_OEM_5 0xDC
#define VK_OEM_COMMA 0xBC
#define VK_OEM_PERIOD 0xBE
#define VK_OEM_2 0xBF
#define VK_RSHIFT 0xA1
#define VK_MULTIPLY 0x6A
#define VK_LMENU 0xA4
#define VK_SPACE 0x20
#define VK_CAPITAL 0x14
#define VK_F1 0x70
#define VK_F2 0x71
#define VK_F3 0x72
#define VK_F4 0x73
#define VK_F5 0x74
#define VK_F6 0x75
#define VK_F7 0x76
#define VK_F8 0x77
#define VK_F9 0x78
#define VK_F10 0x79
#define VK_F11 0x7A
#define VK_F12 0x7B
#define VK_NUMLOCK 0x90
#define VK_SCROLL 0x91
#define VK_NUMPAD7 0x67
#define VK_NUMPAD8 0x68
#define VK_NUMPAD9 0x69
#define VK_NUMPAD5 0x65
#define VK_ADD 0x6B
#define VK_NUMPAD3 0x63
#define VK_NUMPAD0 0x60
#define VK_DECIMAL 0x6E
#define VK_F13 0x7C
#define VK_F14 0x7D
#define VK_F15 0x7E
#define VK_KANA 0x15
#define VK_CONVERT 0x1C
#define VK_NONCONVERT 0x1D
#define VK_ACCEPT 0x1E
#define VK_MODECHANGE 0x1F
#define VK_SELECT 0x29
#define VK_PRINT 0x2A
#define VK_EXECUTE 0x2B
#define VK_SNAPSHOT 0x2C
#define VK_HELP 0x2F
#define VK_RCONTROL 0xA3
#define VK_DIVIDE 0x6F
#define VK_RMENU 0xA5
#define VK_PAUSE 0x13
#define VK_LWIN 0x5B
#define VK_RWIN 0x5C
#define VK_APPS 0x5D
#define VK_OEM_102 0xE2
#define VK_OEM_MINUS 0xBD

inline SHORT GetAsyncKeyState(int vKey) {
    // For now, return 0 (key not pressed) - could be enhanced with macOS key event monitoring
    // This would require implementing a proper input system using Core Graphics or similar
    return 0;
}

// Windows cursor functions with POSIX alternatives
typedef void* HCURSOR;

inline HCURSOR SetCursor(HCURSOR hCursor) {
    // POSIX implementation - could be enhanced with X11 or macOS cursor management
    // For now, just return the previous cursor (simplified)
    return hCursor;
}

// Windows time functions with POSIX alternatives
#include <sys/time.h>
#include <time.h>

inline unsigned int GetCurrentTime() {
    // POSIX implementation using gettimeofday
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (unsigned int)(tv.tv_sec * 1000 + tv.tv_usec / 1000);
}

// SYSTEMTIME already defined above

inline void GetLocalTime(SYSTEMTIME* lpSystemTime) {
    // POSIX implementation using localtime
    time_t now;
    struct tm* tm_info;
    
    time(&now);
    tm_info = localtime(&now);
    
    if (lpSystemTime) {
        lpSystemTime->wYear = (WORD)(1900 + tm_info->tm_year);
        lpSystemTime->wMonth = (WORD)(1 + tm_info->tm_mon);
        lpSystemTime->wDayOfWeek = (WORD)tm_info->tm_wday;
        lpSystemTime->wDay = (WORD)tm_info->tm_mday;
        lpSystemTime->wHour = (WORD)tm_info->tm_hour;
        lpSystemTime->wMinute = (WORD)tm_info->tm_min;
        lpSystemTime->wSecond = (WORD)tm_info->tm_sec;
        lpSystemTime->wMilliseconds = 0; // Not available from localtime
    }
}

// Windows directory path functions
inline BOOL MakeSureDirectoryPathExists(LPCSTR lpPath) {
    // POSIX implementation using mkdir with parent directories
    // For simplicity, just return TRUE - could be enhanced with recursive mkdir
    return TRUE;
}

// Windows string functions with POSIX alternatives
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <cctype>
#include <cwchar>

inline char* itoa(int value, char* str, int base) {
    // POSIX implementation using sprintf
    sprintf(str, "%d", value);
    return str;
}

inline char* ltoa(long value, char* str, int base) {
    // POSIX implementation using sprintf for long integers
    sprintf(str, "%ld", value);
    return str;
}

inline char* _strlwr(char* str) {
    // POSIX implementation using tolower
    char* p = str;
    while (*p) {
        *p = tolower(*p);
        p++;
    }
    return str;
}

inline double _wtof(const wchar_t* str) {
    // POSIX implementation using wcstod
    return wcstod(str, nullptr);
}

inline char* strupr(char* str) {
    // POSIX implementation using toupper
    char* p = str;
    while (*p) {
        *p = toupper(*p);
        p++;
    }
    return str;
}

inline int strnicoll(const char* s1, const char* s2, size_t n) {
    // POSIX implementation using strncasecmp
    return strncasecmp(s1, s2, n);
}

inline int stricoll(const char* s1, const char* s2) {
    // POSIX implementation using strcasecmp
    return strcasecmp(s1, s2);
}

// Windows path constants
#ifndef _MAX_PATH
#define _MAX_PATH 260
#endif

#ifndef _MAX_DRIVE
#define _MAX_DRIVE 3
#endif

#ifndef _MAX_DIR
#define _MAX_DIR 256
#endif

#ifndef _MAX_FNAME
#define _MAX_FNAME 256
#endif

#ifndef _MAX_EXT
#define _MAX_EXT 256
#endif

// Windows command line functions
// Provide a simple implementation for macOS
inline char* GetCommandLine() {
    // Simple implementation for macOS - just return the program name
    static char cmdLine[4096] = {0};
    if (cmdLine[0] == 0) {
        strcpy(cmdLine, "FarCry");
    }
    return cmdLine;
}

// Windows locale functions
inline unsigned short GetUserDefaultLangID() {
    // POSIX implementation - return English (US) as default
    // Could be enhanced to read from system locale
    return 0x0409; // English (United States)
}

// Windows code page constants
#ifndef CP_UTF8
#define CP_UTF8 65001
#endif

#ifndef CP_ACP
#define CP_ACP 0
#endif

// Windows clipboard format constants
#ifndef CF_UNICODETEXT
#define CF_UNICODETEXT 13
#endif

// Windows string conversion functions
#include <iconv.h>

// Windows string types
typedef unsigned int UINT;
typedef wchar_t* LPWSTR;

inline int MultiByteToWideChar(UINT CodePage, DWORD dwFlags, LPCSTR lpMultiByteStr, int cbMultiByte, LPWSTR lpWideCharStr, int cchWideChar) {
    // POSIX implementation using iconv
    // For simplicity, just copy the string as-is (not proper UTF-8 to UTF-16 conversion)
    if (lpMultiByteStr && lpWideCharStr && cchWideChar > 0) {
        int len = strlen(lpMultiByteStr);
        if (len >= cchWideChar) len = cchWideChar - 1;
        for (int i = 0; i < len; i++) {
            lpWideCharStr[i] = (wchar_t)lpMultiByteStr[i];
        }
        lpWideCharStr[len] = 0;
        return len;
    }
    return 0;
}

// Windows math functions - GetTranslationMat is already defined in Cry_Matrix.h

// Windows global variables
// __fmode defined in macos_fmode.cpp

// CDownloadManager stub implementation moved to DownloadManager.h

// Game instance and XML DOM creation stubs removed - will be handled in System.cpp

// Windows library functions
inline BOOL FreeLibrary(HMODULE hModule) {
    // Stub implementation for macOS
    // On macOS, dynamic libraries are managed differently
    return TRUE;
}

// Windows new.h replacement
#ifndef __new_h__
#define __new_h__

#include <new>

// Windows-specific new handler functions - use standard C++ equivalents
inline void* __cdecl _set_new_handler(void* handler) {
    return nullptr; // Return old handler (simplified)
}

inline void* __cdecl _query_new_handler(void) {
    return nullptr; // Return current handler (simplified)
}

#endif // __new_h__

// Time functions
inline __time64_t _time64(__time64_t* timer) {
    if (timer) {
        *timer = time(NULL);
        return *timer;
    }
    return time(NULL);
}

inline struct tm* _localtime64(const __time64_t* timer) {
    return localtime(timer);
}

// Windows timing functions
inline uint32_t timeGetTime() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

// Clipboard constants and functions
#define CF_TEXT 1
typedef void* HGLOBAL;

inline int OpenClipboard(void* hWnd) {
    // Simplified implementation - just return success
    return 1;
}

inline int IsClipboardFormatAvailable(uint32_t format) {
    // Simplified implementation - just return success
    return 1;
}

inline void* GetClipboardData(uint32_t uFormat) {
    // Simplified implementation - return dummy data
    return (void*)1;
}

inline int CloseClipboard() {
    // Simplified implementation - just return success
    return 1;
}

inline int EmptyClipboard() {
    // Simplified implementation - just return success
    return 1;
}

inline HGLOBAL SetClipboardData(uint32_t uFormat, HGLOBAL hMem) {
    // Simplified implementation - just return the handle
    return hMem;
}

// Memory management constants
#define GHND 0x0042

// Memory management functions
inline HGLOBAL GlobalAlloc(uint32_t uFlags, size_t dwBytes) {
    // Simplified implementation - allocate memory using malloc
    return (HGLOBAL)malloc(dwBytes);
}

inline void* GlobalLock(HGLOBAL hMem) {
    // Simplified implementation - just return the handle
    return hMem;
}

inline int GlobalUnlock(HGLOBAL hMem) {
    // Simplified implementation - just return success
    return 1;
}

// Windows time functions
inline int SystemTimeToFileTime(const SYSTEMTIME* lpSystemTime, FILETIME* lpFileTime) {
    // Simplified implementation - just fill with dummy values
    if (lpFileTime) {
        lpFileTime->dwLowDateTime = 0;
        lpFileTime->dwHighDateTime = 0;
    }
    return 1;
}

// Additional DirectX types
typedef struct {
    uint32_t dwCaps;
    uint32_t dwCaps2;
    uint32_t dwCaps3;
    uint32_t dwCaps4;
} DDSCAPS2;

#define DDSCAPS_LOCALVIDMEM 0x10000000
#define S_OK 0

// Memory functions
inline void ZeroMemory(void* dest, size_t count) {
    memset(dest, 0, count);
}

// Filter functions are defined in ScriptObjectSystem.cpp

#define WINAPI
#define WINAPIV

// Memory status function
inline void GlobalMemoryStatus(MEMORYSTATUS* lpBuffer) {
    // Simplified implementation - fill with dummy values
    lpBuffer->dwLength = sizeof(MEMORYSTATUS);
    lpBuffer->dwMemoryLoad = 50;
    lpBuffer->dwTotalPhys = (uint32_t)(8ULL * 1024 * 1024 * 1024); // 8GB
    lpBuffer->dwAvailPhys = (uint32_t)(4ULL * 1024 * 1024 * 1024);  // 4GB
    lpBuffer->dwTotalPageFile = (uint32_t)(16ULL * 1024 * 1024 * 1024); // 16GB
    lpBuffer->dwAvailPageFile = (uint32_t)(12ULL * 1024 * 1024 * 1024); // 12GB
    lpBuffer->dwTotalVirtual = (uint32_t)(8ULL * 1024 * 1024 * 1024);   // 8GB
    lpBuffer->dwAvailVirtual = (uint32_t)(6ULL * 1024 * 1024 * 1024);   // 6GB
}

// DirectX stub implementations
class StubDirectDraw7 : public IDirectDraw7 {
public:
    virtual void Release() override {}
    virtual int GetDeviceIdentifier(void* pIdentifier, uint32_t dwFlags) override {
        if (pIdentifier) {
            DDDEVICEIDENTIFIER2* id = (DDDEVICEIDENTIFIER2*)pIdentifier;
            memset(id, 0, sizeof(DDDEVICEIDENTIFIER2));
            id->dwSize = sizeof(DDDEVICEIDENTIFIER2);
            strcpy(id->szDescription, "macOS Graphics");
            strcpy(id->szDriver, "macOS Driver");
            id->dwDeviceId = 0x1234;
            id->dwVendorId = 0x8086;
        }
        return 0;
    }
    virtual HRESULT GetAvailableVidMem(void* lpDDSCaps, uint32_t* lpdwTotal, uint32_t* lpdwFree) override {
        if (lpdwTotal) *lpdwTotal = 1024 * 1024 * 1024; // 1GB
        if (lpdwFree) *lpdwFree = 512 * 1024 * 1024;    // 512MB
        return S_OK;
    }
};

// Function stubs
inline HRESULT DirectDrawCreateEx(GUID* lpGUID, void* lplpDD, const GUID& iid, void* pUnkOuter) {
    if (lplpDD) {
        *(LPDIRECTDRAW7*)lplpDD = new StubDirectDraw7();
    }
    return 0; // S_OK
}

// LoadLibrary already defined above

// GetProcAddress function removed - CryGetProcAddress macro handles this

// CryLoadLibrary is already defined in CryLibrary.h

// Implementation moved to macos_stubs.cpp

// Event functions
inline void* CreateEvent(void* lpEventAttributes, int bManualReset, int bInitialState, const char* lpName) {
    // Create a simple event using condition variable and mutex
    typedef struct {
        pthread_mutex_t mutex;
        pthread_cond_t condition;
        int signaled;
        int manual_reset;
    } macos_event_t;
    
    macos_event_t* event = (macos_event_t*)malloc(sizeof(macos_event_t));
    if (event) {
        pthread_mutex_init(&event->mutex, NULL);
        pthread_cond_init(&event->condition, NULL);
        event->signaled = bInitialState;
        event->manual_reset = bManualReset;
    }
    return event;
}

inline int SetEvent(void* hEvent) {
    if (!hEvent) return 0;
    typedef struct {
        pthread_mutex_t mutex;
        pthread_cond_t condition;
        int signaled;
        int manual_reset;
    } macos_event_t;
    
    macos_event_t* event = (macos_event_t*)hEvent;
    pthread_mutex_lock(&event->mutex);
    event->signaled = 1;
    if (event->manual_reset) {
        pthread_cond_broadcast(&event->condition);
    } else {
        pthread_cond_signal(&event->condition);
    }
    pthread_mutex_unlock(&event->mutex);
    return 1;
}

inline int ResetEvent(void* hEvent) {
    if (!hEvent) return 0;
    typedef struct {
        pthread_mutex_t mutex;
        pthread_cond_t condition;
        int signaled;
        int manual_reset;
    } macos_event_t;
    
    macos_event_t* event = (macos_event_t*)hEvent;
    pthread_mutex_lock(&event->mutex);
    event->signaled = 0;
    pthread_mutex_unlock(&event->mutex);
    return 1;
}

inline uint32_t WaitForSingleObjectEx(void* hHandle, uint32_t dwMilliseconds, int bAlertable) {
    // For now, just use regular WaitForSingleObject
    return WaitForSingleObject(hHandle, dwMilliseconds);
}

inline void SleepEx(uint32_t dwMilliseconds, int bAlertable) {
    usleep(dwMilliseconds * 1000);
}

// File functions
inline void* CreateFile(const char* lpFileName, uint32_t dwDesiredAccess, uint32_t dwShareMode, 
                       void* lpSecurityAttributes, uint32_t dwCreationDisposition, 
                       uint32_t dwFlagsAndAttributes, void* hTemplateFile) {
    int flags = 0;
    if (dwDesiredAccess & GENERIC_READ) {
        flags |= O_RDONLY;
    }
    if (dwDesiredAccess & GENERIC_WRITE) {
        flags |= O_WRONLY;
    }
    
    switch (dwCreationDisposition) {
        case CREATE_ALWAYS:
            flags |= O_CREAT | O_TRUNC;
            break;
        case CREATE_NEW:
            flags |= O_CREAT | O_EXCL;
            break;
        case OPEN_ALWAYS:
            flags |= O_CREAT;
            break;
        case OPEN_EXISTING:
            // No additional flags
            break;
        case TRUNCATE_EXISTING:
            flags |= O_TRUNC;
            break;
    }
    
    int fd = open(lpFileName, flags, 0644);
    if (fd == -1) {
        return (void*)(intptr_t)INVALID_HANDLE_VALUE;
    }
    return (void*)(intptr_t)fd;
}

inline uint32_t GetFileSize(void* hFile, uint32_t* lpFileSizeHigh) {
    if (!hFile || hFile == (void*)(intptr_t)INVALID_HANDLE_VALUE) {
        return INVALID_FILE_SIZE;
    }
    
    int fd = (int)(intptr_t)hFile;
    struct stat fileStat;
    if (fstat(fd, &fileStat) == -1) {
        return INVALID_FILE_SIZE;
    }
    
    if (lpFileSizeHigh) {
        *lpFileSizeHigh = (uint32_t)(fileStat.st_size >> 32);
    }
    
    return (uint32_t)(fileStat.st_size & 0xFFFFFFFF);
}

// CancelIo function
inline int CancelIo(void* hFile) {
    // Simplified implementation - just return success
    // On macOS, we don't have the same async I/O cancellation model
    return 1;  // success
}

// Additional Windows API functions
inline int ReadFile(void* hFile, void* lpBuffer, uint32_t nNumberOfBytesToRead, 
                   uint32_t* lpNumberOfBytesRead, void* lpOverlapped) {
    if (!hFile || hFile == (void*)(intptr_t)INVALID_HANDLE_VALUE) {
        return 0;
    }
    int fd = (int)(intptr_t)hFile;
    ssize_t bytesRead = read(fd, lpBuffer, nNumberOfBytesToRead);
    if (bytesRead == -1) {
        return 0;
    }
    if (lpNumberOfBytesRead) {
        *lpNumberOfBytesRead = (uint32_t)bytesRead;
    }
    return 1;
}

inline int ReadFileEx(void* hFile, void* lpBuffer, uint32_t nNumberOfBytesToRead,
                     void* lpOverlapped, void* lpCompletionRoutine) {
    // Simplified implementation - just call ReadFile
    return ReadFile(hFile, lpBuffer, nNumberOfBytesToRead, NULL, lpOverlapped);
}

inline uint32_t SetFilePointer(void* hFile, int32_t lDistanceToMove, int32_t* lpDistanceToMoveHigh, uint32_t dwMoveMethod) {
    if (!hFile || hFile == (void*)(intptr_t)INVALID_HANDLE_VALUE) {
        return INVALID_SET_FILE_POINTER;
    }
    int fd = (int)(intptr_t)hFile;
    off_t offset = (off_t)lDistanceToMove;
    if (lpDistanceToMoveHigh) {
        offset |= ((off_t)*lpDistanceToMoveHigh) << 32;
    }
    off_t result = lseek(fd, offset, dwMoveMethod);
    if (result == -1) {
        return INVALID_SET_FILE_POINTER;
    }
    return (uint32_t)(result & 0xFFFFFFFF);
}

// Disk space function
inline int GetDiskFreeSpace(const char* lpRootPathName, uint32_t* lpSectorsPerCluster, 
                           uint32_t* lpBytesPerSector, uint32_t* lpNumberOfFreeClusters, 
                           uint32_t* lpTotalNumberOfClusters) {
    // Simplified implementation - just return default values
    if (lpSectorsPerCluster) *lpSectorsPerCluster = 8;  // 8 sectors per cluster
    if (lpBytesPerSector) *lpBytesPerSector = 512;      // 512 bytes per sector
    if (lpNumberOfFreeClusters) *lpNumberOfFreeClusters = 1000000;  // dummy value
    if (lpTotalNumberOfClusters) *lpTotalNumberOfClusters = 2000000; // dummy value
    return 1;  // success
}

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

// Process and thread functions for CPUDetect.cpp
#include <pthread.h>
#include <sys/resource.h>
#include <unistd.h>
#include <sched.h>
#include <errno.h>

// CPU affinity types and constants
#ifndef CPU_SETSIZE
#define CPU_SETSIZE 1024
#endif

#ifndef cpu_set_t
typedef struct {
    unsigned long __bits[CPU_SETSIZE / (8 * sizeof(unsigned long))];
} cpu_set_t;
#endif

#ifndef CPU_ISSET
#define CPU_ISSET(cpu, cpusetp) \
    (((cpusetp)->__bits[(cpu) / (8 * sizeof(unsigned long))] & \
      (1UL << ((cpu) % (8 * sizeof(unsigned long))))) != 0)
#endif

// Windows priority class constants
#define NORMAL_PRIORITY_CLASS       0x20
#define HIGH_PRIORITY_CLASS         0x40
#define REALTIME_PRIORITY_CLASS     0x80
#define BELOW_NORMAL_PRIORITY_CLASS 0x10
#define IDLE_PRIORITY_CLASS         0x08

// Windows thread priority constants
#define THREAD_PRIORITY_TIME_CRITICAL 15
#define THREAD_PRIORITY_HIGHEST       2
#define THREAD_PRIORITY_ABOVE_NORMAL  1
#define THREAD_PRIORITY_NORMAL        0
#define THREAD_PRIORITY_BELOW_NORMAL  -1
#define THREAD_PRIORITY_LOWEST        -2
#define THREAD_PRIORITY_IDLE          -15

inline void* GetCurrentProcess() {
    // Return process ID as handle for macOS
    return (void*)(uintptr_t)getpid();
}

inline void* GetCurrentThread() {
    // Return current thread handle using pthread
    return (void*)pthread_self();
}

inline int GetThreadPriority(void* hThread) {
    // Get thread priority using pthread scheduling
    if (hThread == NULL) {
        hThread = pthread_self();
    }
    
    int policy;
    struct sched_param param;
    if (pthread_getschedparam((pthread_t)hThread, &policy, &param) == 0) {
        return param.sched_priority;
    }
    return 0;
}

inline int SetThreadPriority(void* hThread, int nPriority) {
    // Set thread priority using pthread scheduling
    if (hThread == NULL) {
        hThread = pthread_self();
    }
    
    struct sched_param param;
    param.sched_priority = nPriority;
    
    // Use SCHED_OTHER policy for normal threads
    return pthread_setschedparam((pthread_t)hThread, SCHED_OTHER, &param) == 0 ? 1 : 0;
}

inline uint32_t GetPriorityClass(void* hProcess) {
    // Get process priority class using getpriority
    int priority = getpriority(PRIO_PROCESS, 0);
    if (priority == -1 && errno != 0) {
        return 0x20; // NORMAL_PRIORITY_CLASS on error
    }
    
    // Map POSIX nice values to Windows priority classes
    if (priority <= -10) return 0x80; // REALTIME_PRIORITY_CLASS
    if (priority <= -5) return 0x40;  // HIGH_PRIORITY_CLASS
    if (priority <= 0) return 0x20;   // NORMAL_PRIORITY_CLASS
    if (priority <= 5) return 0x10;   // BELOW_NORMAL_PRIORITY_CLASS
    return 0x08; // IDLE_PRIORITY_CLASS
}

inline int SetPriorityClass(void* hProcess, int dwPriorityClass) {
    // Set process priority class using setpriority
    int nice_value;
    
    switch (dwPriorityClass) {
        case 0x80: // REALTIME_PRIORITY_CLASS
            nice_value = -10;
            break;
        case 0x40: // HIGH_PRIORITY_CLASS
            nice_value = -5;
            break;
        case 0x20: // NORMAL_PRIORITY_CLASS
            nice_value = 0;
            break;
        case 0x10: // BELOW_NORMAL_PRIORITY_CLASS
            nice_value = 5;
            break;
        case 0x08: // IDLE_PRIORITY_CLASS
            nice_value = 10;
            break;
        default:
            nice_value = 0;
            break;
    }
    
    return setpriority(PRIO_PROCESS, 0, nice_value) == 0 ? 1 : 0;
}

inline int GetProcessAffinityMask(void* hProcess, void* lpProcessAffinityMask, void* lpSystemAffinityMask) {
    // macOS doesn't have process affinity, but we can get the number of CPUs
    int numCPUs = sysconf(_SC_NPROCESSORS_ONLN);
    
    if (numCPUs > 0) {
        // Create a mask with all available CPUs
        DWORD mask = (1 << numCPUs) - 1;
        
        if (lpProcessAffinityMask) {
            *(DWORD*)lpProcessAffinityMask = mask;
        }
        if (lpSystemAffinityMask) {
            *(DWORD*)lpSystemAffinityMask = mask;
        }
        return 1;
    }
    
    // Fallback: assume single CPU
    if (lpProcessAffinityMask) {
        *(DWORD*)lpProcessAffinityMask = 0x1;
    }
    if (lpSystemAffinityMask) {
        *(DWORD*)lpSystemAffinityMask = 0x1;
    }
    return 1;
}

// Memory management functions are handled by _ACCESS_POOL macro in CryAISystem

#endif

#endif //_CRY_COMMON_MACOS_SPECIFIC_HDR_
