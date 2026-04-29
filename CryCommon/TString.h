// This is supposed to be a collection of string class implementations for different purposes

#ifndef _TEMPLATE_STRING_HDR_
#define _TEMPLATE_STRING_HDR_

#include "platform.h"

#if !defined(LINUX)
#include <assert.h>
#endif


#include <string>
#include "string.h"
#include "StlUtils.h"



//[Timur] 
//! Typedef for string to be used everywhere.
typedef string String;

// A basic string that can be used (with caution though) to pass a variable-length string
// between boundaries of DLLs
// (release/debug versions are binary compatible, as long as they're constructed, destructed
// and modified withon one DLL
// THe string contents may be safely modified, up to (excluding) the \0 character
// THE \0 character cannot be touched AT ALL! because it can end up with an access violation
class CryBasicString
{
public:
	CryBasicString() = default;

	CryBasicString(const char* szRight)
	{
		assign(szRight);
	}

	CryBasicString(const char* szBegin, const char* szEnd)
	{
		assign(szBegin, szEnd);
	}

	CryBasicString(const char* szBegin, unsigned nLength)
	{
		assign(szBegin, nLength);
	}

	CryBasicString(const CryBasicString&) = default;
	CryBasicString(const string& rRight)
	{
		assign(rRight.c_str(), (unsigned)rRight.length());
	}

	~CryBasicString() = default;

	CryBasicString& operator = (const char* szRight)
	{
		assign(szRight);
		return *this;
	}

	CryBasicString& operator = (const CryBasicString&) = default;
	CryBasicString& operator = (const string& rRight)
	{
		assign(rRight.c_str(), (unsigned)rRight.length());
		return *this;
	}

	void assign(const char* szBegin, const char* szEnd)
	{
		if (!szBegin || !szEnd || szEnd < szBegin)
		{
			m_value.clear();
			return;
		}
		m_value.assign(szBegin, szEnd - szBegin);
	}

	void assign(const char* szBegin, unsigned nLength)
	{
		if (!szBegin || !nLength)
		{
			m_value.clear();
			return;
		}
		m_value.assign(szBegin, nLength);
	}

	const char* c_str() const
	{
		return m_value.c_str();
	}

	char operator[](int nIndex) const
	{
		assert(nIndex >= 0 && nIndex < length());
		return m_value[nIndex];
	}

	char& operator[](int nIndex)
	{
		assert(nIndex >= 0 && nIndex < length());
		return m_value[nIndex];
	}

	int length() const
	{
		return (int)m_value.length();
	}
	int size() const { return length(); }

	bool empty() const
	{
		return m_value.empty();
	}

	bool operator < (const CryBasicString& strRight) const
	{
		return m_value < strRight.m_value;
	}
	bool operator == (const CryBasicString& strRight) const
	{
		return m_value == strRight.m_value;
	}
	bool operator > (const CryBasicString& strRight) const
	{
		return m_value > strRight.m_value;
	}

	CryBasicString& operator += (const char* szRight)
	{
		if (szRight && szRight[0])
			m_value += szRight;
		return *this;
	}

	CryBasicString& operator += (const CryBasicString& rRight)
	{
		m_value += rRight.m_value;
		return *this;
	}

	void swap(CryBasicString& right)
	{
		m_value.swap(right.m_value);
	}

	friend CryBasicString operator + (const char* szLeft, const CryBasicString& rRight);
	friend CryBasicString operator + (const CryBasicString& rLeft, const char* szRight);
	friend CryBasicString operator + (const CryBasicString& rLeft, const CryBasicString& rRight);

private:
	void assign(const char* szRight)
	{
		m_value = szRight ? szRight : "";
	}

private:
	std::string m_value;
};

inline CryBasicString operator + (const char* szLeft, const CryBasicString& rRight)
{
	CryBasicString strResult;
	strResult.m_value = std::string(szLeft ? szLeft : "") + rRight.m_value;
	return strResult;
}

inline CryBasicString operator + (const CryBasicString& rLeft, const char* szRight)
{
	CryBasicString strResult;
	strResult.m_value = rLeft.m_value + std::string(szRight ? szRight : "");
	return strResult;
}

inline CryBasicString operator + (const CryBasicString& rLeft, const CryBasicString& rRight)
{
	CryBasicString strResult;
	strResult.m_value = rLeft.m_value + rRight.m_value;
	return strResult;
}

namespace stl
{
	//! Specialization of CryBasicString to const char cast.
	template <>
		inline const char* constchar_cast( const CryBasicString &type )
	{
		return type.c_str();
	}
}

#endif