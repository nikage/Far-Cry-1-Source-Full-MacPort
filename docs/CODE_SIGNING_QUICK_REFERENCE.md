# Code Signing Quick Reference

## The Problem
```
Exception Type: EXC_BAD_ACCESS (SIGKILL (Code Signature Invalid))
Termination Reason: Namespace CODESIGNING, Code 2 Invalid Page
```

## The Solution
```bash
# Quick fix - use the launcher script
./launch_farcry.sh

# Or set the environment variable manually
DYLD_DISABLE_CODE_SIGNING=1 ./FarCryWorking
```

## Why This Happens
- macOS requires all `.dylib` files to have valid code signatures
- Far Cry uses 12+ custom libraries without proper signatures
- macOS kills the process when it detects unsigned libraries

## What the Environment Variable Does
`DYLD_DISABLE_CODE_SIGNING=1` tells the dynamic linker to skip code signature validation, allowing unsigned libraries to load.

## Security Note
⚠️ **Only use in trusted development environments!** Never use this with untrusted code.

## For Production Distribution
If you need proper code signing:

```bash
# Sign individual libraries
codesign --force --sign "Your Developer ID" libXRenderMetal.dylib

# Sign the entire app bundle
codesign --force --sign "Your Developer ID" --deep FarCryWorking.app

# Or use ad-hoc signing for local distribution
codesign --force --sign - --deep FarCryWorking.app
```

## Verification Commands
```bash
# Check if a library is signed
codesign -dv libXRenderMetal.dylib

# Check app bundle signature
codesign -dv FarCryWorking.app

# List all signatures in the app
codesign -dv --verbose=4 FarCryWorking.app
```

---
**Quick Fix**: Just run `./launch_farcry.sh` and you're good to go! 🚀
