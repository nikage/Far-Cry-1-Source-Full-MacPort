// ImageLoaderTests.cpp — regression tests for CImageJpgFile / CImageTgaFile
// via CoreGraphics / ImageIO on macOS.
//
// Build & run:
//   clang++ -std=c++17 -framework CoreFoundation -framework CoreGraphics \
//           -framework ImageIO -o image_loader_tests ImageLoaderTests.cpp \
//           && ./image_loader_tests

#include <cassert>
#include <cstdio>
#include <cstring>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>

// ---------------------------------------------------------------------------
// Minimal CImageFile shim — only the interface used by the loaders.
// ---------------------------------------------------------------------------
enum EImFormat { eIF_Unknown = 0, eIF_Jpg = 3, eIF_Tga = 2 };
enum EImFileError { eIFE_OK = 0, eIFE_IOerror, eIFE_OutOfMemory, eIFE_BadFormat };
typedef unsigned char byte;
typedef unsigned char uchar;

struct SRGBPixel { uchar blue, green, red, alpha; };

class CImageFile {
    friend class CImageJpgFile;
    friend class CImageTgaFile;

    int m_Width  = 0;
    int m_Height = 0;
    int m_Depth  = 1;
    int m_Bps    = 0;
    int m_ImgSize = 0;
    int m_NumMips = 0;
    int m_Flags   = 0;
    union { SRGBPixel* m_pPixImage = nullptr; byte* m_pByteImage; };
    static EImFileError m_eError;
    static char m_Error_detail[256];

protected:
    EImFormat  m_eFormat = eIF_Unknown;
    SRGBPixel* m_pPal    = nullptr;

    CImageFile() { m_pByteImage = nullptr; m_eError = eIFE_OK; }

    static void mfSet_error(EImFileError e, char* d = nullptr) {
        m_eError = e;
        if (d) strncpy(m_Error_detail, d, 255);
    }
    void mfSet_dimensions(int w, int h) { m_Width = w; m_Height = h; }

public:
    virtual ~CImageFile() { delete[] m_pByteImage; delete[] m_pPal; }

    int   mfGet_width()  { return m_Width; }
    int   mfGet_height() { return m_Height; }
    int   mfGet_bps()    { return m_Bps; }
    void  mfSet_bps(int b) { m_Bps = b; }
    void  mfSet_ImageSize(int s) { m_ImgSize = s; }
    int   mfGet_ImageSize() { return m_ImgSize; }
    EImFormat mfGetFormat() { return m_eFormat; }

    byte* mfGet_image() {
        if (!m_pByteImage && m_ImgSize)
            m_pByteImage = new byte[m_ImgSize];
        return m_pByteImage;
    }

    static EImFileError mfGet_error() { return m_eError; }
    static char* mfGet_error_detail() { return m_Error_detail; }

    static char m_CurFileName[128];
    char m_FileName[128] = {};
};

EImFileError CImageFile::m_eError = eIFE_OK;
char CImageFile::m_Error_detail[256] = {};
char CImageFile::m_CurFileName[128]  = {};

// ---------------------------------------------------------------------------
// Pull in the loaders (uses #define to avoid the full renderer includes).
// ---------------------------------------------------------------------------
#define __APPLE__
#define __MACH__

// Inline the loader bodies directly — same code as in MacOSStubs.cpp.

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

// ---------------------------------------------------------------------------
// Helpers: synthesise minimal JPEG and PNG (used as TGA-format stand-in)
// buffers in memory so the tests don't need external files.
// ---------------------------------------------------------------------------

// Returns a minimal 1x1 red JPEG in a heap buffer; sets *outSize.
static byte* makeMinimalJpeg(long* outSize)
{
    // 1×1 red JPEG produced by ImageIO
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(nullptr, 1, 1, 8, 4, cs,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    CGContextSetRGBFillColor(ctx, 1, 0, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, 1, 1));
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);

    CFMutableDataRef buf = CFDataCreateMutable(kCFAllocatorDefault, 0);
    CGImageDestinationRef dst = CGImageDestinationCreateWithData(
        buf, CFSTR("public.jpeg"), 1, nullptr);
    CGImageDestinationAddImage(dst, img, nullptr);
    CGImageDestinationFinalize(dst);
    CFRelease(dst);
    CGImageRelease(img);

    CFIndex len = CFDataGetLength(buf);
    byte* out = new byte[len];
    memcpy(out, CFDataGetBytePtr(buf), len);
    CFRelease(buf);
    *outSize = static_cast<long>(len);
    return out;
}

// Returns a minimal 1x1 green PNG (ImageIO decodes it just like TGA).
static byte* makeMinimalPng(long* outSize)
{
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(nullptr, 1, 1, 8, 4, cs,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    CGContextSetRGBFillColor(ctx, 0, 1, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, 1, 1));
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);

    CFMutableDataRef buf = CFDataCreateMutable(kCFAllocatorDefault, 0);
    CGImageDestinationRef dst = CGImageDestinationCreateWithData(
        buf, CFSTR("public.png"), 1, nullptr);
    CGImageDestinationAddImage(dst, img, nullptr);
    CGImageDestinationFinalize(dst);
    CFRelease(dst);
    CGImageRelease(img);

    CFIndex len = CFDataGetLength(buf);
    byte* out = new byte[len];
    memcpy(out, CFDataGetBytePtr(buf), len);
    CFRelease(buf);
    *outSize = static_cast<long>(len);
    return out;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static int passed = 0, failed = 0;
#define EXPECT(cond, msg) \
    do { if (cond) { ++passed; } else { ++failed; printf("FAIL: %s\n", msg); } } while(0)

static void test_jpeg_loads_1x1_red()
{
    long sz;
    byte* buf = makeMinimalJpeg(&sz);
    CImageJpgFile img(buf, sz);
    delete[] buf;

    EXPECT(CImageFile::mfGet_error() == eIFE_OK,      "JPEG: no error");
    EXPECT(img.mfGet_width()  == 1,                   "JPEG: width == 1");
    EXPECT(img.mfGet_height() == 1,                   "JPEG: height == 1");
    EXPECT(img.mfGet_bps()    == 32,                  "JPEG: bps == 32");
    EXPECT(img.mfGetFormat()  == eIF_Jpg,             "JPEG: format == eIF_Jpg");
    EXPECT(img.mfGet_ImageSize() == 4,                "JPEG: image size == 4");

    byte* pixels = img.mfGet_image();
    EXPECT(pixels != nullptr,                         "JPEG: pixels allocated");
    if (pixels) {
        // SRGBPixel layout: [blue, green, red, alpha]
        // Red pixel → blue~0, green~0, red~255
        EXPECT(pixels[2] > 200,                       "JPEG: red channel is bright");
        EXPECT(pixels[0] < 80,                        "JPEG: blue channel is dark");
        EXPECT(pixels[1] < 80,                        "JPEG: green channel is dark");
    }
}

static void test_jpeg_null_input_sets_error()
{
    byte dummy = 0;
    // zero size → CFData with zero bytes → ImageSource should fail gracefully
    CImageJpgFile img(&dummy, 0);
    EXPECT(CImageFile::mfGet_error() != eIFE_OK,      "JPEG null input: error is set");
}

static void test_tga_loads_1x1_green_png()
{
    long sz;
    byte* buf = makeMinimalPng(&sz);
    // CImageTgaFile uses ImageIO which accepts PNG too — tests the same decode path.
    CImageTgaFile img(buf, sz);
    delete[] buf;

    EXPECT(CImageFile::mfGet_error() == eIFE_OK,      "TGA/PNG: no error");
    EXPECT(img.mfGet_width()  == 1,                   "TGA/PNG: width == 1");
    EXPECT(img.mfGet_height() == 1,                   "TGA/PNG: height == 1");
    EXPECT(img.mfGetFormat()  == eIF_Tga,             "TGA/PNG: format == eIF_Tga");

    byte* pixels = img.mfGet_image();
    EXPECT(pixels != nullptr,                         "TGA/PNG: pixels allocated");
    if (pixels) {
        // Green pixel → blue~0, green~255, red~0
        EXPECT(pixels[1] > 200,                       "TGA/PNG: green channel is bright");
        EXPECT(pixels[0] < 80,                        "TGA/PNG: blue channel is dark");
        EXPECT(pixels[2] < 80,                        "TGA/PNG: red channel is dark");
    }
}

int main()
{
    test_jpeg_loads_1x1_red();
    test_jpeg_null_input_sets_error();
    test_tga_loads_1x1_green_png();

    printf("%s — %d passed, %d failed\n",
           failed == 0 ? "PASS" : "FAIL", passed, failed);
    return failed == 0 ? 0 : 1;
}
