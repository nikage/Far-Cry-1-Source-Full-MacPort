// macOS compatibility stubs for missing functions
#include "stdafx.h"

// Forward declarations
namespace XDOM {
    class IXMLDOMDocument;
}

// Note: CreateGameInstance() is properly implemented in CryGame/Game.cpp
// DO NOT add a stub here as it would override the real implementation

// XML DOM creation stub  
XDOM::IXMLDOMDocument* CreateDOMDocument() {
    // Return nullptr for macOS - XML system will need to be properly implemented later
    return nullptr;
}

// CHTTPDownloader template static members
#include "HTTPDownloader.h"
_DECLARE_SCRIPTABLEEX(CHTTPDownloader)
