////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSFileSystem.cpp
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS file system implementation
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#define MACOS_FILESYSTEM_IMPLEMENTATION
#include "MacOSFileSystem.h"
#include <sys/stat.h>
#include <unistd.h>
#include <fnmatch.h>
#include <algorithm>
// CoreFoundation not needed - removed to avoid header conflicts

// Static utility methods
std::string CMacOSFileSystem::ConvertPathSeparators(const std::string& path)
{
    std::string result = path;
    std::replace(result.begin(), result.end(), '\\', '/');
    return result;
}

std::string CMacOSFileSystem::GetAbsolutePath(const std::string& relativePath)
{
    char* absolutePath = realpath(relativePath.c_str(), nullptr);
    if (absolutePath)
    {
        std::string result(absolutePath);
        free(absolutePath);
        return result;
    }
    return relativePath;
}

std::string CMacOSFileSystem::GetGameDataPath()
{
    // Return the application bundle's Resources directory
    return GetBundleResourcesPath();
}

std::string CMacOSFileSystem::GetUserDataPath()
{
    return GetApplicationSupportPath() + "/FarCry";
}

std::string CMacOSFileSystem::GetApplicationPath()
{
    return GetBundlePath();
}

std::string CMacOSFileSystem::GetApplicationResourcesPath()
{
    return GetBundleResourcesPath();
}

bool CMacOSFileSystem::FileExists(const std::string& path)
{
    struct stat st;
    return (stat(path.c_str(), &st) == 0) && S_ISREG(st.st_mode);
}

bool CMacOSFileSystem::DirectoryExists(const std::string& path)
{
    struct stat st;
    return (stat(path.c_str(), &st) == 0) && S_ISDIR(st.st_mode);
}

bool CMacOSFileSystem::CreateDirectoryRecursive(const std::string& path)
{
    if (DirectoryExists(path))
        return true;
    
    // Create parent directories first
    std::string parentPath = GetParentPath(path);
    if (!parentPath.empty() && parentPath != path)
    {
        if (!CreateDirectoryRecursive(parentPath))
            return false;
    }
    
    return mkdir(path.c_str(), 0755) == 0;
}

bool CMacOSFileSystem::DeleteFile(const std::string& path)
{
    return unlink(path.c_str()) == 0;
}

bool CMacOSFileSystem::CopyFile(const std::string& source, const std::string& destination)
{
    FILE* src = fopen(source.c_str(), "rb");
    if (!src)
        return false;
    
    FILE* dst = fopen(destination.c_str(), "wb");
    if (!dst)
    {
        fclose(src);
        return false;
    }
    
    char buffer[8192];
    size_t bytesRead;
    bool success = true;
    
    while ((bytesRead = fread(buffer, 1, sizeof(buffer), src)) > 0)
    {
        if (fwrite(buffer, 1, bytesRead, dst) != bytesRead)
        {
            success = false;
            break;
        }
    }
    
    fclose(src);
    fclose(dst);
    
    return success;
}

bool CMacOSFileSystem::MoveFile(const std::string& source, const std::string& destination)
{
    return rename(source.c_str(), destination.c_str()) == 0;
}

size_t CMacOSFileSystem::GetFileSize(const std::string& path)
{
    struct stat st;
    if (stat(path.c_str(), &st) == 0)
        return st.st_size;
    return 0;
}

time_t CMacOSFileSystem::GetFileModificationTime(const std::string& path)
{
    struct stat st;
    if (stat(path.c_str(), &st) == 0)
        return st.st_mtime;
    return 0;
}

bool CMacOSFileSystem::IsFileReadOnly(const std::string& path)
{
    return access(path.c_str(), W_OK) != 0;
}

bool CMacOSFileSystem::SetFileReadOnly(const std::string& path, bool readOnly)
{
    struct stat st;
    if (stat(path.c_str(), &st) != 0)
        return false;
    
    mode_t mode = st.st_mode;
    if (readOnly)
        mode &= ~(S_IWUSR | S_IWGRP | S_IWOTH);
    else
        mode |= S_IWUSR;
    
    return chmod(path.c_str(), mode) == 0;
}

std::vector<std::string> CMacOSFileSystem::GetDirectoryContents(const std::string& path)
{
    std::vector<std::string> contents;
    
    DIR* dir = opendir(path.c_str());
    if (!dir)
        return contents;
    
    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr)
    {
        if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0)
        {
            contents.push_back(entry->d_name);
        }
    }
    
    closedir(dir);
    return contents;
}

std::vector<std::string> CMacOSFileSystem::FindFiles(const std::string& directory, const std::string& pattern)
{
    std::vector<std::string> files;
    std::vector<std::string> contents = GetDirectoryContents(directory);
    
    for (const std::string& file : contents)
    {
        if (fnmatch(pattern.c_str(), file.c_str(), 0) == 0)
        {
            files.push_back(JoinPaths(directory, file));
        }
    }
    
    return files;
}

bool CMacOSFileSystem::FindFirstFile(const std::string& pattern, std::string& foundFile)
{
    std::string directory = GetParentPath(pattern);
    std::string filename = GetFileName(pattern);
    
    std::vector<std::string> files = FindFiles(directory, filename);
    if (!files.empty())
    {
        foundFile = files[0];
        return true;
    }
    
    return false;
}

// macOS-specific paths using Foundation framework
std::string CMacOSFileSystem::GetBundlePath()
{
    NSBundle* mainBundle = [NSBundle mainBundle];
    NSString* bundlePath = [mainBundle bundlePath];
    return GetStdString(bundlePath);
}

std::string CMacOSFileSystem::GetBundleResourcesPath()
{
    NSBundle* mainBundle = [NSBundle mainBundle];
    NSString* resourcesPath = [mainBundle resourcePath];
    return GetStdString(resourcesPath);
}

std::string CMacOSFileSystem::GetDocumentsPath()
{
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsPath = [paths objectAtIndex:0];
    return GetStdString(documentsPath);
}

std::string CMacOSFileSystem::GetApplicationSupportPath()
{
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString* appSupportPath = [paths objectAtIndex:0];
    return GetStdString(appSupportPath);
}

std::string CMacOSFileSystem::GetCachePath()
{
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString* cachePath = [paths objectAtIndex:0];
    return GetStdString(cachePath);
}

std::string CMacOSFileSystem::GetTemporaryPath()
{
    NSString* tempPath = NSTemporaryDirectory();
    return GetStdString(tempPath);
}

// Path utilities
std::string CMacOSFileSystem::GetParentPath(const std::string& path)
{
    size_t lastSlash = path.find_last_of('/');
    if (lastSlash != std::string::npos)
        return path.substr(0, lastSlash);
    return "";
}

std::string CMacOSFileSystem::GetFileName(const std::string& path)
{
    size_t lastSlash = path.find_last_of('/');
    if (lastSlash != std::string::npos)
        return path.substr(lastSlash + 1);
    return path;
}

std::string CMacOSFileSystem::GetFileExtension(const std::string& path)
{
    std::string filename = GetFileName(path);
    size_t lastDot = filename.find_last_of('.');
    if (lastDot != std::string::npos)
        return filename.substr(lastDot);
    return "";
}

std::string CMacOSFileSystem::RemoveExtension(const std::string& path)
{
    size_t lastDot = path.find_last_of('.');
    if (lastDot != std::string::npos)
        return path.substr(0, lastDot);
    return path;
}

std::string CMacOSFileSystem::JoinPaths(const std::string& path1, const std::string& path2)
{
    if (path1.empty())
        return path2;
    if (path2.empty())
        return path1;
    
    std::string result = path1;
    if (result.back() != '/')
        result += '/';
    result += path2;
    
    return result;
}

// Case-insensitive operations for Windows compatibility
std::string CMacOSFileSystem::FindFileIgnoreCase(const std::string& directory, const std::string& filename)
{
    std::vector<std::string> contents = GetDirectoryContents(directory);
    std::string lowerFilename = CMacOSCaseInsensitivePath::ToLower(filename);
    
    for (const std::string& file : contents)
    {
        if (CMacOSCaseInsensitivePath::ToLower(file) == lowerFilename)
        {
            return JoinPaths(directory, file);
        }
    }
    
    return "";
}

bool CMacOSFileSystem::FileExistsIgnoreCase(const std::string& path)
{
    std::string directory = GetParentPath(path);
    std::string filename = GetFileName(path);
    
    return !FindFileIgnoreCase(directory, filename).empty();
}

// Helper methods
std::string CMacOSFileSystem::NormalizePath(const std::string& path)
{
    return ConvertPathSeparators(path);
}

NSString* CMacOSFileSystem::GetNSString(const std::string& str)
{
    return [NSString stringWithUTF8String:str.c_str()];
}

std::string CMacOSFileSystem::GetStdString(NSString* nsStr)
{
    if (!nsStr)
        return "";
    
    const char* utf8String = [nsStr UTF8String];
    return utf8String ? std::string(utf8String) : "";
}

// CMacOSFileHandle implementation
CMacOSFileHandle::CMacOSFileHandle() : m_file(nullptr)
{
}

CMacOSFileHandle::~CMacOSFileHandle()
{
    Close();
}

bool CMacOSFileHandle::Open(const std::string& path, const std::string& mode)
{
    Close();
    
    m_path = path;
    m_mode = mode;
    m_file = fopen(path.c_str(), mode.c_str());
    
    return m_file != nullptr;
}

void CMacOSFileHandle::Close()
{
    if (m_file)
    {
        fclose(m_file);
        m_file = nullptr;
    }
}

size_t CMacOSFileHandle::Read(void* buffer, size_t size, size_t count)
{
    if (!m_file)
        return 0;
    
    return fread(buffer, size, count, m_file);
}

size_t CMacOSFileHandle::Write(const void* buffer, size_t size, size_t count)
{
    if (!m_file)
        return 0;
    
    return fwrite(buffer, size, count, m_file);
}

bool CMacOSFileHandle::Seek(long offset, int origin)
{
    if (!m_file)
        return false;
    
    return fseek(m_file, offset, origin) == 0;
}

long CMacOSFileHandle::Tell()
{
    if (!m_file)
        return -1;
    
    return ftell(m_file);
}

bool CMacOSFileHandle::Flush()
{
    if (!m_file)
        return false;
    
    return fflush(m_file) == 0;
}

bool CMacOSFileHandle::IsEOF()
{
    if (!m_file)
        return true;
    
    return feof(m_file) != 0;
}

// CMacOSCaseInsensitivePath implementation
std::string CMacOSCaseInsensitivePath::Resolve(const std::string& path)
{
    // For now, just return the original path
    // A full implementation would resolve each path component case-insensitively
    return path;
}

bool CMacOSCaseInsensitivePath::Compare(const std::string& path1, const std::string& path2)
{
    return ToLower(path1) == ToLower(path2);
}

std::string CMacOSCaseInsensitivePath::ToLower(const std::string& str)
{
    std::string result = str;
    std::transform(result.begin(), result.end(), result.begin(), ::tolower);
    return result;
}

#endif // __APPLE__ && __MACH__
