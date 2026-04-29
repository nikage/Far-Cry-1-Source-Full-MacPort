#pragma once

#include "IScriptSystem.h"
#include <string>

// Simple script system stub for macOS
class CSimpleScriptSystem : public IScriptSystem
{
public:
    CSimpleScriptSystem() {}
    virtual ~CSimpleScriptSystem() {}
    
    // IScriptSystem interface implementation (minimal stubs)
    virtual void Release() override { delete this; }
    virtual bool ExecuteFile(const char* sFileName, bool bRaiseError = true) override { return true; }
    virtual bool ExecuteBuffer(const char* sBuffer, size_t nSize) override { 
        // Log the script execution attempt
        printf("ScriptSystem::ExecuteBuffer called with: %s\n", sBuffer ? sBuffer : "NULL");
        return true; 
    }
    virtual bool ExecuteBuffer(const char* sBuffer) override { 
        printf("ScriptSystem::ExecuteBuffer called with: %s\n", sBuffer ? sBuffer : "NULL");
        return true; 
    }
    virtual void UnloadScript(const char* sFileName) override {}
    virtual void UnloadScripts() override {}
    virtual void ReloadScript(const char* sFileName) override {}
    virtual void ReloadScripts() override {}
    virtual bool GetGlobalValue(const char* sKey, int& nVal) override { return false; }
    virtual bool GetGlobalValue(const char* sKey, float& fVal) override { return false; }
    virtual bool GetGlobalValue(const char* sKey, const char*& sVal) override { return false; }
    virtual void SetGlobalValue(const char* sKey, int nVal) override {}
    virtual void SetGlobalValue(const char* sKey, float fVal) override {}
    virtual void SetGlobalValue(const char* sKey, const char* sVal) override {}
    virtual bool GetGlobalValue(const char* sKey, bool& bVal) override { return false; }
    virtual void SetGlobalValue(const char* sKey, bool bVal) override {}
    virtual void BeginCall(const char* sTableName, const char* sFunctionName) override {}
    virtual void EndCall() override {}
    virtual void BeginCall(const char* sFunctionName) override {}
    virtual void PushParam(int nVal) override {}
    virtual void PushParam(float fVal) override {}
    virtual void PushParam(const char* sVal) override {}
    virtual void PushParam(bool bVal) override {}
    virtual void PushParam(void* pVal) override {}
    virtual bool EndCallAny(int nReturns) override { return true; }
    virtual bool EndCallAny(int nReturns, IScriptObject* pObj) override { return true; }
    virtual bool EndCall(int nReturns) override { return true; }
    virtual bool EndCall(int nReturns, IScriptObject* pObj) override { return true; }
    virtual IScriptObject* CreateEmptyObject() override { return nullptr; }
    virtual IScriptObject* CreateGlobalObject(const char* sName) override { return nullptr; }
    virtual IScriptObject* GetGlobalObject() override { return nullptr; }
    virtual void ForceGarbageCollection() override {}
    virtual void SetGCFrequency(const float fRate) override {}
    virtual void SetDebugger(IScriptDebugSink* pDebugSink) override {}
    virtual void DebugContinue() override {}
    virtual void DebugStepNext() override {}
    virtual void DebugStepInto() override {}
    virtual void DebugDisable() override {}
    virtual void GetMemoryUsage(ICrySizer* pSizer) override {}
    virtual void DumpLoadedScripts() override {}
    virtual void PostInit() override {}
};
