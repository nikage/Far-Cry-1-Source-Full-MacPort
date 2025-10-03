# Font Module Hang Analysis and Debugging Guide

## Problem Summary
The font module in FarCry is experiencing hangs during initialization or operation. Based on code analysis, several potential hang points have been identified.

## Identified Hang Points

### 1. Recursive GetFont Call (Critical)
**Location:** `CryFont.cpp:97`
```cpp
CFFont *pFont = (CFFont *)GetFont(szFontName.c_str());
```
**Issue:** This line calls `GetFont` recursively, which can cause infinite recursion if `szFontName` is the same as the original `pszName` parameter.

**Solution:** Add recursion protection or use a different method to access the font.

### 2. Console Variable Operations (High Risk)
**Location:** `CryFont.cpp:86-106`
**Issue:** Console variable operations (`r_DumpFontTexture`, `r_DumpFontNames`) can hang if:
- Console system is not properly initialized
- Console variables are accessed from multiple threads
- Console system is in a locked state

**Solution:** Ensure console system is properly initialized before font operations.

### 3. Font Texture WriteToFile Operation (Medium Risk)
**Location:** `CryFont.cpp:101`
```cpp
pFont->m_pFontTexture.WriteToFile(szFontFile.c_str());
```
**Issue:** File system operations can hang if:
- File system is locked
- Disk I/O is blocked
- File permissions are incorrect

**Solution:** Add timeout or use async file operations.

### 4. Font Map Iteration (Low Risk)
**Location:** `CryFont.cpp:117-122`
**Issue:** Font map iteration can hang if:
- Font objects are corrupted
- Map is being modified during iteration
- Memory corruption in font objects

**Solution:** Add iteration protection and null checks.

## Debugging Approach

### Method 1: LLDB Debugging (Recommended)
```bash
# Start LLDB debugging
lldb build_test/FarCryWorking.app/Contents/MacOS/FarCryWorking

# Set breakpoints on potential hang points
(lldb) breakpoint set --name GetFont
(lldb) breakpoint set --file CryFont.cpp --line 97
(lldb) breakpoint set --file CryFont.cpp --line 101
(lldb) breakpoint set --file CryFont.cpp --line 117

# Run the program
(lldb) run

# When it hangs, analyze the call stack
(lldb) bt
(lldb) thread list
(lldb) thread backtrace all
```

### Method 2: Memory Debugging
```bash
# Enable Address Sanitizer
export ASAN_OPTIONS=detect_leaks=1:abort_on_error=1
export MallocStackLogging=1
export MallocCheckHeapStart=1

# Run with debugging
lldb build_test/FarCryWorking.app/Contents/MacOS/FarCryWorking
```

### Method 3: Automated Debugging Script
```bash
# Use the provided Python script
python3 debug_font_lldb.py build_test/FarCryWorking.app/Contents/MacOS/FarCryWorking
```

## Recommended Fixes

### Fix 1: Add Recursion Protection to GetFont
```cpp
// In CryFont.cpp, modify the GetFont method
IFFont* CCryFont::GetFont(const char *pszName)
{
    static int recursion_depth = 0;
    if (++recursion_depth > 10) {
        // Prevent infinite recursion
        recursion_depth--;
        return NULL;
    }
    
    // ... existing code ...
    
    recursion_depth--;
    return result;
}
```

### Fix 2: Add Console System Check
```cpp
// Before console variable operations
if (!m_pISystem || !m_pISystem->GetIConsole()) {
    return NULL; // Console not available
}
```

### Fix 3: Add File Operation Timeout
```cpp
// For font texture operations
bool WriteToFileWithTimeout(const char* filename, int timeout_ms = 5000) {
    // Implement timeout mechanism
    // Use async file operations or thread with timeout
}
```

## Testing Commands

### Test 1: Basic Hang Detection
```bash
# Run with timeout to detect hangs
./debug_font_module.sh
```

### Test 2: LLDB Analysis
```bash
# Use LLDB for detailed analysis
lldb build_test/FarCryWorking.app/Contents/MacOS/FarCryWorking
(lldb) breakpoint set --name GetFont
(lldb) run
```

### Test 3: Memory Analysis
```bash
# Run with memory debugging
export ASAN_OPTIONS=detect_leaks=1
lldb build_test/FarCryWorking.app/Contents/MacOS/FarCryWorking
```

## Expected Results

After applying the fixes:
1. **Recursion Protection:** Prevents infinite recursion in GetFont calls
2. **Console System Check:** Ensures console is available before operations
3. **File Operation Timeout:** Prevents hangs on file system operations
4. **Iteration Protection:** Prevents hangs during font map iteration

## Monitoring and Validation

Use the provided debugging tools to:
1. Verify that recursive calls are prevented
2. Confirm console system is properly initialized
3. Ensure file operations complete within timeout
4. Validate font map iteration is safe

## Conclusion

The most likely cause of the font module hang is the recursive GetFont call at line 97 in CryFont.cpp. The recommended approach is to:

1. Add recursion protection to the GetFont method
2. Ensure console system is properly initialized
3. Add timeouts to file operations
4. Use the provided debugging tools to validate the fixes

This should resolve the font module hang issues and provide a stable font system for the FarCry Mac Silicon port.


