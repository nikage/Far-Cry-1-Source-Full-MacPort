#include "MetalRenderPCH.h"
#include "MetalRenderer.m"

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <unistd.h>
#include <vector>

extern ILog* iLog;
extern IConsole* iConsole;

class ICrySizer;

namespace
{

class HarnessCVar final : public ICVar
{
public:
    HarnessCVar(const char* name, const char* val)
        : name_(name ? name : "")
        , str_(val ? val : "")
        , i_(atoi(str_.c_str()))
        , f_(static_cast<float>(atof(str_.c_str())))
        , flags_(0)
    {
    }

    HarnessCVar(const char* name, int v)
        : name_(name ? name : "")
        , str_(std::to_string(v))
        , i_(v)
        , f_(static_cast<float>(v))
        , flags_(0)
    {
    }

    HarnessCVar(const char* name, float v)
        : name_(name ? name : "")
        , i_(static_cast<int>(v))
        , f_(v)
        , flags_(0)
    {
        char buf[64];
        snprintf(buf, sizeof(buf), "%g", v);
        str_ = buf;
    }

    void Release() override {}
    int GetIVal() override { return i_; }
    float GetFVal() override { return f_; }
    char* GetString() override { return const_cast<char*>(str_.c_str()); }
    void Set(const char* s) override
    {
        str_ = s ? s : "";
        i_ = atoi(str_.c_str());
        f_ = static_cast<float>(atof(str_.c_str()));
    }
    void ForceSet(const char* s) override { Set(s); }
    void Set(float v) override
    {
        f_ = v;
        i_ = static_cast<int>(v);
        char buf[64];
        snprintf(buf, sizeof(buf), "%g", v);
        str_ = buf;
    }
    void Set(int v) override
    {
        i_ = v;
        f_ = static_cast<float>(v);
        str_ = std::to_string(v);
    }
    void Refresh() override {}
    void ClearFlags(int fl) override { (void)fl; }
    int GetFlags() override { return flags_; }
    int SetFlags(int fl) override
    {
        flags_ = fl;
        return flags_;
    }
    int GetType() override { return CVAR_STRING; }
    const char* GetName() override { return name_.c_str(); }
    const char* GetHelp() override { return ""; }

private:
    std::string name_;
    std::string str_;
    int i_;
    float f_;
    int flags_;
};

class HarnessConsole final : public IConsole
{
public:
    void Release() override {}

    ICVar* CreateVariable(const char* sName, const char* sValue, int nFlags, const char* help) override
    {
        (void)nFlags;
        (void)help;
        auto p = std::make_unique<HarnessCVar>(sName, sValue ? sValue : "");
        HarnessCVar* raw = p.get();
        cvars_.push_back(std::move(p));
        return raw;
    }

    ICVar* CreateVariable(const char* sName, int iValue, int nFlags, const char* help) override
    {
        (void)nFlags;
        (void)help;
        auto p = std::make_unique<HarnessCVar>(sName, iValue);
        HarnessCVar* raw = p.get();
        cvars_.push_back(std::move(p));
        return raw;
    }

    ICVar* CreateVariable(const char* sName, float fValue, int nFlags, const char* help) override
    {
        (void)nFlags;
        (void)help;
        auto p = std::make_unique<HarnessCVar>(sName, fValue);
        HarnessCVar* raw = p.get();
        cvars_.push_back(std::move(p));
        return raw;
    }

    void UnregisterVariable(const char* sVarName, bool bDelete) override
    {
        (void)sVarName;
        (void)bDelete;
    }

    void SetScrollMax(int value) override { (void)value; }

    void AddOutputPrintSink(IOutputPrintSink* inpSink) override { (void)inpSink; }

    void RemoveOutputPrintSink(IOutputPrintSink* inpSink) override { (void)inpSink; }

    void ShowConsole(bool show) override { (void)show; }

    int Register(const char* name, void* src, float defaultvalue, int flags, int type,
                 const char* help) override
    {
        (void)name;
        (void)flags;
        (void)help;
        if (!src)
            return 0;
        if (type == CVAR_FLOAT)
            *static_cast<float*>(src) = defaultvalue;
        else
            *static_cast<int*>(src) = static_cast<int>(defaultvalue);
        return 0;
    }

    float Register(const char* name, float* src, float defaultvalue, int flags,
                   const char* help) override
    {
        (void)name;
        (void)flags;
        (void)help;
        if (src)
            *src = defaultvalue;
        return defaultvalue;
    }

    int Register(const char* name, int* src, float defaultvalue, int flags,
                 const char* help) override
    {
        (void)name;
        (void)flags;
        (void)help;
        if (src)
            *src = static_cast<int>(defaultvalue);
        return src ? *src : 0;
    }

    void DumpCVars(ICVarDumpSink* pCallback, unsigned int nFlagsFilter) override
    {
        (void)pCallback;
        (void)nFlagsFilter;
    }

    void CreateKeyBind(const char* sCmd, const char* sRes, bool bExecute) override
    {
        (void)sCmd;
        (void)sRes;
        (void)bExecute;
    }

    void SetImage(ITexPic* pImage, bool bDeleteCurrent) override
    {
        (void)pImage;
        (void)bDeleteCurrent;
    }

    ITexPic* GetImage() override { return nullptr; }

    void StaticBackground(bool bStatic) override { (void)bStatic; }

    void SetLoadingImage(const char* szFilename) override { (void)szFilename; }

    bool GetLineNo(const DWORD indwLineNo, char* outszBuffer, const DWORD indwBufferSize) const override
    {
        (void)indwLineNo;
        (void)outszBuffer;
        (void)indwBufferSize;
        return false;
    }

    int GetLineCount() const override { return 0; }

    ICVar* GetCVar(const char* name, const bool bCaseSensitive) override
    {
        (void)bCaseSensitive;
        if (!name)
            return nullptr;
        for (const auto& p : cvars_)
        {
            if (p && p->GetName() && strcmp(p->GetName(), name) == 0)
                return p.get();
        }
        return nullptr;
    }

    CXFont* GetFont() override { return nullptr; }

    void Help(const char* command) override { (void)command; }

    char* GetVariable(const char* szVarName, const char* szFileName, const char* def_val) override
    {
        (void)szVarName;
        (void)szFileName;
        return const_cast<char*>(def_val ? def_val : "");
    }

    float GetVariable(const char* szVarName, const char* szFileName, float def_val) override
    {
        (void)szVarName;
        (void)szFileName;
        return def_val;
    }

    void PrintLine(const char* s) override { fprintf(stderr, "%s\n", s ? s : ""); }

    void PrintLinePlus(const char* s) override { fprintf(stderr, "%s", s ? s : ""); }

    bool GetStatus() override { return false; }

    void Clear() override {}

    void Update() override {}

    void Draw() override {}

    void AddCommand(const char* sName, const char* sScriptFunc, const DWORD indwFlags,
                    const char* help) override
    {
        (void)sName;
        (void)sScriptFunc;
        (void)indwFlags;
        (void)help;
    }

    void ExecuteString(const char* command, bool bNeedSlash, bool bIgnoreDevMode) override
    {
        (void)command;
        (void)bNeedSlash;
        (void)bIgnoreDevMode;
    }

    void Exit(const char* command, ...) override
    {
        va_list ap;
        va_start(ap, command);
        vfprintf(stderr, command, ap);
        va_end(ap);
        fputc('\n', stderr);
        exit(1);
    }

    bool IsOpened() override { return false; }

    int GetNumVars() override { return 0; }

    void GetSortedVars(const char** pszArray, size_t numItems) override
    {
        (void)pszArray;
        (void)numItems;
    }

    const char* AutoComplete(const char* substr) override
    {
        (void)substr;
        return "";
    }

    const char* AutoCompletePrev(const char* substr) override
    {
        (void)substr;
        return "";
    }

    char* ProcessCompletion(const char* szInputBuffer) override
    {
        (void)szInputBuffer;
        return nullptr;
    }

    void ResetAutoCompletion() override {}

    void DumpCommandsVars(char* prefix) override { (void)prefix; }

    void GetMemoryUsage(ICrySizer* pSizer) override { (void)pSizer; }

    void ResetProgressBar(int nProgressRange) override { (void)nProgressRange; }

    void TickProgressBar() override {}

    void DumpKeyBinds(IKeyBindDumpSink* pCallback) override { (void)pCallback; }

    const char* FindKeyBind(const char* sCmd) override
    {
        (void)sCmd;
        return "";
    }

    void AddConsoleVarSink(IConsoleVarSink* pSink) override { (void)pSink; }

    void RemoveConsoleVarSink(IConsoleVarSink* pSink) override { (void)pSink; }

    const char* GetHistoryElement(const bool bUpOrDown) override
    {
        (void)bUpOrDown;
        return "";
    }

    void AddCommandToHistory(const char* szCommand) override { (void)szCommand; }

private:
    std::vector<std::unique_ptr<HarnessCVar>> cvars_;
};

HarnessConsole g_harnessConsole;

class HarnessStderrLog : public ILog
{
public:
    void Release() override {}
    void SetFileName(const char*) override {}
    const char* GetFileName() override { return ""; }

    void LogV(IMiniLog::ELogType, const char* fmt, va_list args) override { vfprintf(stderr, fmt, args); }

    void Log(const char* fmt, ...) override
    {
        va_list a;
        va_start(a, fmt);
        vfprintf(stderr, fmt, a);
        va_end(a);
    }
    void LogWarning(const char* fmt, ...) override
    {
        va_list a;
        va_start(a, fmt);
        vfprintf(stderr, fmt, a);
        va_end(a);
    }
    void LogError(const char* fmt, ...) override
    {
        va_list a;
        va_start(a, fmt);
        vfprintf(stderr, fmt, a);
        va_end(a);
    }
    void LogPlus(const char* fmt, ...) override
    {
        va_list a;
        va_start(a, fmt);
        vfprintf(stderr, fmt, a);
        va_end(a);
    }
    void LogToFile(const char* fmt, ...) override
    {
        va_list a;
        va_start(a, fmt);
        vfprintf(stderr, fmt, a);
        va_end(a);
    }
    void LogToFilePlus(const char* fmt, ...) override
    {
        va_list a;
        va_start(a, fmt);
        vfprintf(stderr, fmt, a);
        va_end(a);
    }
    void LogToConsole(const char* fmt, ...) override
    {
        va_list a;
        va_start(a, fmt);
        vfprintf(stderr, fmt, a);
        va_end(a);
    }
    void LogToConsolePlus(const char* fmt, ...) override
    {
        va_list a;
        va_start(a, fmt);
        vfprintf(stderr, fmt, a);
        va_end(a);
    }
    void UpdateLoadingScreen(const char* fmt, ...) override
    {
        va_list a;
        va_start(a, fmt);
        vfprintf(stderr, fmt, a);
        va_end(a);
    }
    void UpdateLoadingScreenPlus(const char* fmt, ...) override
    {
        va_list a;
        va_start(a, fmt);
        vfprintf(stderr, fmt, a);
        va_end(a);
    }
    void EnableVerbosity(bool) override {}
    void SetVerbosity(int) override {}
    int GetVerbosityLevel() override { return 5; }
};

HarnessStderrLog g_harnessLog;

static void Usage()
{
    fprintf(stderr,
            "metal_runtime_validate --assets-dir DIR\n"
            "  Loads UtilShaders.metallib, GeneratedShaders.metallib, and generated_manifest.json\n"
            "  from DIR via FARCRY_METAL_VALIDATION_DIR (same path as staged FarCry.app Resources).\n"
            "  Runs the real CMetalShaderManager shader load path (no game loop).\n");
}

} // namespace

int main(int argc, const char* argv[])
{
    @autoreleasepool {

    const char* assetsDir = nullptr;
    for (int i = 1; i < argc; ++i)
    {
        if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h"))
        {
            Usage();
            return 0;
        }
        if (!strcmp(argv[i], "--assets-dir") && i + 1 < argc)
            assetsDir = argv[++i];
    }

    if (!assetsDir || !assetsDir[0])
    {
        fprintf(stderr, "metal_runtime_validate: missing --assets-dir\n");
        Usage();
        return 1;
    }

    if (setenv("FARCRY_METAL_VALIDATION_DIR", assetsDir, 1) != 0)
    {
        perror("metal_runtime_validate: setenv FARCRY_METAL_VALIDATION_DIR");
        return 1;
    }

    iConsole = &g_harnessConsole;
    iLog = &g_harnessLog;

    CMetalRenderer renderer;
    if (!renderer.InitializeMinimalForShaderLoadValidation())
    {
        fprintf(stderr, "metal_runtime_validate: InitializeMinimalForShaderLoadValidation failed\n");
        return 1;
    }

    CMetalTextureManager textureManager(&renderer);
    CMetalShaderManager shaderManager(&renderer, &textureManager);

    if (!shaderManager.GetDefaultLibrary())
    {
        fprintf(stderr, "metal_runtime_validate: default shader library not loaded\n");
        return 1;
    }

#ifdef NDEBUG
    shaderManager.RunValidateShaderPairs();
#endif

    const int psoFails = shaderManager.GetLastGeneratedShaderPsoFailureCount();
    const int pairFails = shaderManager.GetLastValidateShaderPairsFailureCount();
    fprintf(stdout,
            "metal_runtime_validate: pso_failures=%d validate_pair_failures=%d\n",
            psoFails,
            pairFails);
    fflush(stdout);

    const int exitCode = (psoFails > 0 || pairFails > 0) ? 2 : 0;
    std::_Exit(exitCode);
    }
}
