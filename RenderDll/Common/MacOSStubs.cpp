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
#include "StubTelemetry.h"

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

// CTexMan::CheckTexLimits — no-op on Metal. The legacy CTexMan-driven LRU
// eviction policy in the OGL/D3D9 backends does not apply: Metal manages its
// own texture lifecycle through CMetalTextureManager, which performs its own
// memory accounting and eviction. Telemetry remains so any unexpected
// caller from the Common layer is surfaced.
void CTexMan::CheckTexLimits(STexPic* pic)
{
    METAL_STUB_TRACE("CTexMan::CheckTexLimits", "pic=%p", (void*)pic);
}

// CCObject::GetInvMatrix — port of the D3D9 implementation
// (RenderDll/XRenderD3D9/D3DRendPipeline.cpp:1025) using the portable
// QQinvertMatrixf fallback baked into mathMatrixInverse on ARM/Apple Silicon.
// Caches inverted matrices in the shared CCObject::m_ObjMatrices pool.
namespace
{
    Matrix44& AcquireIdentityInvMatrix()
    {
        static Matrix44 sIdentity;
        static bool sSeeded = false;
        if (!sSeeded)
        {
            sIdentity.SetIdentity();
            sSeeded = true;
        }
        return sIdentity;
    }
}

Matrix44& CCObject::GetInvMatrix()
{
    if (m_InvMatrixId == 0)
        return AcquireIdentityInvMatrix();
    if (m_InvMatrixId > 0)
        return m_ObjMatrices[m_InvMatrixId];

    int n = m_ObjMatrices.size();
    m_ObjMatrices.resize(n + 1);
    m_InvMatrixId = (short)n;

    Matrix44& m = m_ObjMatrices[m_InvMatrixId];

    if (m_ObjFlags & FOB_TRANS_ROTATE)
    {
        mathMatrixInverse(m.GetData(), m_Matrix.GetData(), g_CpuFlags);
    }
    else if (m_ObjFlags & FOB_TRANS_SCALE)
    {
        const float fiScaleX = 1.0f / m_Matrix(0, 0);
        const float fiScaleY = 1.0f / m_Matrix(1, 1);
        const float fiScaleZ = 1.0f / m_Matrix(2, 2);
        m(0, 0) = fiScaleX;       m(0, 1) = m_Matrix(0, 1); m(0, 2) = m_Matrix(0, 2); m(0, 3) = m_Matrix(0, 3);
        m(1, 0) = m_Matrix(1, 0); m(1, 1) = fiScaleY;       m(1, 2) = m_Matrix(1, 2); m(1, 3) = m_Matrix(1, 3);
        m(2, 0) = m_Matrix(2, 0); m(2, 1) = m_Matrix(2, 1); m(2, 2) = fiScaleZ;       m(2, 3) = m_Matrix(2, 3);
        m(3, 0) = -m_Matrix(3, 0) * fiScaleX;
        m(3, 1) = -m_Matrix(3, 1) * fiScaleY;
        m(3, 2) = -m_Matrix(3, 2) * fiScaleZ;
        m(3, 3) = m_Matrix(3, 3);
    }
    else if (m_ObjFlags & FOB_TRANS_TRANSLATE)
    {
        m(0, 0) = m_Matrix(0, 0); m(0, 1) = m_Matrix(0, 1); m(0, 2) = m_Matrix(0, 2); m(0, 3) = m_Matrix(0, 3);
        m(1, 0) = m_Matrix(1, 0); m(1, 1) = m_Matrix(1, 1); m(1, 2) = m_Matrix(1, 2); m(1, 3) = m_Matrix(1, 3);
        m(2, 0) = m_Matrix(2, 0); m(2, 1) = m_Matrix(2, 1); m(2, 2) = m_Matrix(2, 2); m(2, 3) = m_Matrix(2, 3);
        m(3, 0) = -m_Matrix(3, 0);
        m(3, 1) = -m_Matrix(3, 1);
        m(3, 2) = -m_Matrix(3, 2);
        m(3, 3) = m_Matrix(3, 3);
    }
    else
    {
        m.SetIdentity();
    }

    return m;
}

// CRenderer::EF_SetState — forward to the virtual SetState() so the Metal
// renderer's full GS_*-flag translation in CMetalRenderer::SetState runs.
// EF_SetState is the legacy fixed-function entry point used by the OGL/D3D9
// backends; on Apple it is reachable only as the implementation behind the
// inline CRenderer::SetState in Renderer.h, which the derived
// CMetalRenderer::SetState already overrides. The forward here makes any
// direct EF_SetState caller pick up the same translation.
void CRenderer::EF_SetState(int state)
{
    SetState(state);
}

// CVProgram stub static members and methods
TArray<CVProgram*> CVProgram::m_VPrograms;

CVProgram* CVProgram::mfForName(const char* name, uint64 maskGen)
{
    METAL_STUB_TRACE("CVProgram::mfForName", "name=%s", name ? name : "(null)");
    return nullptr;
}

// CRETempMesh is implemented in RenderDll/XRenderMetal/MetalRETempMesh.mm

// CREClearStencil is implemented in RenderDll/XRenderMetal/MetalREClearStencil.mm

// CREFlareGeom::mfCheckVis is implemented in RenderDll/XRenderMetal/MetalREFlareGeom.mm

// Platform-specific device query stubs — safe nullptr on Metal. These are
// only invoked by editor/screenshot paths that branch on a non-null return.
void* gGet_D3DDevice()
{
    METAL_STUB_TRACE_BARE("gGet_D3DDevice");
    return nullptr;
}

void* gGet_glReadPixels()
{
    METAL_STUB_TRACE_BARE("gGet_glReadPixels");
    return nullptr;
}

// CLeafBuffer::DrawImmediately — empty in D3D9, D3D8 and NULL renderers
// (only the OGL backend implements it, as a debug/immediate-mode helper that
// is not part of the main draw path). Match the canonical no-op convention.
void CLeafBuffer::DrawImmediately()
{
}

// CVertexBuffer::GetStream — Metal port.
// Callers in LeafBufferCreate.cpp test the result against nullptr to decide
// whether to (re-)create a tangent stream; the D3D9 version returns the
// IDirect3DVertexBuffer9 pointer. For Metal we return the cached CPU-side
// pointer when the stream exists, nullptr otherwise — same null/non-null
// semantics required by the callers.
void* CVertexBuffer::GetStream(int nStream, int* nOffset)
{
    if (nOffset)
        *nOffset = 0;

    if (nStream < 0 || nStream >= VSF_NUM)
        return nullptr;

    if (m_VS[nStream].m_VertBuf.m_nID <= 0 && !m_VS[nStream].m_VData)
        return nullptr;

    return m_VS[nStream].m_VData;
}

// CShader::mfXxx — legacy fixed-function shader compile/hash/list/load path.
// Replaced on Metal by CMetalShaderManager which owns its own pipeline. The
// definitions here exist purely to satisfy the linker; telemetry surfaces any
// caller that escapes into them.
void CShader::mfAddToHash(char* name, SShader* shader)
{
    METAL_STUB_TRACE("CShader::mfAddToHash", "name=%s", name ? name : "(null)");
}

SShaderTechnique* CShader::mfCompileHW(SShader* shader, char* script, int flags)
{
    METAL_STUB_TRACE("CShader::mfCompileHW", "shader=%p flags=0x%x", (void*)shader, flags);
    return nullptr;
}

bool CShader::mfReloadFile(const char* filename, const char* name, int flags)
{
    METAL_STUB_TRACE("CShader::mfReloadFile", "name=%s", name ? name : "(null)");
    return false;
}

char** CShader::mfListInScript(char* name)
{
    METAL_STUB_TRACE("CShader::mfListInScript", "name=%s", name ? name : "(null)");
    return nullptr;
}

bool CShader::mfCompileTexGen(char* name, char* params, SShader* shader, SShaderTexUnit* unit)
{
    METAL_STUB_TRACE("CShader::mfCompileTexGen", "name=%s", name ? name : "(null)");
    return false;
}

void CShader::mfLoadFromFiles(int flags)
{
    METAL_STUB_TRACE("CShader::mfLoadFromFiles", "flags=0x%x", flags);
}

void CShader::mfRemoveFromHash(SShader* shader)
{
    METAL_STUB_TRACE("CShader::mfRemoveFromHash", "shader=%p", (void*)shader);
}

char* CShader::mfScriptForFileName(const char* filename, SShader* shader, uint64 maskGen)
{
    METAL_STUB_TRACE("CShader::mfScriptForFileName", "fn=%s", filename ? filename : "(null)");
    return nullptr;
}

void CShader::mfStartScriptPreprocess()
{
    METAL_STUB_TRACE_BARE("CShader::mfStartScriptPreprocess");
}

// CPShader stub methods and static members
class CPShader;
TArray<CPShader*> CPShader::m_PShaders;

CPShader* CPShader::mfForName(const char* name, uint64 nMaskGen)
{
    METAL_STUB_TRACE("CPShader::mfForName", "name=%s", name ? name : "(null)");
    return nullptr;
}

// Virtual-table anchors for the legacy fixed-function array/matrix/fog
// parameter binding classes. Replaced on Metal by direct uniform-buffer
// writes inside CMetalShaderManager; these are pure linker bait. Telemetry
// catches any caller that escapes back into them.

float SParamComp_Fog::mfGet()
{
    METAL_STUB_TRACE_BARE("SParamComp_Fog::mfGet");
    return 0.0f;
}

void SArrayPointer_Vertex::mfSet(int Id)
{
    METAL_STUB_TRACE("SArrayPointer_Vertex::mfSet", "id=%d", Id);
}

void SArrayPointer_Color::mfSet(int Id)
{
    METAL_STUB_TRACE("SArrayPointer_Color::mfSet", "id=%d", Id);
}

void SArrayPointer_SecColor::mfSet(int Id)
{
    METAL_STUB_TRACE("SArrayPointer_SecColor::mfSet", "id=%d", Id);
}

void SArrayPointer_Normal::mfSet(int Id)
{
    METAL_STUB_TRACE("SArrayPointer_Normal::mfSet", "id=%d", Id);
}

void SArrayPointer_Texture::mfSet(int Id)
{
    METAL_STUB_TRACE("SArrayPointer_Texture::mfSet", "id=%d", Id);
}

void SMatrixTransform_Identity::mfSet(bool bSet)
{
    METAL_STUB_TRACE("SMatrixTransform_Identity::mfSet(bool)", "bSet=%d", (int)bSet);
}

void SMatrixTransform_Identity::mfSet(Matrix44& matr)
{
    METAL_STUB_TRACE_BARE("SMatrixTransform_Identity::mfSet(Matrix44)");
}

void SMatrixTransform_Scale::mfSet(bool bSet)
{
    METAL_STUB_TRACE("SMatrixTransform_Scale::mfSet(bool)", "bSet=%d", (int)bSet);
}

void SMatrixTransform_Scale::mfSet(Matrix44& matr)
{
    METAL_STUB_TRACE_BARE("SMatrixTransform_Scale::mfSet(Matrix44)");
}

void SMatrixTransform_Translate::mfSet(bool bSet)
{
    METAL_STUB_TRACE("SMatrixTransform_Translate::mfSet(bool)", "bSet=%d", (int)bSet);
}

void SMatrixTransform_Translate::mfSet(Matrix44& matr)
{
    METAL_STUB_TRACE_BARE("SMatrixTransform_Translate::mfSet(Matrix44)");
}

void SMatrixTransform_Matrix::mfSet(bool bSet)
{
    METAL_STUB_TRACE("SMatrixTransform_Matrix::mfSet(bool)", "bSet=%d", (int)bSet);
}

void SMatrixTransform_Matrix::mfSet(Matrix44& matr)
{
    METAL_STUB_TRACE_BARE("SMatrixTransform_Matrix::mfSet(Matrix44)");
}

void SMatrixTransform_Rotate::mfSet(bool bSet)
{
    METAL_STUB_TRACE("SMatrixTransform_Rotate::mfSet(bool)", "bSet=%d", (int)bSet);
}

void SMatrixTransform_Rotate::mfSet(Matrix44& matr)
{
    METAL_STUB_TRACE_BARE("SMatrixTransform_Rotate::mfSet(Matrix44)");
}

// Standalone WriteJPG / WriteTGA helpers — only invoked by OGL/D3D9 backend
// code excluded from the Apple build. The 3D engine screenshot path goes
// through CRenderer::WriteJPG / WriteTGA virtuals, not these symbols.
void WriteJPG(byte* data, int width, int height, char* filename)
{
    METAL_STUB_TRACE("WriteJPG", "%dx%d fn=%s", width, height, filename ? filename : "(null)");
}

void WriteTGA(byte* data, int width, int height, char* filename, int bpp)
{
    METAL_STUB_TRACE("WriteTGA", "%dx%d bpp=%d fn=%s", width, height, bpp, filename ? filename : "(null)");
}

// ---------------------------------------------------------------------------
// JPEG and TGA image loaders using macOS CoreGraphics / ImageIO.
// Both produce 32-bpp BGRA output matching SRGBPixel{blue,green,red,alpha}.
// ---------------------------------------------------------------------------
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>

class CImageJpgFile : public CImageFile {
    friend class CImageFile;
public:
    CImageJpgFile(byte* ptr, long filesize);
    virtual ~CImageJpgFile() {}
};

CImageJpgFile::CImageJpgFile(byte* ptr, long filesize) : CImageFile()
{
    m_eFormat = eIF_Jpg;

    CFDataRef cfData = CFDataCreateWithBytesNoCopy(
        kCFAllocatorDefault, reinterpret_cast<const UInt8*>(ptr),
        static_cast<CFIndex>(filesize), kCFAllocatorNull);
    if (!cfData) { mfSet_error(eIFE_IOerror, const_cast<char*>("JPEG: CFData alloc failed")); return; }

    CGImageSourceRef src = CGImageSourceCreateWithData(cfData, nullptr);
    CFRelease(cfData);
    if (!src) { mfSet_error(eIFE_BadFormat, const_cast<char*>("JPEG: ImageSource failed")); return; }

    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, nullptr);
    CFRelease(src);
    if (!img) { mfSet_error(eIFE_BadFormat, const_cast<char*>("JPEG: decode failed")); return; }

    const int w = static_cast<int>(CGImageGetWidth(img));
    const int h = static_cast<int>(CGImageGetHeight(img));
    mfSet_dimensions(w, h);
    mfSet_ImageSize(w * h * 4);
    mfSet_bps(32);

    byte* pixels = mfGet_image();
    if (!pixels) { CGImageRelease(img); mfSet_error(eIFE_OutOfMemory, const_cast<char*>("JPEG: no memory")); return; }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels, w, h, 8, w * 4, cs,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    if (!ctx) { CGImageRelease(img); mfSet_error(eIFE_BadFormat, const_cast<char*>("JPEG: CGBitmapContext failed")); return; }

    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    CGContextRelease(ctx);
    CGImageRelease(img);
}

class CImageTgaFile : public CImageFile {
    friend class CImageFile;
public:
    CImageTgaFile(byte* ptr, long filesize);
    virtual ~CImageTgaFile() {}
};

CImageTgaFile::CImageTgaFile(byte* ptr, long filesize) : CImageFile()
{
    m_eFormat = eIF_Tga;

    CFDataRef cfData = CFDataCreateWithBytesNoCopy(
        kCFAllocatorDefault, reinterpret_cast<const UInt8*>(ptr),
        static_cast<CFIndex>(filesize), kCFAllocatorNull);
    if (!cfData) { mfSet_error(eIFE_IOerror, const_cast<char*>("TGA: CFData alloc failed")); return; }

    CGImageSourceRef src = CGImageSourceCreateWithData(cfData, nullptr);
    CFRelease(cfData);
    if (!src) { mfSet_error(eIFE_BadFormat, const_cast<char*>("TGA: ImageSource failed")); return; }

    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, nullptr);
    CFRelease(src);
    if (!img) { mfSet_error(eIFE_BadFormat, const_cast<char*>("TGA: decode failed")); return; }

    const int w = static_cast<int>(CGImageGetWidth(img));
    const int h = static_cast<int>(CGImageGetHeight(img));
    mfSet_dimensions(w, h);
    mfSet_ImageSize(w * h * 4);
    mfSet_bps(32);

    byte* pixels = mfGet_image();
    if (!pixels) { CGImageRelease(img); mfSet_error(eIFE_OutOfMemory, const_cast<char*>("TGA: no memory")); return; }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels, w, h, 8, w * 4, cs,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    if (!ctx) { CGImageRelease(img); mfSet_error(eIFE_BadFormat, const_cast<char*>("TGA: CGBitmapContext failed")); return; }

    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    CGContextRelease(ctx);
    CGImageRelease(img);
}

#endif // __APPLE__ && __MACH__

