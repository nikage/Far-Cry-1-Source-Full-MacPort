////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSFileSystem.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS-specific file system operations and path handling
//               Adapts Windows file system conventions to macOS
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef MACOS_FILESYSTEM_H
#define MACOS_FILESYSTEM_H

#if defined(__APPLE__) && defined(__MACH__)

#include <string>
#include <vector>
#include <Foundation/Foundation.h>
#include <sys/stat.h>
#include <dirent.h>

class CMacOSFileSystem
{
public:
    // Path conversion utilities
    static std::string ConvertPathSeparators(const std::string& path);
    static std::string GetAbsolutePath(const std::string& relativePath);
    static std::string GetGameDataPath();
    static std::string GetUserDataPath();
    static std::string GetApplicationPath();
    static std::string GetApplicationResourcesPath();
    
    // File operations
    static bool FileExists(const std::string& path);
    static bool DirectoryExists(const std::string& path);
    static bool CreateDirectoryRecursive(const std::string& path);
    static bool DeleteFile(const std::string& path);
    static bool CopyFile(const std::string& source, const std::string& destination);
    static bool MoveFile(const std::string& source, const std::string& destination);
    
    // File information
    static size_t GetFileSize(const std::string& path);
    static time_t GetFileModificationTime(const std::string& path);
    static bool IsFileReadOnly(const std::string& path);
    static bool SetFileReadOnly(const std::string& path, bool readOnly);
    
    // Directory operations
    static std::vector<std::string> GetDirectoryContents(const std::string& path);
    static std::vector<std::string> FindFiles(const std::string& directory, const std::string& pattern);
    static bool FindFirstFile(const std::string& pattern, std::string& foundFile);
    
    // macOS-specific utilities
    static std::string GetBundlePath();
    static std::string GetBundleResourcesPath();
    static std::string GetDocumentsPath();
    static std::string GetApplicationSupportPath();
    static std::string GetCachePath();
    static std::string GetTemporaryPath();
    
    // Path utilities
    static std::string GetParentPath(const std::string& path);
    static std::string GetFileName(const std::string& path);
    static std::string GetFileExtension(const std::string& path);
    static std::string RemoveExtension(const std::string& path);
    static std::string JoinPaths(const std::string& path1, const std::string& path2);
    
    // Case-insensitive file operations (for Windows compatibility)
    static std::string FindFileIgnoreCase(const std::string& directory, const std::string& filename);
    static bool FileExistsIgnoreCase(const std::string& path);
    
private:
    static std::string NormalizePath(const std::string& path);
    static NSString* GetNSString(const std::string& str);
    static std::string GetStdString(NSString* nsStr);
};

// macOS-specific file handle wrapper
class CMacOSFileHandle
{
public:
    CMacOSFileHandle();
    ~CMacOSFileHandle();
    
    bool Open(const std::string& path, const std::string& mode);
    void Close();
    
    size_t Read(void* buffer, size_t size, size_t count);
    size_t Write(const void* buffer, size_t size, size_t count);
    
    bool Seek(long offset, int origin);
    long Tell();
    bool Flush();
    bool IsEOF();
    
    FILE* GetHandle() { return m_file; }
    bool IsOpen() const { return m_file != nullptr; }
    
private:
    FILE* m_file;
    std::string m_path;
    std::string m_mode;
};

// Utility macros for cross-platform compatibility
#define MACOS_PATH_SEPARATOR "/"
#define MACOS_MAX_PATH 1024

// Convert Windows-style paths to macOS
inline std::string MacOSPathFromWindows(const std::string& windowsPath)
{
    std::string result = windowsPath;
    
    // Replace backslashes with forward slashes
    for (char& c : result)
    {
        if (c == '\\')
            c = '/';
    }
    
    return result;
}

// Helper for case-insensitive path operations
class CMacOSCaseInsensitivePath
{
public:
    static std::string Resolve(const std::string& path);
    static bool Compare(const std::string& path1, const std::string& path2);
    
private:
    static std::string ToLower(const std::string& str);
};

#endif // __APPLE__ && __MACH__

#endif // MACOS_FILESYSTEM_H
