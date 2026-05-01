#ifndef _CRY_SYSTEM_PAK_VARS_HDR_
#define _CRY_SYSTEM_PAK_VARS_HDR_

// variables that control behaviour of CryPak/StreamEngine subsystems
struct PakVars
{
	int nPriority;
	int nReadSlice;
	int nLogMissingFiles;
	PakVars()
		: nPriority(1)
		, nReadSlice(0)
#ifdef _DEBUG
		, nLogMissingFiles(1)
#else
		, nLogMissingFiles(0)
#endif
	{}
};


#endif