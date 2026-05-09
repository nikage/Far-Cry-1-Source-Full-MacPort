#pragma once

inline const char* CryLog_TextAfterVerbosityPrefix(const char* pText)
{
	if (!pText || pText[0] == '\0')
		return pText;
	if ((unsigned char)pText[0] >= ' ')
		return pText;
	return pText + 1;
}
