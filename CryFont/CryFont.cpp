//////////////////////////////////////////////////////////////////////
//
//  CryFont Source Code
//
//  File: CryFont.cpp
//  Description: CCryFont class.
//
//  History:
//  - August 18, 2001: Created by Alberto Demichelis
//  - June	 28, 2003: Added r_DumpFontTexture and r_DumpFontNames CVARs
//
//////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "CryFont.h"
#include "FBitmap.h"
#include "FFont.h"
#include <cassert>
#include <iostream>

static ICVar *r_DumpFontTexture = 0;
static ICVar *r_DumpFontNames = 0;

///////////////////////////////////////////////
CCryFont::CCryFont(ISystem *pSystem)
{
	// Assert system pointer is valid
	assert(pSystem != nullptr && "CCryFont: System pointer cannot be null");
	
  m_pISystem = pSystem;
	m_mapFonts.clear();
	
	// Assert font map is properly initialized
	assert(m_mapFonts.empty() && "CCryFont: Font map should be empty after initialization");

	// CVar added by marcio

	if (!r_DumpFontTexture)
	{
		// Assert console system is available
		assert(pSystem->GetIConsole() != nullptr && "CCryFont: Console system must be available for font operations");
		
		r_DumpFontTexture = pSystem->GetIConsole()->CreateVariable("r_DumpFontTexture", "0", 0, "Dumps the specified font's texture to a bitmap file!\n\nUsage: r_DumpFontTexture <fontname> <filename>");
		
		// Assert console variable was created successfully
		assert(r_DumpFontTexture != nullptr && "CCryFont: Failed to create r_DumpFontTexture console variable");
	}

	if (!r_DumpFontNames)
	{
		// Assert console system is available
		assert(pSystem->GetIConsole() != nullptr && "CCryFont: Console system must be available for font operations");
		
		r_DumpFontNames = pSystem->GetIConsole()->CreateVariable("r_DumpFontNames", "0", 0, "Displays a list of fonts currently loaded!");
		
		// Assert console variable was created successfully
		assert(r_DumpFontNames != nullptr && "CCryFont: Failed to create r_DumpFontNames console variable");
	}
}

///////////////////////////////////////////////
CCryFont::~CCryFont()
{
	// Assert system pointer is still valid during destruction
	assert(m_pISystem != nullptr && "CCryFont: System pointer should be valid during destruction");
	
#ifdef __APPLE__
	// On macOS, console variables are null, so no need to unregister
#else
	// Assert console system is available for cleanup
	assert(m_pISystem->GetIConsole() != nullptr && "CCryFont: Console system must be available for cleanup");
	
	m_pISystem->GetIConsole()->UnregisterVariable("r_DumpFontTexture", 1);
	m_pISystem->GetIConsole()->UnregisterVariable("r_DumpFontNames", 1);
#endif
	r_DumpFontTexture = 0;
	r_DumpFontNames = 0;

	// Assert font map is not empty before cleanup (should have fonts to clean up)
	assert(!m_mapFonts.empty() || m_mapFonts.empty() && "CCryFont: Font map state should be consistent");
	
	for (FontMapItor itor=m_mapFonts.begin();itor!=m_mapFonts.end(); itor++)
	{
		// Assert font object is valid before releasing
		assert(itor->second != nullptr && "CCryFont: Font object cannot be null during cleanup");
		
		IFFont *pFont=itor->second;
		pFont->Release();
	}
	m_mapFonts.clear();
	
	// Assert font map is empty after cleanup
	assert(m_mapFonts.empty() && "CCryFont: Font map should be empty after cleanup");
}

///////////////////////////////////////////////
void CCryFont::Release()
{
	delete this;
}


///////////////////////////////////////////////
IFFont* CCryFont::NewFont(const char *pszName)
{
	// Assert font name is valid
	assert(pszName != nullptr && "CCryFont::NewFont: Font name cannot be null");
	assert(strlen(pszName) > 0 && "CCryFont::NewFont: Font name cannot be empty");
	assert(strlen(pszName) < 256 && "CCryFont::NewFont: Font name too long");
	
	// Assert system is available
	assert(m_pISystem != nullptr && "CCryFont::NewFont: System must be available");
	
	string sName=pszName;
	for (int i=0;i<(int)sName.size();i++) sName[i]=tolower(sName[i]);
	
	// Assert name conversion was successful
	assert(!sName.empty() && "CCryFont::NewFont: Converted font name cannot be empty");
	
	// check if font already created, if so return it
	FontMapItor itor;
	itor=m_mapFonts.find(sName.c_str());
	if (itor!=m_mapFonts.end())
	{
		// Assert existing font is valid
		assert(itor->second != nullptr && "CCryFont::NewFont: Existing font object cannot be null");
		return itor->second;
	}
	
	// Assert we can create new font
	assert(m_pISystem != nullptr && "CCryFont::NewFont: System must be available for font creation");
	
	CFFont *pFont=new CFFont(m_pISystem, this, sName.c_str());
	
	// Assert font creation was successful
	assert(pFont != nullptr && "CCryFont::NewFont: Font creation failed");
	
	m_mapFonts.insert(FontMapItor::value_type(sName.c_str(), pFont));
	
	// Assert font was added to map
	assert(m_mapFonts.find(sName.c_str()) != m_mapFonts.end() && "CCryFont::NewFont: Font not found in map after insertion");
	
	return (IFFont*)pFont;
}

///////////////////////////////////////////////
IFFont* CCryFont::GetFont(const char *pszName)
{
	// Assert font name is valid
	assert(pszName != nullptr && "CCryFont::GetFont: Font name cannot be null");
	assert(strlen(pszName) > 0 && "CCryFont::GetFont: Font name cannot be empty");
	assert(strlen(pszName) < 256 && "CCryFont::GetFont: Font name too long");
	
	// Assert system is available
	assert(m_pISystem != nullptr && "CCryFont::GetFont: System must be available");
	
	// Add recursion protection to prevent infinite loops
	static int recursion_depth = 0;
	
	// Assert recursion depth is reasonable
	assert(recursion_depth >= 0 && "CCryFont::GetFont: Recursion depth should not be negative");
	
	if (++recursion_depth > 10) {
		// Prevent infinite recursion
		std::cerr << "CCryFont::GetFont: Recursion depth exceeded limit (" << recursion_depth << "), preventing infinite loop" << std::endl;
		recursion_depth--;
		return NULL;
	}

	// Check if console system is available before accessing console variables
	if (r_DumpFontTexture && m_pISystem && m_pISystem->GetIConsole())
	{
		// Assert console variable is valid
		assert(r_DumpFontTexture != nullptr && "CCryFont::GetFont: r_DumpFontTexture should not be null");
		
		const char *pValue = r_DumpFontTexture->GetString();
		
		// Assert console variable value is valid
		assert(pValue != nullptr && "CCryFont::GetFont: Console variable value cannot be null");

		if ((pValue) && (*pValue != 0) && (*pValue != '0'))
		{
			// Assert font name is valid
			assert(strlen(pValue) > 0 && "CCryFont::GetFont: Font name from console cannot be empty");
			assert(strlen(pValue) < 256 && "CCryFont::GetFont: Font name from console too long");
			
			string szFontName(pValue);
			string szFontFile(pValue);
			szFontFile += ".bmp";
			
			// Assert strings are valid
			assert(!szFontName.empty() && "CCryFont::GetFont: Font name string cannot be empty");
			assert(!szFontFile.empty() && "CCryFont::GetFont: Font file string cannot be empty");

			r_DumpFontTexture->Set("0"); // must be here, to avoid recursion
			
			// Use direct font map lookup instead of recursive GetFont call
			string sFontName = szFontName;
			for (int i=0;i<(int)sFontName.size();i++) sFontName[i]=tolower(sFontName[i]);
			
			// Assert name conversion was successful
			assert(!sFontName.empty() && "CCryFont::GetFont: Converted font name cannot be empty");
			
			FontMapItor itor = m_mapFonts.find(sFontName.c_str());
			CFFont *pFont = (itor != m_mapFonts.end()) ? (CFFont *)itor->second : NULL;

			if (pFont)
			{
				// Assert font object is valid
				assert(pFont != nullptr && "CCryFont::GetFont: Font object cannot be null");
				
				// Add safety check for font texture operation
				try {
					pFont->m_pFontTexture.WriteToFile(szFontFile.c_str());
				} catch (...) {
					// Handle file operation errors gracefully
					if (m_pISystem && m_pISystem->GetILog()) {
						m_pISystem->GetILog()->LogToConsole("\1Error: Failed to write font texture to file: %s", szFontFile.c_str());
					}
				}
			}

			// Assert logging system is available
			assert(m_pISystem->GetILog() != nullptr && "CCryFont::GetFont: Logging system must be available");
			
			m_pISystem->GetILog()->LogToConsole("\1Dumped '%s' texture to '%s'!", pValue, szFontFile.c_str());
		}
	}

	// Check if console system is available before accessing console variables
	if (r_DumpFontNames && m_pISystem && m_pISystem->GetIConsole())
	{
		// Assert console variable is valid
		assert(r_DumpFontNames != nullptr && "CCryFont::GetFont: r_DumpFontNames should not be null");
		
		if (r_DumpFontNames->GetIVal())
		{
			// Assert logging system is available
			assert(m_pISystem->GetILog() != nullptr && "CCryFont::GetFont: Logging system must be available for font names");
			
			FontMapItor pItor;
			CFFont *pFont;

			m_pISystem->GetILog()->LogToConsole("\1Currently Loaded Fonts:");

			// Assert font map is in valid state
			assert(!m_mapFonts.empty() || m_mapFonts.empty() && "CCryFont::GetFont: Font map state should be consistent");

			for (pItor=m_mapFonts.begin(); pItor != m_mapFonts.end(); ++pItor)
			{
				// Add safety check for font object
				if (pItor->second) {
					// Assert font object is valid
					assert(pItor->second != nullptr && "CCryFont::GetFont: Font object in map cannot be null");
					
					pFont = (CFFont *)pItor->second;
					if (pFont) {
						// Assert font name is valid
						assert(!pFont->m_szName.empty() && "CCryFont::GetFont: Font name cannot be empty");
						
						m_pISystem->GetILog()->LogToConsole("\1  - %s", pFont->m_szName.c_str());
					}
				}
			}

			r_DumpFontNames->Set(0);
		}
	}

	string sName=pszName;
	for (int i=0;i<(int)sName.size();i++) sName[i]=tolower(sName[i]);
	
	// Assert name conversion was successful
	assert(!sName.empty() && "CCryFont::GetFont: Converted font name cannot be empty");
	
	FontMapItor itor;
	itor=m_mapFonts.find(sName.c_str());
	
	// Assert recursion depth is still valid
	assert(recursion_depth > 0 && "CCryFont::GetFont: Recursion depth should be positive before decrement");
	
	// Decrement recursion depth before returning
	recursion_depth--;
	
	if (itor!=m_mapFonts.end())
	{
		// Assert found font is valid
		assert(itor->second != nullptr && "CCryFont::GetFont: Found font object cannot be null");
		return itor->second;
	}
	else
	{
		// Font not found - this is normal, return NULL
		return NULL;
	}
}

void CCryFont::GetMemoryUsage(class ICrySizer* pSizer)
{
	// Assert sizer is valid
	assert(pSizer != nullptr && "CCryFont::GetMemoryUsage: Sizer cannot be null");
	
	if (!pSizer->Add (*this))
		return;
		
	// Assert font map is in valid state
	assert(!m_mapFonts.empty() || m_mapFonts.empty() && "CCryFont::GetMemoryUsage: Font map state should be consistent");
	
	FontMapItor it = m_mapFonts.begin(), itEnd = m_mapFonts.end();
	for (; it != itEnd; ++it)
	{
		// Assert font object is valid
		assert(it->second != nullptr && "CCryFont::GetMemoryUsage: Font object in map cannot be null");
		
		// Assert font name is valid
		assert(!it->first.empty() && "CCryFont::GetMemoryUsage: Font name in map cannot be empty");
		
		pSizer->AddObject(&*it,sizeof(*it)+it->first.capacity()+1);
		it->second->GetMemoryUsage (pSizer);
	}
}

#include <CrtDebugStats.h>

