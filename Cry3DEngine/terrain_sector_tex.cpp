////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File.
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   terrain_sector_tex.cpp
//  Version:     v1.00
//  Created:     28/5/2001 by Vladimir Kajalin
//  Compilers:   Visual Studio.NET
//  Description: terrain texture management
// -------------------------------------------------------------------------
//  History:
//
////////////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "terrain_sector.h"
#include "terrain.h"
#include "objman.h"

// set texture for sector
void CSectorInfo::SetTextures(bool bMakeUncompressedForEditing)
{
	FUNCTION_PROFILER( GetSystem(),PROFILE_3DENGINE );

	assert(m_pTerrain && "SetTextures: m_pTerrain cannot be null!");
	assert(m_pTerrain->m_pTexturePool && "SetTextures: texture pool cannot be null!");

	if(m_bLockTexture) // always keep full texture detail during editing
		m_cNewTextMML = 0;

  { // required actions
    if(!m_nLowLodTextureID)
    {
      m_nLowLodTextureID = MakeSectorTextureDDS( GetSecIndex(), MAX_TEX_MML_LEVEL, bMakeUncompressedForEditing );
      assert(m_nLowLodTextureID && "SetTextures: failed to create low LOD texture!");
    }

    if(!m_nTextureID)
    {
      m_nTextureID = m_nLowLodTextureID;
      m_cTextureMML = MAX_TEX_MML_LEVEL; 
    }
  }

  // desired actions
  if(m_cTextureMML > m_cNewTextMML)
  { // increase tex resolution
		if(!m_bLockTexture)
		{
			if(m_pTerrain->m_nUploadsInFrame>1)
				return; // no more than 1 upload per frame

			// remove hi res texture if it's not needed
			if(m_cGeometryMML>=MAX_MML_LEVEL) // NOTE: in testing
			{
				if(m_nTextureID != m_nLowLodTextureID)
				{
					m_pTerrain->m_pTexturePool->RemoveTexture(m_nTextureID);
					assert(m_nTextureID);
					assert(m_nTextureID != m_nLowLodTextureID);
					m_nTextureID = m_nLowLodTextureID;
					m_cTextureMML = MAX_TEX_MML_LEVEL; 
				}
				return;
			}

			m_pTerrain->m_nUploadsInFrame++;

			if(m_nTextureID != m_nLowLodTextureID)
				GetLog()->Log("CSectorInfo::SetTextureAndLOD: m_nTextureID != m_nLowLodTextureID");
		}

    m_cTextureMML = m_cNewTextMML; 
    m_nTextureID = MakeSectorTextureDDS( GetSecIndex(), m_cTextureMML, bMakeUncompressedForEditing );
  
    if(m_pTerrain->GetCVars()->e_terrain_log) 
      GetLog()->Log("tex loaded %d(%d)", GetSecIndex(), m_cTextureMML);
  }
  else if(m_cTextureMML < m_cNewTextMML)
  { // reduce tex resolution
    if(m_nTextureID == m_nLowLodTextureID)
      GetLog()->Log("CSectorInfo::SetTextureAndLOD: m_nTextureID == m_nLowLodTextureID");

    m_pTerrain->m_pTexturePool->RemoveTexture(m_nTextureID);
    m_nTextureID = m_nLowLodTextureID;
    m_cTextureMML = MAX_TEX_MML_LEVEL; 
  }
}

// load compresssed texture from disk
int CSectorInfo::MakeSectorTextureDDS( int sec_id, int nMipMapLevelToLoad, bool bMakeUncompressedForEditing )
{
	FUNCTION_PROFILER( GetSystem(),PROFILE_3DENGINE );

	assert(m_pTerrain && "MakeSectorTextureDDS: m_pTerrain cannot be null!");
	assert(m_pTerrain->m_pTexturePool && "MakeSectorTextureDDS: texture pool cannot be null!");
	assert(sec_id >= 0 && "MakeSectorTextureDDS: sector ID cannot be negative!");
	assert(nMipMapLevelToLoad >= 0 && "MakeSectorTextureDDS: mip level cannot be negative!");

	nMipMapLevelToLoad+=GetCVars()->e_terrain_texture_mip_offset;

  // open file once
  if(!m_pTerrain->m_fpTerrainTextureFile)
  { 
    m_pTerrain->m_fpTerrainTextureFile = GetSystem()->GetIPak()->FOpen(Get3DEngine()->GetLevelFilePath("terrain\\cover.ctc"), "rb");

    if(!m_pTerrain->m_fpTerrainTextureFile) 
      return 0;

    GetSystem()->GetIPak()->FRead(&m_pTerrain->m_nSectorTextureReadedSize, 1, 4, m_pTerrain->m_fpTerrainTextureFile);
    assert(m_pTerrain->m_nSectorTextureReadedSize > 0 && "MakeSectorTextureDDS: invalid texture size read from file!");
    GetLog()->Log("  TerrainSectorTextureSize %dx%d", m_pTerrain->m_nSectorTextureReadedSize, m_pTerrain->m_nSectorTextureReadedSize);

    GetSystem()->GetIPak()->FSeek( m_pTerrain->m_fpTerrainTextureFile, 0, SEEK_END);
    int nFileSize = GetSystem()->GetIPak()->FTell(m_pTerrain->m_fpTerrainTextureFile);
    assert(nFileSize > 4 && "MakeSectorTextureDDS: terrain texture file is too small!");

    int nSectorsTableSize = m_pTerrain->GetSectorsTableSize();
    assert(nSectorsTableSize > 0 && "MakeSectorTextureDDS: invalid sectors table size!");
    m_pTerrain->m_nSectorTextureDataSizeBytes = (nFileSize-4)/(nSectorsTableSize*nSectorsTableSize);
    assert(m_pTerrain->m_nSectorTextureDataSizeBytes > 0 && "MakeSectorTextureDDS: invalid sector texture data size!");
    GetLog()->Log("  SectorTextureDataSizeBytes = %d", m_pTerrain->m_nSectorTextureDataSizeBytes);

    m_pTerrain->m_ucpTmpTexBuffer = new uchar [m_pTerrain->m_nSectorTextureDataSizeBytes];
    assert(m_pTerrain->m_ucpTmpTexBuffer && "MakeSectorTextureDDS: failed to allocate temp texture buffer!");
  }

  if(!m_pTerrain->m_fpTerrainTextureFile)
  { Warning(0,0,"MakeSectorTextureDDS: !m_pTerrain->m_fpTerrainTextureFile"); return 0; }
  
  assert(m_pTerrain->m_ucpTmpTexBuffer && "MakeSectorTextureDDS: temp texture buffer is null!");
  
  // count mm levels
  int nMipLevels=0;
  int w = m_pTerrain->m_nSectorTextureReadedSize;
  assert(w > 0 && "MakeSectorTextureDDS: invalid texture size!");
  while(w>0)
  { w/=2; nMipLevels++; }
  assert(nMipLevels > 0 && "MakeSectorTextureDDS: no mip levels calculated!");

  int nDataSize = m_pTerrain->m_nSectorTextureDataSizeBytes;
  assert(nDataSize > 0 && "MakeSectorTextureDDS: invalid data size!");
  
  int nTexSize  = m_pTerrain->m_nSectorTextureReadedSize;
  assert(nTexSize > 0 && "MakeSectorTextureDDS: invalid texture size!");

  // calculate texture offset in file
  int file_offset = 4+sec_id*m_pTerrain->m_nSectorTextureDataSizeBytes;
  assert(file_offset >= 4 && "MakeSectorTextureDDS: invalid file offset!");

  // if not zero mml specified
  for(int m=0; m<nMipMapLevelToLoad; m++)
  {
    assert(nTexSize > 0 && "MakeSectorTextureDDS: texture size became zero or negative during mip calculation!");
    file_offset = file_offset + nTexSize*nTexSize/2;
    nDataSize -= nTexSize*nTexSize/2;
    nMipLevels--;
    nTexSize = nTexSize/2;
  }
  
  assert(nTexSize > 0 && "MakeSectorTextureDDS: final texture size is invalid!");
  assert(nDataSize > 0 && "MakeSectorTextureDDS: final data size is invalid!");
  assert(nMipLevels > 0 && "MakeSectorTextureDDS: no mip levels remaining!");

	assert(m_pTerrain->m_nSectorTextureDataSizeBytes >= (GetCVars()->e_terrain_texture_mipmaps ? nDataSize : nTexSize*nTexSize/2));

  // read texture
  GetSystem()->GetIPak()->FSeek( m_pTerrain->m_fpTerrainTextureFile, file_offset, SEEK_SET );
  int nBytesToRead = GetCVars()->e_terrain_texture_mipmaps ? nDataSize : nTexSize*nTexSize/2;
  assert(nBytesToRead > 0 && "MakeSectorTextureDDS: invalid number of bytes to read!");
  INT_PTR readed = GetSystem()->GetIPak()->FRead(m_pTerrain->m_ucpTmpTexBuffer, 1,		//AMD Port
    nBytesToRead, 
    m_pTerrain->m_fpTerrainTextureFile);
  assert(readed == nBytesToRead && "MakeSectorTextureDDS: failed to read complete texture data from file!");

  // no reason to use update texture instead create since size is always diferent
/*  int nTexID = GetRenderer()->DownLoadToVideo Memory(m_pTerrain->m_ucpTmpTexBuffer,
    nTexSize, nTexSize, eTF_DXT1, eTF_DXT1,
    GetCVars()->e_terrain_texture_mipmaps ? nMipLevels : 0, false,
    GetCVars()->e_terrain_texture_mipmaps ? FILTER_BILINEAR : FILTER_LINEAR);*/

  int nTexID = m_pTerrain->m_pTexturePool->MakeTexture(m_pTerrain->m_ucpTmpTexBuffer, nTexSize, this, bMakeUncompressedForEditing);
  assert(nTexID != 0 && "MakeSectorTextureDDS: failed to create texture!");

  return (nTexID);
}
/*
void CSectorInfo::UpdateSectorTexture(unsigned char * pTexData, int nSizeOffTexData)
{
  int nTexSize = m_pTerrain->m_nSectorTextureReadedSize;

  if(nSizeOffTexData != nTexSize*nTexSize*3)
  { 
    GetLog()->Log("Error: CSectorInfo::UpdateSectorTexture: nSizeOffTexData error"); 
    return; 
  }

  if(m_nTextureID)
  {
    GetRenderer()->UpdateTextureInVideoMemory(m_nTextureID,pTexData,0,0,nTexSize,nTexSize,eTF_0888);
  }
  else
  {
    assert(0);
//    m_nTextureID = GetRenderer()->DownLoadToVideo Memory(pTexData,
  //    nTexSize,nTexSize,eTF_0888,eTF_DXT1,0,false);
  }
}	*/

int CSectorInfo::LockSectorTexture(int & nTexDim)
{
	assert(m_pTerrain && "LockSectorTexture: m_pTerrain cannot be null!");
	assert(m_pTerrain->m_nSectorTextureReadedSize > 0 && "LockSectorTexture: invalid sector texture size!");
	
	m_bLockTexture = true;
	nTexDim = m_pTerrain->m_nSectorTextureReadedSize;
	// force texture reloading as uncompressed
	m_cNewTextMML = 0;
	m_cTextureMML = 1;
	SetTextures(true);
	
	assert(m_nTextureID != 0 && "LockSectorTexture: texture ID is zero after SetTextures!");
	return m_nTextureID;
}

void CSectorInfo::RemoveSectorTextures(bool bRemoveLowLod)
{
  assert(m_pTerrain && "RemoveSectorTextures: m_pTerrain cannot be null!");
  assert(m_pTerrain->m_pTexturePool && "RemoveSectorTextures: texture pool cannot be null!");
  
  // remove high
  if(m_nTextureID)
  {
    assert(m_nTextureID != 0 && "RemoveSectorTextures: attempting to remove invalid texture ID!");
    m_pTerrain->m_pTexturePool->RemoveTexture(m_nTextureID);
    assert(m_nLowLodTextureID);
    m_nTextureID = m_nLowLodTextureID;
    m_cTextureMML = MAX_TEX_MML_LEVEL; 
  }

  // remove low
  if(bRemoveLowLod)
  {
    assert(m_nLowLodTextureID != 0 && "RemoveSectorTextures: attempting to remove invalid low LOD texture ID!");
    m_pTerrain->m_pTexturePool->RemoveTexture(m_nLowLodTextureID);
    m_nTextureID = m_nLowLodTextureID = 0;
  }
}

void CSectorInfo::UnloadHeighFieldTexture(float fDistanse, float fMaxViewDist)
{
	assert(m_pTerrain && "UnloadHeighFieldTexture: m_pTerrain cannot be null!");
	assert(m_pTerrain->m_pTexturePool && "UnloadHeighFieldTexture: texture pool cannot be null!");
	assert(fDistanse >= 0.0f && "UnloadHeighFieldTexture: distance cannot be negative!");
	assert(fMaxViewDist > 0.0f && "UnloadHeighFieldTexture: max view distance must be positive!");
	
	if(m_nTextureID && m_cTextureMML == 0 && m_nTextureID!=m_nLowLodTextureID)
	{ // unload if to far or not in use int time
		assert(m_nTextureID != m_nLowLodTextureID && "UnloadHeighFieldTexture: texture ID should not equal low LOD ID here!");
		if(m_nTextureID == m_nLowLodTextureID)
			GetLog()->Log("unload old secs error");

		// set low lod tex
		//glDeleteTextures(1, &(m_nTextureID) );
		assert(m_nTextureID != 0 && "UnloadHeighFieldTexture: attempting to remove invalid texture ID!");
		m_pTerrain->m_pTexturePool->RemoveTexture(m_nTextureID);
		m_nTextureID = m_nLowLodTextureID;
		m_cTextureMML = MAX_TEX_MML_LEVEL; 

		if(GetCVars()->e_terrain_log)
			GetLog()->Log("lod0 tex unloaded");
	}
	else if(m_nTextureID && m_nTextureID == m_nLowLodTextureID)
	{ // only low lod
		assert(m_nTextureID == m_nLowLodTextureID && "UnloadHeighFieldTexture: texture IDs should match here!");
		if(fDistanse > (1.5f*fMaxViewDist))
		{
			assert(m_nTextureID != 0 && "UnloadHeighFieldTexture: attempting to remove invalid texture ID!");
			m_pTerrain->m_pTexturePool->RemoveTexture(m_nTextureID);
			m_nTextureID = m_nLowLodTextureID = 0;
			m_cTextureMML = 0;

			if(GetCVars()->e_terrain_log)
				GetLog()->Log("lod1 tex unloaded");
		}
	}
	else if(!m_nTextureID && !m_nLowLodTextureID)
	{ // no textures
		m_nTextureID = m_nLowLodTextureID;
	}
	else
	{
		Warning(0,0,"CTerrain::UnloadOldSectors: tex management error");
	}
}