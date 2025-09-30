// macOS compatibility stubs for missing functions
#include "stdafx.h"

// Forward declarations
class IGame;
namespace XDOM {
    class IXMLDOMDocument;
}

// Game instance creation stub
extern "C" IGame* CreateGameInstance() {
    // Return nullptr for macOS - game will need to be properly implemented later
    return nullptr;
}

// XML DOM creation stub  
XDOM::IXMLDOMDocument* CreateDOMDocument() {
    // Return nullptr for macOS - XML system will need to be properly implemented later
    return nullptr;
}

// CHTTPDownloader template static members
#include "HTTPDownloader.h"
_DECLARE_SCRIPTABLEEX(CHTTPDownloader)
