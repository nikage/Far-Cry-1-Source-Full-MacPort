#pragma once

#include <algorithm>
#include <cstdint>
#include <unordered_map>
#include <vector>

struct ManifoldViolation
{
    unsigned short v0;
    unsigned short v1;
    int            faceCount;
};

namespace MeshManifold
{

inline uint32_t EdgeKey(unsigned short a, unsigned short b)
{
    if (a > b)
        std::swap(a, b);
    return (static_cast<uint32_t>(a) << 16) | static_cast<uint32_t>(b);
}

// Returns every undirected edge that has more than 2 incident triangles.
// indexCount must be a multiple of 3 (triangle list).
inline std::vector<ManifoldViolation> FindNonManifoldEdges(
    const unsigned short* indices, int indexCount)
{
    const int numFaces = indexCount / 3;

    std::unordered_map<uint32_t, int> edgeCount;
    edgeCount.reserve(numFaces * 2);

    for (int i = 0; i < numFaces; ++i)
    {
        const unsigned short v0 = indices[i * 3 + 0];
        const unsigned short v1 = indices[i * 3 + 1];
        const unsigned short v2 = indices[i * 3 + 2];
        if (v0 == v1 || v1 == v2 || v0 == v2)
            continue;
        edgeCount[EdgeKey(v0, v1)]++;
        edgeCount[EdgeKey(v1, v2)]++;
        edgeCount[EdgeKey(v2, v0)]++;
    }

    std::vector<ManifoldViolation> violations;
    for (const auto& kv : edgeCount)
    {
        if (kv.second > 2)
        {
            ManifoldViolation mv;
            mv.v0        = static_cast<unsigned short>(kv.first >> 16);
            mv.v1        = static_cast<unsigned short>(kv.first & 0xFFFFu);
            mv.faceCount = kv.second;
            violations.push_back(mv);
        }
    }
    return violations;
}

// Removes the 3rd+ faces on every non-manifold edge in-place.
// The buffer is compacted; indexCount is updated to the new (smaller) multiple of 3.
// Returns the number of removed faces (0 means the mesh was already manifold).
// indexCount must be a multiple of 3 (triangle list).
inline int RemoveNonManifoldFaces(unsigned short* indices, int& indexCount)
{
    const int numFaces = indexCount / 3;
    if (numFaces == 0)
        return 0;

    // Map each edge to the ordered list of face indices that use it.
    // We use a vector to preserve iteration order so that face0/face1 in the
    // NvStripifier sense are kept and only the 3rd+ are removed.
    std::unordered_map<uint32_t, std::vector<int>> edgeFaces;
    edgeFaces.reserve(numFaces * 2);

    for (int i = 0; i < numFaces; ++i)
    {
        const unsigned short v0 = indices[i * 3 + 0];
        const unsigned short v1 = indices[i * 3 + 1];
        const unsigned short v2 = indices[i * 3 + 2];
        if (v0 == v1 || v1 == v2 || v0 == v2)
            continue;
        edgeFaces[EdgeKey(v0, v1)].push_back(i);
        edgeFaces[EdgeKey(v1, v2)].push_back(i);
        edgeFaces[EdgeKey(v2, v0)].push_back(i);
    }

    std::vector<bool> removeFace(numFaces, false);
    for (const auto& kv : edgeFaces)
    {
        const std::vector<int>& faces = kv.second;
        for (int j = 2; j < static_cast<int>(faces.size()); ++j)
            removeFace[faces[j]] = true;
    }

    int write = 0, removed = 0;
    for (int i = 0; i < numFaces; ++i)
    {
        if (!removeFace[i])
        {
            if (write != i)
            {
                indices[write * 3 + 0] = indices[i * 3 + 0];
                indices[write * 3 + 1] = indices[i * 3 + 1];
                indices[write * 3 + 2] = indices[i * 3 + 2];
            }
            ++write;
        }
        else
        {
            ++removed;
        }
    }
    indexCount = write * 3;
    return removed;
}

} // namespace MeshManifold
