# Font Module Assertions Guide

## Overview
Comprehensive assertion system has been added to the CryFont module to catch bugs early and provide detailed debugging information. The assertions help identify issues during development and prevent runtime crashes.

## Assertion Categories

### 1. Parameter Validation Assertions
**Purpose:** Validate input parameters to prevent invalid operations

**Examples:**
```cpp
// Font name validation
assert(pszName != nullptr && "CCryFont::NewFont: Font name cannot be null");
assert(strlen(pszName) > 0 && "CCryFont::NewFont: Font name cannot be empty");
assert(strlen(pszName) < 256 && "CCryFont::NewFont: Font name too long");

// File name validation
assert(szFile != nullptr && "CFFont::Load: File name cannot be null");
assert(strlen(szFile) > 0 && "CFFont::Load: File name cannot be empty");
assert(strlen(szFile) < 512 && "CFFont::Load: File name too long");

// Dimension validation
assert(nWidth > 0 && "CFFont::Load: Width must be positive");
assert(nHeight > 0 && "CFFont::Load: Height must be positive");
assert(nWidth < 4096 && "CFFont::Load: Width too large");
assert(nHeight < 4096 && "CFFont::Load: Height too large");
```

### 2. System State Assertions
**Purpose:** Ensure system components are properly initialized

**Examples:**
```cpp
// System pointer validation
assert(m_pISystem != nullptr && "CCryFont: System pointer cannot be null");
assert(pSystem->GetIConsole() != nullptr && "CCryFont: Console system must be available");

// Console variable validation
assert(r_DumpFontTexture != nullptr && "CCryFont: Failed to create r_DumpFontTexture console variable");
assert(r_DumpFontNames != nullptr && "CCryFont: Failed to create r_DumpFontNames console variable");
```

### 3. Memory Safety Assertions
**Purpose:** Prevent null pointer dereferences and memory corruption

**Examples:**
```cpp
// Font object validation
assert(pFont != nullptr && "CCryFont::NewFont: Font creation failed");
assert(itor->second != nullptr && "CCryFont::GetFont: Font object cannot be null");

// Memory sizer validation
assert(pSizer != nullptr && "CCryFont::GetMemoryUsage: Sizer cannot be null");
```

### 4. Recursion Protection Assertions
**Purpose:** Prevent infinite recursion and stack overflow

**Examples:**
```cpp
// Recursion depth validation
assert(recursion_depth >= 0 && "CCryFont::GetFont: Recursion depth should not be negative");
assert(recursion_depth > 0 && "CCryFont::GetFont: Recursion depth should be positive before decrement");

// Recursion limit protection
if (++recursion_depth > 10) {
    std::cerr << "CCryFont::GetFont: Recursion depth exceeded limit (" << recursion_depth << "), preventing infinite loop" << std::endl;
    recursion_depth--;
    return NULL;
}
```

### 5. String and Data Validation Assertions
**Purpose:** Ensure string operations and data integrity

**Examples:**
```cpp
// String validation
assert(!sName.empty() && "CCryFont::NewFont: Converted font name cannot be empty");
assert(!szFontName.empty() && "CCryFont::GetFont: Font name string cannot be empty");
assert(!pFont->m_szName.empty() && "CCryFont::GetFont: Font name cannot be empty");

// Console variable value validation
assert(pValue != nullptr && "CCryFont::GetFont: Console variable value cannot be null");
```

### 6. State Consistency Assertions
**Purpose:** Ensure object state remains consistent

**Examples:**
```cpp
// Font map state validation
assert(m_mapFonts.empty() && "CCryFont: Font map should be empty after initialization");
assert(!m_mapFonts.empty() || m_mapFonts.empty() && "CCryFont: Font map state should be consistent");
assert(m_mapFonts.find(sName.c_str()) != m_mapFonts.end() && "CCryFont::NewFont: Font not found in map after insertion");
```

## Assertion Usage Guidelines

### 1. Debug vs Release Builds
- **Debug builds:** All assertions are active and will terminate the program on failure
- **Release builds:** Assertions are typically disabled for performance
- **Development:** Always use debug builds during development

### 2. Assertion Messages
- Use descriptive messages that explain what went wrong
- Include the function name and parameter name
- Provide context about expected vs actual values

### 3. Performance Considerations
- Assertions have minimal performance impact in debug builds
- They are completely removed in release builds
- Use assertions liberally during development

## Testing Assertions

### 1. Compile with Debug Flags
```bash
g++ -g -DDEBUG -o font_test font_test.cpp
```

### 2. Run Assertion Tests
```bash
./test_font_asserts
```

### 3. Test Invalid Operations
```cpp
// These should trigger assertions in debug mode
CCryFont font(nullptr);  // Should assert: System pointer cannot be null
font.NewFont("");        // Should assert: Font name cannot be empty
font.NewFont(nullptr);   // Should assert: Font name cannot be null
```

## Common Assertion Failures and Solutions

### 1. "System pointer cannot be null"
**Cause:** ISystem pointer is null during font operations
**Solution:** Ensure system is properly initialized before creating fonts

### 2. "Font name cannot be empty"
**Cause:** Empty or null font name passed to font functions
**Solution:** Validate font names before passing to font functions

### 3. "Recursion depth exceeded limit"
**Cause:** Infinite recursion in GetFont calls
**Solution:** Check for circular references in font loading

### 4. "Console system must be available"
**Cause:** Console system not initialized
**Solution:** Ensure console system is initialized before font operations

### 5. "Font object cannot be null"
**Cause:** Font creation failed or memory corruption
**Solution:** Check memory allocation and font file validity

## Debugging with Assertions

### 1. Enable Core Dumps
```bash
ulimit -c unlimited
```

### 2. Use GDB for Analysis
```bash
gdb ./font_program core
(gdb) bt
(gdb) info locals
(gdb) print variable_name
```

### 3. Use LLDB for macOS
```bash
lldb ./font_program
(lldb) run
(lldb) bt
(lldb) thread backtrace all
```

## Assertion Best Practices

### 1. Use Assertions for:
- Parameter validation
- Preconditions and postconditions
- Invariant checking
- Error condition detection

### 2. Don't Use Assertions for:
- User input validation (use proper error handling)
- Expected error conditions
- Performance-critical code paths
- Side effects (assertions may be disabled)

### 3. Assertion Message Format:
```cpp
assert(condition && "FunctionName: Description of what went wrong");
```

## Integration with Build System

### 1. Debug Build Configuration
```cmake
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_definitions(CryFont PRIVATE DEBUG=1)
    target_compile_options(CryFont PRIVATE -g -O0)
endif()
```

### 2. Release Build Configuration
```cmake
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    target_compile_definitions(CryFont PRIVATE NDEBUG=1)
    target_compile_options(CryFont PRIVATE -O3 -DNDEBUG)
endif()
```

## Conclusion

The comprehensive assertion system in the font module provides:
- **Early bug detection** during development
- **Detailed error messages** for debugging
- **Memory safety** protection
- **Recursion protection** against infinite loops
- **State consistency** validation

This system significantly improves the reliability and debuggability of the font module, making it easier to identify and fix issues during development.


