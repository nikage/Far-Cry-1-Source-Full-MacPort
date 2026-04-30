// Unit tests for shader pair validation logic.
// Tests the manifest-based pairing rules without requiring Metal API or a GPU.
//
// Build: clang++ -std=c++17 -o shader_pair_validation_tests ShaderPairValidationTests.cpp && ./shader_pair_validation_tests
//
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

// ---------------------------------------------------------------------------
// Minimal test harness
// ---------------------------------------------------------------------------
static int g_passed = 0;
static int g_failed = 0;

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);   \
            ++g_failed;                                                        \
        } else {                                                               \
            ++g_passed;                                                        \
        }                                                                      \
    } while (0)

#define CHECK_EQ(a, b) CHECK((a) == (b))
#define CHECK_STR(a, b) CHECK(std::string(a) == std::string(b))
#define SECTION(name) fprintf(stdout, "\n--- %s ---\n", (name))

// ---------------------------------------------------------------------------
// Re-implementation of the manifest validation logic (pure C++, no ObjC/Metal)
// Mirrors the logic in pair_validator.dart and the runtime ValidateShaderPairs.
// ---------------------------------------------------------------------------

struct ManifestEntry {
    std::string shader;
    std::string normalized;
    std::string stage;         // "vertex" or "fragment"
    std::string entryPoint;
    std::string vertexEntryPoint;
    std::string pipelineCategory;
    std::vector<std::string> vertexAttributes;
    std::vector<std::string> vertexOutputNames;
};

struct ValidationResult {
    int rule1Errors      = 0;
    int rule2Errors      = 0;
    int rule3Warnings    = 0;
    int totalFragments   = 0;
    int pairedFragments  = 0;
    int fullscreenCount  = 0;

    bool passed() const { return rule1Errors == 0 && rule2Errors == 0; }
    double coverageRatio() const {
        if (totalFragments == 0) return 1.0;
        return static_cast<double>(pairedFragments + fullscreenCount) / totalFragments;
    }
};

static bool isCgSemantic(const std::string& attr) {
    static const char* prefixes[] = {
        "POSITION", "TEXCOORD", "COLOR", "NORMAL",
        "BINORMAL", "TANGENT", "BLENDWEIGHT", "BLENDINDICES",
        nullptr
    };
    for (int i = 0; prefixes[i]; ++i) {
        if (attr.find(prefixes[i]) == 0)
            return true;
    }
    return false;
}

static ValidationResult validateManifest(const std::vector<ManifestEntry>& entries) {
    ValidationResult result;

    std::unordered_set<std::string> vertexEPs;
    std::unordered_map<std::string, const ManifestEntry*> vertexByEP;

    for (const auto& e : entries) {
        if (e.stage == "vertex") {
            vertexEPs.insert(e.entryPoint);
            vertexByEP[e.entryPoint] = &e;
        }
    }

    for (const auto& e : entries) {
        if (e.stage != "fragment") continue;
        result.totalFragments++;

        if (!e.vertexEntryPoint.empty()) {
            result.pairedFragments++;

            // Rule 2: vertexEntryPoint must reference an existing vertex entry.
            if (vertexEPs.find(e.vertexEntryPoint) == vertexEPs.end()) {
                result.rule2Errors++;
            } else {
                // Rule 3: structural compatibility check.
                auto it = vertexByEP.find(e.vertexEntryPoint);
                if (it != vertexByEP.end()) {
                    const ManifestEntry* vert = it->second;
                    std::unordered_set<std::string> vsOutLower;
                    for (const auto& out : vert->vertexOutputNames)
                        vsOutLower.insert(std::string(out.begin(), out.end()));

                    for (const auto& attr : e.vertexAttributes) {
                        if (isCgSemantic(attr)) continue;
                        std::string lower(attr.begin(), attr.end());
                        bool found = false;
                        for (const auto& o : vsOutLower) {
                            bool exactMatch = (o == lower);
                            bool substringMatch = (o.size() > 4 && lower.size() > 4 &&
                                                   lower.find(o) != std::string::npos);
                            if (exactMatch || substringMatch) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) result.rule3Warnings++;
                    }
                }
            }
        } else if (e.pipelineCategory == "fullscreen") {
            result.fullscreenCount++;
        } else {
            // Rule 1: non-fullscreen fragment must have a vertexEntryPoint.
            result.rule1Errors++;
        }
    }

    return result;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static void testRule1_AllPaired() {
    SECTION("Rule 1 — all fragments paired");
    std::vector<ManifestEntry> m = {
        {"CGVSimple", "cgvsimple", "vertex", "generated_cgvsimple_vertex", "", "mesh", {}, {"Tex0"}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag", "generated_cgvsimple_vertex", "mesh", {}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK_EQ(r.rule1Errors, 0);
    CHECK_EQ(r.pairedFragments, 1);
    CHECK_EQ(r.totalFragments, 1);
}

static void testRule1_FullscreenExempt() {
    SECTION("Rule 1 — fullscreen fragment exempt from pairing");
    std::vector<ManifestEntry> m = {
        {"CGRC_HDR_Bloom_PS20", "cgrc_hdr_bloom_ps20", "fragment", "bloom_frag", "", "fullscreen", {}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK_EQ(r.rule1Errors, 0);
    CHECK_EQ(r.fullscreenCount, 1);
    CHECK_EQ(r.pairedFragments, 0);
}

static void testRule1_UnpairedMeshFails() {
    SECTION("Rule 1 — unpaired mesh fragment emits error");
    std::vector<ManifestEntry> m = {
        {"CGRCMesh", "cgrcmesh", "fragment", "cgrcmesh_frag", "", "mesh", {}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(!r.passed());
    CHECK_EQ(r.rule1Errors, 1);
}

static void testRule1_MultipleUnpairedAllFail() {
    SECTION("Rule 1 — multiple unpaired non-fullscreen fragments");
    std::vector<ManifestEntry> m = {
        {"CGRCAlpha", "cgrcalpha", "fragment", "cgrcalpha_frag", "", "mesh", {}, {}},
        {"CGRCShadow", "cgrcshadow", "fragment", "cgrcshadow_frag", "", "shadow", {}, {}},
        {"CGRC_HDR_A", "cgrc_hdr_a", "fragment", "cgrc_hdr_a_frag", "", "fullscreen", {}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(!r.passed());
    CHECK_EQ(r.rule1Errors, 2);
    CHECK_EQ(r.fullscreenCount, 1);
    CHECK_EQ(r.totalFragments, 3);
}

static void testRule2_ValidReference() {
    SECTION("Rule 2 — valid vertexEntryPoint reference");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag", "generated_cgvsim_vertex", "mesh", {}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK_EQ(r.rule2Errors, 0);
}

static void testRule2_InvalidReferenceFails() {
    SECTION("Rule 2 — dangling vertexEntryPoint emits error");
    std::vector<ManifestEntry> m = {
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag", "generated_doesnotexist_vertex", "mesh", {}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(!r.passed());
    CHECK_EQ(r.rule2Errors, 1);
}

static void testRule3_SemanticAttrsIgnored() {
    SECTION("Rule 3 — CG semantic attributes not flagged as missing");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {"Tex0"}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag",
         "generated_cgvsim_vertex", "mesh",
         {"POSITION_3", "TEXCOORD0_2", "COLOR_4"}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK_EQ(r.rule3Warnings, 0);
}

static void testRule3_MissingVaryingWarns() {
    SECTION("Rule 3 — custom varying missing from VS outputs produces warning");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {"Tex0"}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag",
         "generated_cgvsim_vertex", "mesh",
         {"ShadowTc", "ReflMap"}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK(r.rule3Warnings > 0);
}

static void testCoverageRatio_Full() {
    SECTION("Coverage — 100% when all fragments paired or fullscreen");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {}},
        {"CGRCPaired", "cgrcpaired", "fragment", "cgrcpaired_frag", "generated_cgvsim_vertex", "mesh", {}, {}},
        {"CGRC_HDR_A", "cgrc_hdr_a", "fragment", "cgrc_hdr_a_frag", "", "fullscreen", {}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK_EQ(r.totalFragments, 2);
    CHECK_EQ(r.pairedFragments, 1);
    CHECK_EQ(r.fullscreenCount, 1);
    CHECK(r.coverageRatio() >= 1.0 - 1e-6);
}

static void testCoverageRatio_Zero() {
    SECTION("Coverage — 0% when all fragments unpaired mesh");
    std::vector<ManifestEntry> m = {
        {"CGRCA", "cgrca", "fragment", "cgrca_frag", "", "mesh", {}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.coverageRatio() < 1e-6);
}

static void testEmptyManifest() {
    SECTION("Empty manifest passes all rules");
    ValidationResult r = validateManifest({});
    CHECK(r.passed());
    CHECK_EQ(r.totalFragments, 0);
    CHECK(r.coverageRatio() >= 1.0 - 1e-6);
}

static void testNormalizationCategory() {
    SECTION("pipelineCategory affects Rule 1 (shadow not fullscreen)");
    std::vector<ManifestEntry> m = {
        {"CGRCShadow", "cgrcshadow", "fragment", "cgrcshadow_frag", "", "shadow", {}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(!r.passed());
    CHECK_EQ(r.rule1Errors, 1);
}

static void testRule3_ShortVsOutputDoesNotSilenceWarning() {
    SECTION("Rule 3 — short VS output (<= 4 chars) does not suppress warning for unrelated FS varying");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {"tc"}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag",
         "generated_cgvsim_vertex", "mesh",
         {"ShadowTc"}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    // "tc" is <= 4 chars so it must NOT cover "ShadowTc" via substring.
    CHECK(r.rule3Warnings > 0);
}

static void testRule3_LongExactMatchNoWarning() {
    SECTION("Rule 3 — exact match between VS output and FS varying produces no warning");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {"ShadowTc"}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag",
         "generated_cgvsim_vertex", "mesh",
         {"ShadowTc"}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK_EQ(r.rule3Warnings, 0);
}

static void testRule3_LongSubstringMatchNoWarning() {
    SECTION("Rule 3 — FS varying contains VS output as substring (both > 4 chars) produces no warning");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {"ShadowMap"}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag",
         "generated_cgvsim_vertex", "mesh",
         {"ShadowMapTc"}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK_EQ(r.rule3Warnings, 0);
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main() {
    testRule1_AllPaired();
    testRule1_FullscreenExempt();
    testRule1_UnpairedMeshFails();
    testRule1_MultipleUnpairedAllFail();
    testRule2_ValidReference();
    testRule2_InvalidReferenceFails();
    testRule3_SemanticAttrsIgnored();
    testRule3_MissingVaryingWarns();
    testRule3_ShortVsOutputDoesNotSilenceWarning();
    testRule3_LongExactMatchNoWarning();
    testRule3_LongSubstringMatchNoWarning();
    testCoverageRatio_Full();
    testCoverageRatio_Zero();
    testEmptyManifest();
    testNormalizationCategory();

    fprintf(stdout, "\nResults: %d passed, %d failed\n", g_passed, g_failed);
    return g_failed > 0 ? 1 : 0;
}
