////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSNetwork.h
//  Version:     v1.00
//  Created:     29/09/2025 by Mac Silicon Port Team.
//  Compilers:   Clang/LLVM for macOS
//  Description: macOS BSD sockets networking implementation
//               Replaces WinSock with POSIX sockets for cross-platform networking
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#ifndef MACOS_NETWORK_H
#define MACOS_NETWORK_H

#if defined(__APPLE__) && defined(__MACH__)

#include "INetwork.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <poll.h>
#include <map>
#include <vector>

// Socket type definitions for compatibility
typedef int SOCKET;
#define INVALID_SOCKET (-1)
#define SOCKET_ERROR (-1)

// Error code mappings from WinSock to BSD sockets
#define WSAEWOULDBLOCK      EWOULDBLOCK
#define WSAECONNRESET       ECONNRESET
#define WSAECONNABORTED     ECONNABORTED
#define WSAECONNREFUSED     ECONNREFUSED
#define WSAENETDOWN         ENETDOWN
#define WSAENETUNREACH      ENETUNREACH
#define WSAEHOSTDOWN        EHOSTDOWN
#define WSAEHOSTUNREACH     EHOSTUNREACH
#define WSAENOTCONN         ENOTCONN
#define WSAEISCONN          EISCONN
#define WSAEINPROGRESS      EINPROGRESS
#define WSAEALREADY         EALREADY

// macOS-specific socket wrapper
class CMacOSSocket
{
public:
    CMacOSSocket();
    ~CMacOSSocket();
    
    // Socket creation and management
    bool Create(int family = AF_INET, int type = SOCK_STREAM, int protocol = 0);
    bool Close();
    bool Bind(const sockaddr* addr, int addrlen);
    bool Listen(int backlog = SOMAXCONN);
    bool Connect(const sockaddr* addr, int addrlen);
    CMacOSSocket* Accept(sockaddr* addr = nullptr, int* addrlen = nullptr);
    
    // Data transmission
    int Send(const void* data, int len, int flags = 0);
    int Receive(void* buffer, int len, int flags = 0);
    int SendTo(const void* data, int len, const sockaddr* to, int tolen, int flags = 0);
    int ReceiveFrom(void* buffer, int len, sockaddr* from, int* fromlen, int flags = 0);
    
    // Socket options
    bool SetOption(int level, int optname, const void* optval, int optlen);
    bool GetOption(int level, int optname, void* optval, int* optlen);
    bool SetNonBlocking(bool nonBlocking);
    bool SetReuseAddress(bool reuse);
    bool SetKeepAlive(bool keepAlive);
    bool SetNoDelay(bool noDelay);
    
    // Socket state
    bool IsValid() const { return m_socket != INVALID_SOCKET; }
    bool IsConnected() const { return m_connected; }
    SOCKET GetHandle() const { return m_socket; }
    int GetLastError() const { return errno; }
    
    // Address utilities
    bool GetLocalAddress(sockaddr_in& addr);
    bool GetRemoteAddress(sockaddr_in& addr);
    
protected:
    SOCKET m_socket;
    bool m_connected;
    bool m_nonBlocking;
    
private:
    CMacOSSocket(SOCKET socket); // For accepted connections
};

// Network address utilities
class CMacOSNetworkAddress
{
public:
    CMacOSNetworkAddress();
    CMacOSNetworkAddress(const std::string& address, uint16_t port);
    CMacOSNetworkAddress(uint32_t address, uint16_t port);
    CMacOSNetworkAddress(const sockaddr_in& addr);
    
    // Address manipulation
    void SetAddress(const std::string& address);
    void SetAddress(uint32_t address);
    void SetPort(uint16_t port);
    
    // Address queries
    std::string GetAddressString() const;
    uint32_t GetAddress() const;
    uint16_t GetPort() const;
    sockaddr_in GetSockAddr() const;
    
    // DNS resolution
    bool Resolve(const std::string& hostname);
    static std::vector<CMacOSNetworkAddress> ResolveAll(const std::string& hostname, uint16_t port);
    
    // Utility functions
    bool IsValid() const;
    bool IsLocalhost() const;
    bool IsPrivate() const;
    
private:
    sockaddr_in m_addr;
};

// Network polling and event management
class CMacOSNetworkPoller
{
public:
    CMacOSNetworkPoller();
    ~CMacOSNetworkPoller();
    
    // Socket registration
    bool AddSocket(SOCKET socket, int events);
    bool RemoveSocket(SOCKET socket);
    bool ModifySocket(SOCKET socket, int events);
    
    // Polling operations
    int Poll(int timeout_ms);
    bool HasEvents(SOCKET socket, int events);
    
    // Event types
    enum Events
    {
        READ = POLLIN,
        WRITE = POLLOUT,
        ERROR = POLLERR,
        HANGUP = POLLHUP
    };
    
private:
    std::vector<pollfd> m_pollFds;
    std::map<SOCKET, size_t> m_socketMap;
};

// Network utilities
class CMacOSNetworkUtils
{
public:
    // Network initialization/cleanup
    static bool Initialize();
    static void Shutdown();
    
    // Error handling
    static std::string GetErrorString(int error);
    static int GetLastError();
    
    // Hostname and network info
    static std::string GetHostName();
    static std::string GetLocalIPAddress();
    static std::vector<std::string> GetAllLocalIPAddresses();
    
    // Network interface information
    static bool IsNetworkAvailable();
    static uint32_t GetSubnetMask(const std::string& interface);
    static std::string GetDefaultGateway();
    
    // Utility functions
    static uint32_t StringToAddress(const std::string& address);
    static std::string AddressToString(uint32_t address);
    static uint16_t HostToNetworkShort(uint16_t hostshort);
    static uint32_t HostToNetworkLong(uint32_t hostlong);
    static uint16_t NetworkToHostShort(uint16_t netshort);
    static uint32_t NetworkToHostLong(uint32_t netlong);
    
    // DNS utilities
    static bool IsValidIPAddress(const std::string& address);
    static bool IsValidHostname(const std::string& hostname);
    
private:
    static bool s_initialized;
};

// High-level network client
class CMacOSNetworkClient
{
public:
    CMacOSNetworkClient();
    ~CMacOSNetworkClient();
    
    // Connection management
    bool Connect(const std::string& host, uint16_t port, int timeout_ms = 5000);
    bool ConnectAsync(const std::string& host, uint16_t port);
    bool IsConnecting() const;
    bool IsConnected() const;
    void Disconnect();
    
    // Data transmission
    int Send(const void* data, size_t size);
    int Receive(void* buffer, size_t size);
    bool SendAll(const void* data, size_t size);
    
    // Non-blocking operations
    bool CanSend() const;
    bool CanReceive() const;
    bool HasError() const;
    
    // Configuration
    void SetTimeout(int timeout_ms);
    void SetKeepAlive(bool enable);
    void SetNoDelay(bool enable);
    
private:
    CMacOSSocket m_socket;
    CMacOSNetworkAddress m_remoteAddress;
    int m_timeout;
    bool m_connecting;
};

// High-level network server
class CMacOSNetworkServer
{
public:
    CMacOSNetworkServer();
    ~CMacOSNetworkServer();
    
    // Server management
    bool Start(uint16_t port, const std::string& bindAddress = "");
    void Stop();
    bool IsRunning() const;
    
    // Connection handling
    CMacOSSocket* AcceptConnection();
    void CloseConnection(CMacOSSocket* client);
    
    // Configuration
    void SetBacklog(int backlog);
    void SetReuseAddress(bool reuse);
    
private:
    CMacOSSocket m_listenSocket;
    bool m_running;
    int m_backlog;
};

#endif // __APPLE__ && __MACH__

#endif // MACOS_NETWORK_H
