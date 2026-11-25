//====== Copyright Valve Corporation, All rights reserved. ====================
//
// Purpose: C ABI wrapper around GameNetworkingSockets, for managed code.
//
//=============================================================================

#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <vector>

#include "steam/steamnetworkingsockets.h"
#include "steam/isteamnetworkingutils.h"

static ISteamNetworkingSockets *s_networkSockets = nullptr;
static HSteamNetPollGroup s_pollGroup = 0;
static std::vector<uint32> eventData;

#ifdef _WIN32
#define GNS_VSPRINTF( buffer, fmt, args ) vsprintf_s( buffer, sizeof(buffer), fmt, args )
#define GNS_MEMCPY( dst, dstSize, src, srcSize ) memcpy_s( dst, dstSize, src, srcSize )
#else
#define GNS_VSPRINTF( buffer, fmt, args ) vsprintf( buffer, fmt, args )
#define GNS_MEMCPY( dst, dstSize, src, srcSize ) memcpy( dst, src, srcSize )
#endif

// eventData holds { event, connection handle } pairs.
// event 1 = connected, event 2 = disconnected.
static void FatalError( const char *fmt, ... )
{
    char buffer[2048];
    va_list args;
    va_start( args, fmt );

    GNS_VSPRINTF( buffer, fmt, args );
    va_end( args );

    // Trim a trailing newline
    size_t len = strlen( buffer );
    if ( len > 0 )
        if ( buffer[len-1] == '\n' )
            buffer[len-1] = '\0';
    printf( buffer );
    fflush( stdout );
    fflush( stderr );
}

extern "C" void GNS_Startup()
{
    SteamNetworkingErrMsg errMsg;
    if ( !GameNetworkingSockets_Init( nullptr, errMsg ) )
        FatalError( "GameNetworkingSockets_Init failed.  %s", errMsg );

    s_networkSockets = SteamNetworkingSockets();

    SteamNetworkingIdentity identity;
    identity.SetLocalHost();

    s_networkSockets->ResetIdentity( &identity );

    s_pollGroup = s_networkSockets->CreatePollGroup();
    if ( !s_pollGroup )
        FatalError( "Failed to create poll group" );
}

extern "C" void GNS_Shutdown()
{
    if ( s_pollGroup )
    {
        s_networkSockets->DestroyPollGroup( s_pollGroup );
        s_pollGroup = 0;
    }

    if ( s_networkSockets )
    {
        GameNetworkingSockets_Kill();
        s_networkSockets = nullptr;
    }
}

extern "C" uint32 GNS_Recieve( uint8 *transportBuffer, int &resultSize, int maxTransportSize )
{
    resultSize = 0;

    SteamNetworkingMessage_t *message = nullptr;
    if ( !s_networkSockets )
        return 0;

    int nMessages = s_networkSockets->ReceiveMessagesOnPollGroup( s_pollGroup, &message, 1 );

    if ( nMessages <= 0 )
        return 0;
    uint32 connection = message->m_conn;
    if ( connection )
    {
        // The Linux build relied on the caller having sized the buffer; the
        // Windows build used the secure CRT.  maxTransportSize is ignored on
        // Linux in the original binary.
        GNS_MEMCPY( transportBuffer, maxTransportSize, message->m_pData, message->m_cbSize );

        resultSize = message->m_cbSize;
    }

    message->Release();

    return connection;
}

extern "C" int GNS_ConnectionEvents( uint32 *eventBuffer, int maxEventSize )
{
    s_networkSockets->RunCallbacks();

    int count = 0;

    // maxEventSize is not checked in the original implementation.
    for ( uint32 event : eventData )
    {
        eventBuffer[count] = event;
        count++;
    }

    eventData.clear();

    return count / 2;
}

static void OnListenerConnectionStatusChanged( SteamNetConnectionStatusChangedCallback_t *pInfo )
{
    switch ( pInfo->m_info.m_eState )
    {
    case k_ESteamNetworkingConnectionState_ClosedByPeer:
    case k_ESteamNetworkingConnectionState_ProblemDetectedLocally:
        // Only report a disconnect if the caller was told about the connect.
        if ( pInfo->m_eOldState == k_ESteamNetworkingConnectionState_Connected )
        {
            eventData.push_back( 2 );
            eventData.push_back( pInfo->m_hConn );
        }
        else if ( pInfo->m_eOldState == k_ESteamNetworkingConnectionState_Connecting )
        {
            s_networkSockets->CloseConnection( pInfo->m_hConn, 0, nullptr, false );
        }
        break;

    case k_ESteamNetworkingConnectionState_Connecting:
        // Accept inbound connections and put them in our poll group.
        if ( s_networkSockets->AcceptConnection( pInfo->m_hConn ) != k_EResultOK )
        {
            s_networkSockets->CloseConnection( pInfo->m_hConn, 0, nullptr, false );
            break;
        }
        if ( !s_networkSockets->SetConnectionPollGroup( pInfo->m_hConn, s_pollGroup ) )
        {
            s_networkSockets->CloseConnection( pInfo->m_hConn, 0, nullptr, false );
        }
        break;

    case k_ESteamNetworkingConnectionState_Connected:
        eventData.push_back( 1 );
        eventData.push_back( pInfo->m_hConn );
        break;

    default:
        break;
    }
}

static void OnClientConnectionStatusChanged( SteamNetConnectionStatusChangedCallback_t *pInfo )
{
    switch ( pInfo->m_info.m_eState )
    {
    case k_ESteamNetworkingConnectionState_ClosedByPeer:
    case k_ESteamNetworkingConnectionState_ProblemDetectedLocally:
        eventData.push_back( 2 );
        eventData.push_back( pInfo->m_hConn );
        break;

    case k_ESteamNetworkingConnectionState_Connecting:
        // Make sure the connection is in the poll group used by Recieve.
        if ( !s_networkSockets->SetConnectionPollGroup( pInfo->m_hConn, s_pollGroup ) )
        {
            s_networkSockets->CloseConnection( pInfo->m_hConn, 0, nullptr, false );
            eventData.push_back( 2 );
            eventData.push_back( pInfo->m_hConn );
        }
        break;

    case k_ESteamNetworkingConnectionState_Connected:
        eventData.push_back( 1 );
        eventData.push_back( pInfo->m_hConn );
        break;

    default:
        break;
    }
}

extern "C" uint32 GNS_ListenIPPort( const char *addrString )
{
    SteamNetworkingIPAddr addr;
    addr.ParseString( addrString );

    SteamNetworkingConfigValue_t opt;
    opt.SetPtr( k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged, (void*)OnListenerConnectionStatusChanged );
    return s_networkSockets->CreateListenSocketIP( addr, 1, &opt );
}

extern "C" uint32 GNS_Listen( int port )
{
    SteamNetworkingIPAddr addr;
    addr.Clear();
    addr.m_port = (uint16)port;

    SteamNetworkingConfigValue_t opt;
    opt.SetPtr( k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged, (void*)OnListenerConnectionStatusChanged );
    return s_networkSockets->CreateListenSocketIP( addr, 1, &opt );
}

extern "C" void GNS_CloseListen( uint32 socket )
{
    s_networkSockets->CloseListenSocket( socket );
}

extern "C" uint32 GNS_ConnectString( const char *addrString )
{
    SteamNetworkingIPAddr addr;
    addr.ParseString( addrString );

    SteamNetworkingConfigValue_t opt;
    opt.SetPtr( k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged, (void*)OnClientConnectionStatusChanged );
    return s_networkSockets->ConnectByIPAddress( addr, 1, &opt );
}

extern "C" uint32 GNS_Connect( const SteamNetworkingIPAddr &addr )
{
    SteamNetworkingConfigValue_t opt;
    opt.SetPtr( k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged, (void*)OnClientConnectionStatusChanged );
    return s_networkSockets->ConnectByIPAddress( addr, 1, &opt );
}

extern "C" bool GNS_GetSocketAddress( uint32 socket, char *addressBuffer, int addressBufferSize )
{
    SteamNetConnectionInfo_t info;
    bool result = s_networkSockets->GetConnectionInfo( socket, &info );

    if ( result )
    {
        info.m_addrRemote.ToString( addressBuffer, addressBufferSize, true );
    }

    return result;
}

extern "C" void GNS_CloseSocket( uint32 socket )
{
    s_networkSockets->CloseConnection( socket, 0, "Closed", true );
}

extern "C" void GNS_SocketSend( uint32 socket, const void *sendBuffer, int sendAmount )
{
    s_networkSockets->SendMessageToConnection( socket, sendBuffer, sendAmount, k_nSteamNetworkingSend_Reliable, nullptr );
}
