#pragma once

#include "../CryCommon/ICryPak.h"
#include "../CryCommon/ILog.h"

class CAssetValidator
{
public:
    bool ValidateMountedPaks(ICryPak* pPak, ILog* pLog);
};
