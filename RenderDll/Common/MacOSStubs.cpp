////////////////////////////////////////////////////////////////////////////
//
//  Crytek Engine Source File - Mac Silicon Port
//  Copyright (C), Crytek Studios, 2002.
// -------------------------------------------------------------------------
//  File name:   MacOSStubs.cpp
//  Version:     v1.00
//  Created:     29/10/2025 by Mac Silicon Port Team.
//  Description: Stub implementations for macOS
// -------------------------------------------------------------------------
//
////////////////////////////////////////////////////////////////////////////

#if defined(__APPLE__) && defined(__MACH__)

#include "../RenderPCH.h"

namespace
{
SShader* AcquireFallbackShader()
{
    if (gRenDev && gRenDev->m_cEF.m_DefaultShader)
    {
        gRenDev->m_cEF.m_DefaultShader->AddRef();
        return gRenDev->m_cEF.m_DefaultShader;
    }

    static SShader fallback;
    static bool seeded = false;
    if (!seeded)
    {
        fallback.m_Name = "mac_null_shader";
        fallback.m_Id = -1;
        fallback.m_Flags = EF_SYSTEM;
        fallback.m_eClass = eSH_World;
        seeded = true;
    }
    fallback.AddRef();
    return &fallback;
}
}

SShader* CShader::mfForName(const char* name, EShClass cl, int flags, const SInputShaderResources* resources, uint64 maskGen)
{
    if (!name || !name[0])
        return AcquireFallbackShader();

    if (gRenDev)
    {
        if (SShader* resolved = gRenDev->m_cEF.mfForName(name, cl, flags, resources, maskGen))
            return resolved;
        if (SShader* fallbackDefault = gRenDev->m_cEF.m_DefaultShader)
        {
            fallbackDefault->AddRef();
            return fallbackDefault;
        }
    }

    return AcquireFallbackShader();
}

// STexPic stub methods
void STexPic::BuildMips()
{
    CreateMips();
}

bool STexPic::UploadMips(int start, int count)
{
    (void)start;
    (void)count;
    return true;
}

void STexPic::SetWrapping()
{
    SetClamp(true);
}

void STexPic::RemoveFromPool()
{
    Unlink();
    m_pPoolItem = nullptr;
}

void STexPic::ReleaseDriverTexture()
{
    m_Bind = 0;
    m_LoadedSize = 0;
    m_Flags2 |= FT2_WASUNLOADED;
}

int STexPic::DstFormatFromTexFormat(ETEX_Format fmt)
{
    return static_cast<int>(fmt);
}

void STexPic::PrecacheAsynchronously(float priority, int flags)
{
    (void)priority;
    Preload(flags);
}

void STexPic::Set(int unit)
{
    (void)unit;
}

void STexPic::Preload(int flags)
{
    (void)flags;
}

void STexPic::SaveJPG(const char* filename, bool bMips)
{
    (void)filename;
    (void)bMips;
}

void STexPic::SaveTGA(const char* filename, bool bMips)
{
    (void)filename;
    (void)bMips;
}

int STexPic::TexSize(int width, int height, int format)
{
    (void)format;
    return width * height * 4;
}

void STexPic::SetClamp(bool clamp)
{
    if (clamp)
        m_Flags |= FT_CLAMP;
    else
        m_Flags &= ~FT_CLAMP;
}

byte* STexPic::GetData32()
{
    return m_pData32;
}

bool STexPic::SetFilter(int filter)
{
    (void)filter;
    return true;
}

void STexPic::SetFilter()
{
}

bool SShader::Reload(int flags)
{
    (void)flags;
    return false;
}

// CTexMan stub methods
void CTexMan::CheckTexLimits(STexPic* pic)
{
    // TODO: Implement texture limit checking
    assert(false && "TODO: Implement texture limit checking");
}

// CCObject stub methods
Matrix44& CCObject::GetInvMatrix()
{
    // TODO: Implement inverse matrix retrieval
    assert(false && "TODO: Implement inverse matrix retrieval");
    static Matrix44 identity;
    identity.SetIdentity();
    return identity;
}

// CRenderer stub methods
void CRenderer::EF_SetState(int state)
{
    // TODO: Implement render state setting
    assert(false && "TODO: Implement render state setting");
}

// CVProgram stub static members and methods
TArray<CVProgram*> CVProgram::m_VPrograms;

CVProgram* CVProgram::mfForName(const char* name, uint64 maskGen)
{
    // TODO: Implement vertex program lookup
    assert(false && "TODO: Implement vertex program lookup");
    return nullptr;
}

// CREOcean stubs (conditionally excluded from build, but need symbols for linker)
float CREOcean::GetWaterZElevation(float x, float y)
{
    // macOS: CREOcean is not supported
    return 0.0f;
}

CREOcean* CREOcean::m_pStaticOcean = nullptr;

// CRETempMesh stub for vtable
bool CRETempMesh::mfDraw(SShader* ef, SShaderPass* sfm)
{
    // TODO: Implement temp mesh rendering
    assert(false && "TODO: Implement temp mesh rendering");
    return false;
}

void CRETempMesh::mfReset()
{
    // TODO: Implement reset
    assert(false && "TODO: Implement reset");
}

bool CRETempMesh::mfPreDraw(SShaderPass* sl)
{
    // TODO: Implement pre-draw
    assert(false && "// TODO: Implement pre-draw");
    return false;
}

void CRETempMesh::mfPrepare()
{
    // TODO: Implement prepare
    assert(false && "TODO: Implement prepare");
}

void* CRETempMesh::mfGetPointer(ESrcPointer ePT, int *Stride, int Type, ESrcPointer Dst, int Flags)
{
    // TODO: Implement pointer retrieval
    assert(false && "TODO: Implement pointer retrieval");
    if (Stride)
        *Stride = 0;
    return nullptr;
}

// CREClearStencil stub for vtable
bool CREClearStencil::mfDraw(SShader* ef, SShaderPass* sfm)
{
    // TODO: Implement stencil clear
    assert(false && "TODO: Implement stencil clear");
    return false;
}

// CREFlareGeom stub method
void CREFlareGeom::mfCheckVis(CFColor& col, CCObject* obj)
{
    // TODO: Implement flare visibility check
    assert(false && "TODO: Implement flare visibility check");
    assert(false && "Implement flare visibility check");
}

// Platform-specific device query stubs
void* gGet_D3DDevice()
{
    // macOS doesn't use D3D
    assert(false && "macOS doesn't use D3D");
    return nullptr;
}

void* gGet_glReadPixels()
{
    // macOS doesn't have OpenGL equivalent for Metal
    assert(false && "macOS doesn't have OpenGL equivalent for Metal");
    return nullptr;
}

// CLeafBuffer stub method
void CLeafBuffer::DrawImmediately()
{
    // macOS: immediate mode drawing not implemented
    assert(false && "macOS: immediate mode drawing not implemented");
}

// CVertexBuffer stub method
void* CVertexBuffer::GetStream(int StreamMask, int* nOffset)
{
    // macOS: vertex stream not implemented
    assert(false && "macOS: vertex stream not implemented");
    if (nOffset)
        *nOffset = 0;
    return nullptr;
}

// CShader stub methods
void CShader::mfAddToHash(char* name, SShader* shader)
{
    // macOS: shader hash not implemented
    assert(false && "macOS: shader hash not implemented");
}

SShaderTechnique* CShader::mfCompileHW(SShader* shader, char* script, int flags)
{
    // macOS: hardware shader compilation not implemented
    assert(false && "macOS: hardware shader compilation not implemented");
    return nullptr;
}

bool CShader::mfReloadFile(const char* filename, const char* name, int flags)
{
    // macOS: shader reload not implemented
    assert(false && "macOS: shader reload not implemented");
    return false;
}

char** CShader::mfListInScript(char* name)
{
    // macOS: shader listing not implemented
    assert(false && "macOS: shader listing not implemented");
    return nullptr;
}

bool CShader::mfCompileTexGen(char* name, char* params, SShader* shader, SShaderTexUnit* unit)
{
    // macOS: texture generation not implemented
    assert(false && "macOS: texture generation not implemented");
    return false;
}

void CShader::mfLoadFromFiles(int flags)
{
    // macOS: shader loading not implemented
    assert(false && "macOS: shader loading not implemented");
}

void CShader::mfRemoveFromHash(SShader* shader)
{
    // macOS: shader hash removal not implemented
    assert(false && "macOS: shader hash removal not implemented");
}

char* CShader::mfScriptForFileName(const char* filename, SShader* shader, uint64 maskGen)
{
    // macOS: script naming not implemented
    assert(false && "macOS: script naming not implemented");
    return nullptr;
}

void CShader::mfStartScriptPreprocess()
{
    // macOS: script preprocessing not implemented
    assert(false && "macOS: script preprocessing not implemented");
}

// CPShader stub methods and static members
class CPShader;
TArray<CPShader*> CPShader::m_PShaders;

CPShader* CPShader::mfForName(const char* name, uint64 nMaskGen)
{
    // macOS: pixel shader lookup not implemented
    assert(false && "macOS: pixel shader lookup not implemented");
    return nullptr;
}

// Virtual table stub implementations for shader system classes

// SParamComp_Fog stub
float SParamComp_Fog::mfGet()
{
    // macOS: fog parameter not implemented
    assert(false && "macOS: fog parameter not implemented");
    return 0.0f;
}

// SArrayPointer stubs
void SArrayPointer_Vertex::mfSet(int Id)
{
    // macOS: vertex array pointer not implemented
    assert(false && "macOS: vertex array pointer not implemented");
}

void SArrayPointer_Color::mfSet(int Id)
{
    // macOS: color array pointer not implemented
    assert(false && "macOS: color array pointer not implemented");
}

void SArrayPointer_SecColor::mfSet(int Id)
{
    // macOS: secondary color array pointer not implemented
    assert(false && "macOS: secondary color array pointer not implemented");
}

void SArrayPointer_Normal::mfSet(int Id)
{
    // macOS: normal array pointer not implemented
    assert(false && "macOS: normal array pointer not implemented");
}

void SArrayPointer_Texture::mfSet(int Id)
{
    // macOS: texture array pointer not implemented
    assert(false && "macOS: texture array pointer not implemented");
}

// SMatrixTransform stubs
void SMatrixTransform_Identity::mfSet(bool bSet)
{
    // macOS: identity matrix transform not implemented
    assert(false && "macOS: identity matrix transform not implemented");
}

void SMatrixTransform_Identity::mfSet(Matrix44& matr)
{
    // macOS: identity matrix transform not implemented
    assert(false && "macOS: identity matrix transform not implemented");
}

void SMatrixTransform_Scale::mfSet(bool bSet)
{
    // macOS: scale matrix transform not implemented
    assert(false && "macOS: scale matrix transform not implemented");
}

void SMatrixTransform_Scale::mfSet(Matrix44& matr)
{
    // macOS: scale matrix transform not implemented
    assert(false && "macOS: scale matrix transform not implemented");
}

void SMatrixTransform_Translate::mfSet(bool bSet)
{
    // macOS: translate matrix transform not implemented
    assert(false && "macOS: translate matrix transform not implemented");
}

void SMatrixTransform_Translate::mfSet(Matrix44& matr)
{
    // macOS: translate matrix transform not implemented
    assert(false && "macOS: translate matrix transform not implemented");
}

void SMatrixTransform_Matrix::mfSet(bool bSet)
{
    // macOS: matrix transform not implemented
    assert(false && "macOS: matrix transform not implemented");
}

void SMatrixTransform_Matrix::mfSet(Matrix44& matr)
{
    // macOS: matrix transform not implemented
    assert(false && "macOS: matrix transform not implemented");
}

void SMatrixTransform_Rotate::mfSet(bool bSet)
{
    // macOS: rotate matrix transform not implemented
    assert(false && "macOS: rotate matrix transform not implemented");
}

void SMatrixTransform_Rotate::mfSet(Matrix44& matr)
{
    // macOS: rotate matrix transform not implemented
    assert(false && "macOS: rotate matrix transform not implemented");
}

void WriteJPG(byte* data, int width, int height, char* filename)
{
    // macOS: JPEG writing not implemented
    assert(false && "macOS: JPEG writing not implemented");
}

void WriteTGA(byte* data, int width, int height, char* filename, int bpp)
{
    // macOS: TGA writing not implemented
    assert(false && "macOS: TGA writing not implemented");
}

// JPEG image loader stub
class CImageJpgFile : public CImageFile {
public:
    CImageJpgFile(byte* ptr, long filesize);
    virtual ~CImageJpgFile();
};

CImageJpgFile::CImageJpgFile(byte* ptr, long filesize) {
    // macOS: JPEG loading not implemented
    assert(false && "macOS: JPEG loading not implemented");
}

CImageJpgFile::~CImageJpgFile() {
}

// TGA image loader stub
class CImageTgaFile : public CImageFile {
public:
    CImageTgaFile(byte* ptr, long filesize);
    virtual ~CImageTgaFile();
};

CImageTgaFile::CImageTgaFile(byte* ptr, long filesize) {
    // macOS: TGA loading not implemented
    assert(false && "macOS: TGA loading not implemented");
}

CImageTgaFile::~CImageTgaFile() {
}

#endif // __APPLE__ && __MACH__

