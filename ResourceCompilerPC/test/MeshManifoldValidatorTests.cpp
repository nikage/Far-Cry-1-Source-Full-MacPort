// Standalone unit tests for MeshManifoldValidator.
// No engine dependencies — compiles with plain clang++.
//
// Build & run:
//   clang++ -std=c++17 -I../.. -o mesh_manifold_validator_tests MeshManifoldValidatorTests.cpp && ./mesh_manifold_validator_tests
//
#include <cassert>
#include <cstdio>
#include <vector>

#include "CryCommon/MeshManifoldValidator.h"

// ---------------------------------------------------------------------------
// Minimal test harness
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond)                                                    \
    do {                                                               \
        if (cond) {                                                    \
            ++g_passed;                                                \
        } else {                                                       \
            ++g_failed;                                                \
            printf("FAIL  %s:%d  %s\n", __FILE__, __LINE__, #cond);   \
        }                                                              \
    } while (0)

#define CHECK_EQ(a, b)                                                         \
    do {                                                                       \
        auto _a = (a); auto _b = (b);                                          \
        if (_a == _b) {                                                        \
            ++g_passed;                                                        \
        } else {                                                               \
            ++g_failed;                                                        \
            printf("FAIL  %s:%d  %s == %s  (%d != %d)\n",                     \
                   __FILE__, __LINE__, #a, #b, (int)_a, (int)_b);             \
        }                                                                      \
    } while (0)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static std::vector<unsigned short> makeTri(unsigned short a, unsigned short b,
                                           unsigned short c)
{
    return {a, b, c};
}

// Append triangle to flat index buffer.
static void addTri(std::vector<unsigned short>& buf,
                   unsigned short a, unsigned short b, unsigned short c)
{
    buf.push_back(a);
    buf.push_back(b);
    buf.push_back(c);
}

// ---------------------------------------------------------------------------
// FindNonManifoldEdges tests
// ---------------------------------------------------------------------------

static void test_manifold_mesh_has_no_violations()
{
    // Two triangles sharing one edge — manifold.
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 2);
    addTri(idx, 1, 3, 2);
    auto v = MeshManifold::FindNonManifoldEdges(idx.data(), (int)idx.size());
    CHECK(v.empty());
}

static void test_single_triangle_has_no_violations()
{
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 2);
    auto v = MeshManifold::FindNonManifoldEdges(idx.data(), (int)idx.size());
    CHECK(v.empty());
}

static void test_three_tris_on_one_edge_is_detected()
{
    // Edge (0,1) shared by three triangles.
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 2);
    addTri(idx, 0, 1, 3);
    addTri(idx, 0, 1, 4);
    auto v = MeshManifold::FindNonManifoldEdges(idx.data(), (int)idx.size());
    CHECK_EQ(v.size(), 1u);
    if (!v.empty())
    {
        const unsigned short lo = std::min(v[0].v0, v[0].v1);
        const unsigned short hi = std::max(v[0].v0, v[0].v1);
        CHECK_EQ(lo, 0);
        CHECK_EQ(hi, 1);
        CHECK_EQ(v[0].faceCount, 3);
    }
}

static void test_four_tris_on_one_edge_reports_count_4()
{
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 2);
    addTri(idx, 0, 1, 3);
    addTri(idx, 1, 0, 4); // reversed winding — same undirected edge
    addTri(idx, 0, 1, 5);
    auto v = MeshManifold::FindNonManifoldEdges(idx.data(), (int)idx.size());
    CHECK_EQ(v.size(), 1u);
    if (!v.empty())
        CHECK_EQ(v[0].faceCount, 4);
}

static void test_two_distinct_non_manifold_edges_both_detected()
{
    // Edge (0,1) has 3 faces, edge (2,3) has 3 faces.
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 10);
    addTri(idx, 0, 1, 11);
    addTri(idx, 0, 1, 12);
    addTri(idx, 2, 3, 20);
    addTri(idx, 2, 3, 21);
    addTri(idx, 2, 3, 22);
    auto v = MeshManifold::FindNonManifoldEdges(idx.data(), (int)idx.size());
    CHECK_EQ(v.size(), 2u);
}

static void test_empty_buffer_has_no_violations()
{
    auto v = MeshManifold::FindNonManifoldEdges(nullptr, 0);
    CHECK(v.empty());
}

static void test_degenerate_triangles_ignored()
{
    // Degenerate (v0 == v1) should not contribute edge counts.
    std::vector<unsigned short> idx;
    addTri(idx, 0, 0, 2);
    addTri(idx, 0, 0, 3);
    addTri(idx, 0, 0, 4);
    auto v = MeshManifold::FindNonManifoldEdges(idx.data(), (int)idx.size());
    CHECK(v.empty());
}

// ---------------------------------------------------------------------------
// RemoveNonManifoldFaces tests
// ---------------------------------------------------------------------------

static void test_remove_does_nothing_on_manifold_mesh()
{
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 2);
    addTri(idx, 1, 3, 2);
    int count = (int)idx.size();
    int removed = MeshManifold::RemoveNonManifoldFaces(idx.data(), count);
    CHECK_EQ(removed, 0);
    CHECK_EQ(count, 6);
}

static void test_remove_excess_face_from_triple_edge()
{
    // Three tris on edge (0,1): first two kept, third removed.
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 2);
    addTri(idx, 0, 1, 3);
    addTri(idx, 0, 1, 4); // excess — should be removed
    int count = (int)idx.size();
    int removed = MeshManifold::RemoveNonManifoldFaces(idx.data(), count);
    CHECK_EQ(removed, 1);
    CHECK_EQ(count, 6); // 2 faces × 3 indices
    // Remaining faces are the first two.
    CHECK_EQ(idx[0], 0); CHECK_EQ(idx[1], 1); CHECK_EQ(idx[2], 2);
    CHECK_EQ(idx[3], 0); CHECK_EQ(idx[4], 1); CHECK_EQ(idx[5], 3);
}

static void test_remove_two_excess_faces_from_quad_edge()
{
    // Four tris on edge (0,1): first two kept, two removed.
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 2);
    addTri(idx, 0, 1, 3);
    addTri(idx, 0, 1, 4);
    addTri(idx, 0, 1, 5);
    int count = (int)idx.size();
    int removed = MeshManifold::RemoveNonManifoldFaces(idx.data(), count);
    CHECK_EQ(removed, 2);
    CHECK_EQ(count, 6);
}

static void test_result_is_manifold_after_repair()
{
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 2);
    addTri(idx, 0, 1, 3);
    addTri(idx, 0, 1, 4);
    int count = (int)idx.size();
    MeshManifold::RemoveNonManifoldFaces(idx.data(), count);
    auto v = MeshManifold::FindNonManifoldEdges(idx.data(), count);
    CHECK(v.empty());
}

static void test_remove_does_nothing_on_empty_buffer()
{
    int count = 0;
    int removed = MeshManifold::RemoveNonManifoldFaces(nullptr, count);
    CHECK_EQ(removed, 0);
    CHECK_EQ(count, 0);
}

static void test_unrelated_faces_preserved_after_repair()
{
    // Non-manifold edge (0,1) plus two fully-independent triangles.
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 2);
    addTri(idx, 0, 1, 3);
    addTri(idx, 0, 1, 4); // excess
    addTri(idx, 10, 11, 12);
    addTri(idx, 20, 21, 22);
    int count = (int)idx.size();
    int removed = MeshManifold::RemoveNonManifoldFaces(idx.data(), count);
    CHECK_EQ(removed, 1);
    CHECK_EQ(count, 12); // 4 remaining faces
    auto v = MeshManifold::FindNonManifoldEdges(idx.data(), count);
    CHECK(v.empty());
}

static void test_reversed_winding_same_edge_detected()
{
    // (0,1,2), (1,0,3): FindEdgeInfo treats (0,1) and (1,0) as the same edge.
    std::vector<unsigned short> idx;
    addTri(idx, 0, 1, 2);
    addTri(idx, 1, 0, 3);
    addTri(idx, 0, 1, 4); // third face on undirected edge (0,1)
    int count = (int)idx.size();
    auto violations = MeshManifold::FindNonManifoldEdges(idx.data(), count);
    CHECK_EQ(violations.size(), 1u);
    int removed = MeshManifold::RemoveNonManifoldFaces(idx.data(), count);
    CHECK_EQ(removed, 1);
    CHECK_EQ(count, 6);
}

// ---------------------------------------------------------------------------
// EdgeKey symmetry test
// ---------------------------------------------------------------------------

static void test_edge_key_is_symmetric()
{
    CHECK_EQ(MeshManifold::EdgeKey(3, 7), MeshManifold::EdgeKey(7, 3));
    CHECK_EQ(MeshManifold::EdgeKey(0, 65535), MeshManifold::EdgeKey(65535, 0));
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main()
{
    test_manifold_mesh_has_no_violations();
    test_single_triangle_has_no_violations();
    test_three_tris_on_one_edge_is_detected();
    test_four_tris_on_one_edge_reports_count_4();
    test_two_distinct_non_manifold_edges_both_detected();
    test_empty_buffer_has_no_violations();
    test_degenerate_triangles_ignored();

    test_remove_does_nothing_on_manifold_mesh();
    test_remove_excess_face_from_triple_edge();
    test_remove_two_excess_faces_from_quad_edge();
    test_result_is_manifold_after_repair();
    test_remove_does_nothing_on_empty_buffer();
    test_unrelated_faces_preserved_after_repair();
    test_reversed_winding_same_edge_detected();

    test_edge_key_is_symmetric();

    printf("\n%d passed, %d failed\n", g_passed, g_failed);
    return g_failed ? 1 : 0;
}
