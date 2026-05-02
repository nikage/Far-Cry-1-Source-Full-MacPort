//////////////////////////////////////////////////////////////////////////////
// CrySystem/NullNetwork.h
// Minimal no-op INetwork/IServer/IClient stub for macOS singleplayer.
//
// Singleplayer does not need real networking.  listen=false already skips
// all socket binding in CServer::Init.  This stub satisfies the game's
// object graph (CXServer / CXClient) without opening any sockets.
//////////////////////////////////////////////////////////////////////////////
#pragma once

#if defined(__APPLE__) && defined(__MACH__)

#include <INetwork.h>
#include <IPAddress.h>
#include <IBitStream.h>

//////////////////////////////////////////////////////////////////////////////
// CNullServer
//////////////////////////////////////////////////////////////////////////////
class CNullServer : public IServer
{
public:
    void Update(unsigned int) override {}
    void Release() override { delete this; }
    void SetVariable(CryNetworkVarible, unsigned int) override {}
    void GetBandwidth(float &fIn, float &fOut, DWORD &nIn, DWORD &nOut) override
    {
        fIn = fOut = 0.0f; nIn = nOut = 0;
    }
    const char *GetHostName() override { return "localhost"; }
    void RegisterPacketSink(const unsigned char, INetworkPacketSink *) override {}
    void SetSecuritySink(IServerSecuritySink *) override {}
    bool IsIPBanned(const unsigned int) override { return false; }
    void BanIP(const unsigned int) override {}
    void UnbanIP(const unsigned int) override {}
    IServerSlot *GetServerSlotbyID(const unsigned char) const override { return nullptr; }
    uint8 GetMaxClientID() const override { return 0; }
    EMPServerType GetServerType() const override { return eMPST_LAN; }
};

//////////////////////////////////////////////////////////////////////////////
// CNullClient
//////////////////////////////////////////////////////////////////////////////
class CNullClient : public IClient
{
public:
    void Connect(const char *, WORD, const BYTE *, unsigned int) override {}
    void Disconnect(const char *) override {}
    void SendReliable(CStream &) override {}
    void SendUnreliable(CStream &) override {}
    void ContextReady(CStream &) override {}
    bool IsReady() override { return true; }
    bool Update(unsigned int) override { return true; }
    void GetBandwidth(float &fIn, float &fOut, DWORD &nIn, DWORD &nOut) override
    {
        fIn = fOut = 0.0f; nIn = nOut = 0;
    }
    void Release() override { delete this; }
    unsigned int GetPing() override { return 0; }
    unsigned int GetRemoteTimestamp(unsigned int nTime) override { return nTime; }
    unsigned int GetPacketsLostCount() override { return 0; }
    unsigned int GetUnreliablePacketsLostCount() override { return 0; }
    CIPAddress GetServerIP() const override { return CIPAddress(); }
    void InitiateCDKeyAuthorization(const bool) override {}
    void OnCDKeyAuthorization(BYTE *) override {}
    void SetServerIP(const char *) override {}
};

//////////////////////////////////////////////////////////////////////////////
// CNullNetwork
//////////////////////////////////////////////////////////////////////////////
class CNullNetwork : public INetwork
{
public:
    explicit CNullNetwork(ISystem *) {}

    DWORD GetLocalIP() const override { return 0; }
    void SetLocalIP(const char *) override {}

    IClient *CreateClient(IClientSink *, bool) override
    {
        return new CNullClient();
    }

    IServer *CreateServer(IServerSlotFactory *, WORD, bool) override
    {
        return new CNullServer();
    }

    IRConSystem *CreateRConSystem() override { return nullptr; }
    INETServerSnooper *CreateNETServerSnooper(INETServerSnooperSink *) override { return nullptr; }
    IServerSnooper *CreateServerSnooper(IServerSnooperSink *) override { return nullptr; }
    const char *EnumerateError(NRESULT) override { return ""; }
    void Release() override { delete this; }
    void GetMemoryStatistics(ICrySizer *) override {}
    ICompressionHelper *GetCompressionHelper() override { return nullptr; }
    void ClearProtectedFiles() override {}
    void AddProtectedFile(const char *) override {}
    IServer *GetServerByPort(const WORD) override { return nullptr; }
    void UpdateNetwork() override {}
    void OnAfterServerLoadLevel(const char *, const uint32, const WORD) override {}
    bool VerifyMultiplayerOverInternet() override { return false; }
    void Client_ReJoinGameServer() override {}
    IClient *GetClient() override { return nullptr; }
};

#endif // __APPLE__
