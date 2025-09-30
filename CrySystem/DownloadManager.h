#pragma once

//#ifndef LINUX

class CHTTPDownloader;

#ifdef __APPLE__
// macOS stub implementation
class CDownloadManager
{
public:
	CDownloadManager() {}
	virtual ~CDownloadManager() {}
	void Create(ISystem *pSystem) {}
	CHTTPDownloader *CreateDownload() { return nullptr; }
	void RemoveDownload(CHTTPDownloader *pDownload) {}
	void Update() {}
	void Release() {}
};
#else
// Original Windows implementation
class CDownloadManager
{
public:
	CDownloadManager();
	virtual ~CDownloadManager();

	void Create(ISystem *pSystem);
	CHTTPDownloader *CreateDownload();
	void RemoveDownload(CHTTPDownloader *pDownload);
	void Update();
	void Release();

private:

	ISystem												*m_pSystem;
	std::list<CHTTPDownloader *>	m_lDownloadList;
};
#endif

//#endif //LINUX