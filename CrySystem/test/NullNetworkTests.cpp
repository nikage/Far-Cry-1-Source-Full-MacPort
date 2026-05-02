// Standalone regression test for CNullNetwork / CNullServer / CNullClient.
//
// Build (from CrySystem/test/):
//   clang++ -std=c++17 -I../.. -I../../CryCommon \
//     -o null_network_tests NullNetworkTests.cpp && ./null_network_tests

#include <cassert>
#include <cstdio>

#include "INetwork.h"
#include "../NullNetwork.h"

// Stub required by CryError (pulled in through platform headers)
struct ISystem;
ISystem* GetISystem() { return nullptr; }

// ---------------------------------------------------------------------------
// Minimal test harness
// ---------------------------------------------------------------------------
static int g_total  = 0;
static int g_failed = 0;

#define CHECK(expr) do { \
    ++g_total; \
    if (!(expr)) { \
        ++g_failed; \
        fprintf(stderr, "FAIL  line %d: %s\n", __LINE__, #expr); \
    } \
} while(0)

// ---------------------------------------------------------------------------

static void test_null_server()
{
    CNullNetwork net(nullptr);
    IServer *srv = net.CreateServer(nullptr, 0, false);

    CHECK(srv != nullptr);
    CHECK(srv->GetServerType() == eMPST_LAN);
    CHECK(srv->GetMaxClientID() == 0);
    CHECK(srv->GetHostName() != nullptr);
    CHECK(srv->IsIPBanned(0) == false);

    float fIn = 1.0f, fOut = 1.0f;
    DWORD nIn = 1, nOut = 1;
    srv->GetBandwidth(fIn, fOut, nIn, nOut);
    CHECK(fIn == 0.0f);
    CHECK(fOut == 0.0f);
    CHECK(nIn == 0);
    CHECK(nOut == 0);

    srv->Update(12345);
    srv->SetVariable(cnvDataStreamTimeout, 99);
    srv->SetSecuritySink(nullptr);
    srv->BanIP(0x7f000001);
    srv->UnbanIP(0x7f000001);
    srv->RegisterPacketSink(0, nullptr);

    CHECK(srv->GetServerSlotbyID(0) == nullptr);

    srv->Release();
}

static void test_null_client()
{
    CNullNetwork net(nullptr);
    IClient *cli = net.CreateClient(nullptr, true);

    CHECK(cli != nullptr);
    CHECK(cli->IsReady() == true);
    CHECK(cli->Update(0) == true);
    CHECK(cli->GetPing() == 0);
    CHECK(cli->GetPacketsLostCount() == 0);
    CHECK(cli->GetUnreliablePacketsLostCount() == 0);
    CHECK(cli->GetRemoteTimestamp(42) == 42);

    float fIn = 1.0f, fOut = 1.0f;
    DWORD nIn = 1, nOut = 1;
    cli->GetBandwidth(fIn, fOut, nIn, nOut);
    CHECK(fIn == 0.0f);
    CHECK(fOut == 0.0f);
    CHECK(nIn == 0);
    CHECK(nOut == 0);

    CStream stm;
    cli->SendReliable(stm);
    cli->SendUnreliable(stm);
    cli->ContextReady(stm);
    cli->Disconnect("test");

    cli->Release();
}

static void test_null_network()
{
    CNullNetwork *net = new CNullNetwork(nullptr);

    CHECK(net->GetLocalIP() == 0);
    CHECK(net->GetCompressionHelper() != nullptr);
    CHECK(net->GetClient() == nullptr);
    CHECK(net->GetServerByPort(0) == nullptr);
    CHECK(net->VerifyMultiplayerOverInternet() == false);
    CHECK(net->EnumerateError(0) != nullptr);

    net->UpdateNetwork();
    net->ClearProtectedFiles();
    net->AddProtectedFile("test.pak");
    net->OnAfterServerLoadLevel("map", 1, 27015);
    net->Client_ReJoinGameServer();

    net->Release();
}

static void test_null_compression_helper()
{
    CNullCompressionHelper helper;
    CStream stm;

    // round-trip: unsigned char
    const unsigned char kByte = 0xAB;
    CHECK(helper.Write(stm, kByte));
    stm.Seek(0);
    unsigned char readByte = 0;
    CHECK(helper.Read(stm, readByte));
    CHECK(readByte == kByte);

    // round-trip: string
    stm.Reset();
    const char* kStr = "TeamAlpha";
    CHECK(helper.Write(stm, kStr));
    stm.Seek(0);
    char outBuf[64] = {};
    CHECK(helper.Read(stm, outBuf, sizeof(outBuf)));
    CHECK(strcmp(outBuf, kStr) == 0);

    // round-trip: empty string
    stm.Reset();
    CHECK(helper.Write(stm, ""));
    stm.Seek(0);
    char emptyBuf[8] = { 'x', 'x', 'x', 0 };
    CHECK(helper.Read(stm, emptyBuf, sizeof(emptyBuf)));
    CHECK(emptyBuf[0] == '\0');

    // truncation: buffer smaller than the written string
    stm.Reset();
    CHECK(helper.Write(stm, "LongTeamName"));
    stm.Seek(0);
    char smallBuf[5] = {};
    CHECK(helper.Read(stm, smallBuf, sizeof(smallBuf)));
    CHECK(smallBuf[4] == '\0');

    // nullptr treated as empty string
    stm.Reset();
    CHECK(helper.Write(stm, nullptr));
    stm.Seek(0);
    char nullBuf[8] = { 'z' };
    CHECK(helper.Read(stm, nullBuf, sizeof(nullBuf)));
    CHECK(nullBuf[0] == '\0');
}

// ---------------------------------------------------------------------------
int main()
{
    test_null_server();
    test_null_client();
    test_null_network();
    test_null_compression_helper();

    if (g_failed == 0)
        printf("PASSED  %d/%d checks\n", g_total, g_total);
    else
        printf("FAILED  %d/%d checks\n", g_failed, g_total);

    return g_failed == 0 ? 0 : 1;
}
