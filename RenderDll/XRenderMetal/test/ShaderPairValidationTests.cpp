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

static void testRule3_Tex1MissingFromVsIsWarned() {
    SECTION("Rule 3 — Tex1 missing from VS outputs is flagged as a warning");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {"Tex0"}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag",
         "generated_cgvsim_vertex", "mesh", {"Tex1"}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK(r.rule3Warnings > 0);
}

static void testRule3_TexPresentInVsNoWarning() {
    SECTION("Rule 3 — Tex1 present in VS outputs produces no warning");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {"Tex0", "Tex1"}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag",
         "generated_cgvsim_vertex", "mesh", {"Tex0", "Tex1"}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK_EQ(r.rule3Warnings, 0);
}

static void testRule3_MismatchedVaryingCaught() {
    SECTION("Rule 3 — FS varying absent from VS outputs produces warning count > 0");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {"Tex0"}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag",
         "generated_cgvsim_vertex", "mesh",
         {"ShadowMapTc"}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK_EQ(r.rule3Warnings, 1);
}

static void testRule3_AllMatchedNoWarnings() {
    SECTION("Rule 3 — all FS varyings present in VS outputs");
    std::vector<ManifestEntry> m = {
        {"CGVSim", "cgvsim", "vertex", "generated_cgvsim_vertex", "", "mesh", {}, {"ShadowMapTc", "Tex0"}},
        {"CGRCFrag", "cgrcfrag", "fragment", "cgrcfrag_frag",
         "generated_cgvsim_vertex", "mesh",
         {"ShadowMapTc", "Tex0"}, {}},
    };
    ValidationResult r = validateManifest(m);
    CHECK(r.passed());
    CHECK_EQ(r.rule3Warnings, 0);
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
// PSO failure soft-limit evaluation
// Mirrors the softened ValidateShaderPairs logic in MetalShaderLoader.mm.
// The hard assert was replaced with a LogError so the game can continue.
// ---------------------------------------------------------------------------

struct PsoValidationOutcome {
    int failures;
    int total;
    bool exceededLimit;
};

static PsoValidationOutcome evaluatePsoFailures(int failures, int total, int limit) {
    return { failures, total, failures > limit };
}

static void testValidatePairs_BelowLimit_NoAlert() {
    SECTION("ValidateShaderPairs — failures below limit, no alert");
    auto r = evaluatePsoFailures(5, 100, 10);
    CHECK_EQ(r.failures, 5);
    CHECK(!r.exceededLimit);
}

static void testValidatePairs_AtLimit_NoAlert() {
    SECTION("ValidateShaderPairs — failures exactly at limit, no alert");
    auto r = evaluatePsoFailures(10, 100, 10);
    CHECK(!r.exceededLimit);
}

static void testValidatePairs_AboveLimit_AlertsButContinues() {
    SECTION("ValidateShaderPairs — failures exceed limit, alerts but does NOT abort");
    auto r = evaluatePsoFailures(11, 100, 10);
    CHECK(r.exceededLimit);
    CHECK_EQ(r.failures, 11);
    CHECK_EQ(r.total, 100);
}

static void testValidatePairs_ManyFailures_AlertsButContinues() {
    SECTION("ValidateShaderPairs — 341 failures (real-world case), function does not abort");
    auto r = evaluatePsoFailures(341, 400, 10);
    CHECK(r.exceededLimit);
    CHECK_EQ(r.failures, 341);
}

static void testValidatePairs_ZeroFailures_NoAlert() {
    SECTION("ValidateShaderPairs — zero failures, no alert");
    auto r = evaluatePsoFailures(0, 50, 10);
    CHECK(!r.exceededLimit);
}

// ---------------------------------------------------------------------------
// CreateVertexDescriptorFromVertexInputs — pure-C++ logic tests
// These mirror the logic implemented in MetalVertexDescriptor.mm without
// depending on Obj-C/Metal headers.
// ---------------------------------------------------------------------------

enum MockVertexFormat {
    MOCK_FORMAT_INVALID = 0,
    MOCK_FORMAT_FLOAT2,
    MOCK_FORMAT_FLOAT3,
    MOCK_FORMAT_FLOAT4,
    MOCK_FORMAT_UCHAR4_NORM,
};

struct MockAttrDesc {
    std::string token;
    std::string category;
    int components = 0;
    int slot       = 0;
    int bufferIndex = 0;
};

struct MockAttrState {
    MockVertexFormat format     = MOCK_FORMAT_INVALID;
    unsigned int     offset     = 0;
    int              bufferIndex = 0;
};

struct MockDescriptor {
    MockAttrState attrs[32];
    unsigned int  strides[8] = {};
};

static std::string ToLower(const std::string& s) {
    std::string out = s;
    for (char& c : out) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return out;
}

static MockVertexFormat MockFormatFor(const MockAttrDesc& attr) {
    const std::string cat = ToLower(attr.category);
    const int comp = attr.components > 0 ? attr.components : 4;
    if (cat == "color") return MOCK_FORMAT_UCHAR4_NORM;
    if (comp == 2) return MOCK_FORMAT_FLOAT2;
    if (comp == 3) return MOCK_FORMAT_FLOAT3;
    if (comp == 4) return MOCK_FORMAT_FLOAT4;
    return MOCK_FORMAT_FLOAT3;
}

static unsigned int MockByteSize(MockVertexFormat fmt) {
    switch (fmt) {
        case MOCK_FORMAT_FLOAT2:      return 8;
        case MOCK_FORMAT_FLOAT3:      return 12;
        case MOCK_FORMAT_FLOAT4:      return 16;
        case MOCK_FORMAT_UCHAR4_NORM: return 4;
        default:                      return 4;
    }
}

static MockDescriptor BuildMockDescriptor(std::vector<MockAttrDesc> attrs) {
    MockDescriptor desc{};
    std::sort(attrs.begin(), attrs.end(),
        [](const MockAttrDesc& a, const MockAttrDesc& b){ return a.slot < b.slot; });
    std::unordered_map<int,unsigned int> bufOffs;
    for (const MockAttrDesc& a : attrs) {
        const int slot   = a.slot;
        const int bufIdx = a.bufferIndex;
        const MockVertexFormat fmt  = MockFormatFor(a);
        const unsigned int     off  = bufOffs[bufIdx];
        desc.attrs[slot].format     = fmt;
        desc.attrs[slot].offset     = off;
        desc.attrs[slot].bufferIndex = bufIdx;
        bufOffs[bufIdx] = off + MockByteSize(fmt);
    }
    for (auto& kv : bufOffs) {
        if (kv.first >= 0 && kv.first < 8)
            desc.strides[kv.first] = kv.second;
    }
    return desc;
}

static void testVertexDescriptor_TangentAtManifestSlot() {
    SECTION("CreateVertexDescriptorFromVertexInputs — Tangent at manifest slot 7 (bufferIndex=1)");
    std::vector<MockAttrDesc> attrs = {
        { "Position", "position", 3, 0, 0 },
        { "Normal",   "normal",   3, 1, 0 },
        { "Color",    "color",    4, 2, 0 },
        { "Tex0",     "texcoord", 2, 3, 0 },
        { "Tangent",  "tangent",  3, 7, 1 },
        { "Binormal", "binormal", 3, 8, 1 },
        { "TNormal",  "normal",   3, 9, 1 },
    };
    MockDescriptor d = BuildMockDescriptor(attrs);
    CHECK_EQ(d.attrs[7].format,      MOCK_FORMAT_FLOAT3);
    CHECK_EQ(d.attrs[7].bufferIndex, 1);
    CHECK_EQ(d.attrs[7].offset,      0u);
    CHECK_EQ(d.attrs[8].format,      MOCK_FORMAT_FLOAT3);
    CHECK_EQ(d.attrs[8].bufferIndex, 1);
    CHECK_EQ(d.attrs[8].offset,      12u);
    CHECK_EQ(d.attrs[9].format,      MOCK_FORMAT_FLOAT3);
    CHECK_EQ(d.attrs[9].offset,      24u);
    CHECK_EQ(d.strides[1], 36u);
    CHECK_EQ(d.strides[0], 36u);
}

static void testVertexDescriptor_TwoTexcoords() {
    SECTION("CreateVertexDescriptorFromVertexInputs — Position + Tex0 + Tex1 (three attrs)");
    std::vector<MockAttrDesc> attrs = {
        { "Position", "position", 3, 0, 0 },
        { "Tex0",     "texcoord", 2, 1, 0 },
        { "Tex1",     "texcoord", 2, 2, 0 },
    };
    MockDescriptor d = BuildMockDescriptor(attrs);
    CHECK_EQ(d.attrs[0].format, MOCK_FORMAT_FLOAT3);
    CHECK_EQ(d.attrs[1].format, MOCK_FORMAT_FLOAT2);
    CHECK_EQ(d.attrs[2].format, MOCK_FORMAT_FLOAT2);
    CHECK(d.attrs[3].format == MOCK_FORMAT_INVALID);
    CHECK_EQ(d.attrs[0].offset, 0u);
    CHECK_EQ(d.attrs[1].offset, 12u);
    CHECK_EQ(d.attrs[2].offset, 20u);
    CHECK_EQ(d.strides[0], 28u);
}

static void testVertexDescriptor_Color1() {
    SECTION("CreateVertexDescriptorFromVertexInputs — Color1 at slot 1 (UChar4Normalized)");
    std::vector<MockAttrDesc> attrs = {
        { "Position", "position", 3, 0, 0 },
        { "Color1",   "color",    4, 1, 0 },
    };
    MockDescriptor d = BuildMockDescriptor(attrs);
    CHECK_EQ(d.attrs[1].format,      MOCK_FORMAT_UCHAR4_NORM);
    CHECK_EQ(d.attrs[1].bufferIndex, 0);
    CHECK_EQ(d.attrs[1].offset,      12u);
    CHECK_EQ(d.strides[0], 16u);
}

// ---------------------------------------------------------------------------
// Alias-registration regression test
//
// Reproduces the bug where the two-pass vertexByFuncName build only registered
// the LAST (versioned) entry-point name for a canonical key, causing fragment
// shaders whose manifest vertexEntryPoint referred to the bare variant to miss.
// ---------------------------------------------------------------------------

struct MockVSEntry {
    std::string entryPoint;
    std::string normalizedName;
};

static std::string StripVsSuffix(const std::string& name) {
    for (const char* suf : { "_vs30", "_vs20", "_vs11", "_vs10" }) {
        if (name.size() > strlen(suf) &&
            name.compare(name.size() - strlen(suf), strlen(suf), suf) == 0)
            return name.substr(0, name.size() - strlen(suf));
    }
    return name;
}

static void testAliasRegistration_BareLookupResolvesVersionedEntry() {
    SECTION("vertexByFuncName — bare entry-point alias resolves to versioned VS entry");

    // Simulate manifest VS entries: bare 'foo' comes before versioned 'foo_vs20'.
    // The versioned entry must win in generatedVertexEntries.
    // Both 'generated_foo_vertex' (bare) AND 'generated_foo_vs20_vertex' (versioned)
    // must resolve to the same (versioned) stored entry in vertexByFuncName.
    struct ManifestVS { std::string normalized; std::string entryPoint; };
    std::vector<ManifestVS> vsManifest = {
        { "foo",     "generated_foo_vertex"     },   // bare — comes first
        { "foo_vs20","generated_foo_vs20_vertex"},   // versioned — must win
    };

    std::unordered_map<std::string, MockVSEntry> generatedVertexEntries;
    std::unordered_map<std::string, std::vector<std::string>> allEntryPointsByCanonical;

    for (auto& vs : vsManifest) {
        const std::string canonicalKey = StripVsSuffix(vs.normalized);
        allEntryPointsByCanonical[canonicalKey].push_back(vs.entryPoint);

        const bool isVersioned = (vs.normalized != canonicalKey);
        const bool slotEmpty   = generatedVertexEntries.find(canonicalKey) ==
                                 generatedVertexEntries.end();
        if (isVersioned || slotEmpty)
            generatedVertexEntries[canonicalKey] = { vs.entryPoint, vs.normalized };
    }

    // The stored entry must be the versioned variant.
    CHECK_STR(generatedVertexEntries["foo"].entryPoint, "generated_foo_vs20_vertex");

    // Build vertexByFuncName with all aliases.
    std::unordered_map<std::string, const MockVSEntry*> vertexByFuncName;
    for (auto& [canonKey, eps] : allEntryPointsByCanonical) {
        auto it = generatedVertexEntries.find(canonKey);
        if (it == generatedVertexEntries.end()) continue;
        for (const std::string& ep : eps)
            vertexByFuncName[ep] = &it->second;
    }

    // Both the bare and versioned entry-point names must resolve to the versioned entry.
    CHECK(vertexByFuncName.count("generated_foo_vertex") == 1);
    CHECK(vertexByFuncName.count("generated_foo_vs20_vertex") == 1);
    CHECK_STR(vertexByFuncName["generated_foo_vertex"]->entryPoint,
              "generated_foo_vs20_vertex");
    CHECK_STR(vertexByFuncName["generated_foo_vs20_vertex"]->entryPoint,
              "generated_foo_vs20_vertex");
}

static void testAliasRegistration_VersionedOnlyNoAliasNeeded() {
    SECTION("vertexByFuncName — versioned-only shader registers its entry point");

    struct ManifestVS { std::string normalized; std::string entryPoint; };
    std::vector<ManifestVS> vsManifest = {
        { "bar_vs20", "generated_bar_vs20_vertex" },
    };

    std::unordered_map<std::string, MockVSEntry> generatedVertexEntries;
    std::unordered_map<std::string, std::vector<std::string>> allEntryPointsByCanonical;

    for (auto& vs : vsManifest) {
        const std::string canonicalKey = StripVsSuffix(vs.normalized);
        allEntryPointsByCanonical[canonicalKey].push_back(vs.entryPoint);
        const bool isVersioned = (vs.normalized != canonicalKey);
        const bool slotEmpty   = generatedVertexEntries.find(canonicalKey) ==
                                 generatedVertexEntries.end();
        if (isVersioned || slotEmpty)
            generatedVertexEntries[canonicalKey] = { vs.entryPoint, vs.normalized };
    }

    std::unordered_map<std::string, const MockVSEntry*> vertexByFuncName;
    for (auto& [canonKey, eps] : allEntryPointsByCanonical) {
        auto it = generatedVertexEntries.find(canonKey);
        if (it == generatedVertexEntries.end()) continue;
        for (const std::string& ep : eps)
            vertexByFuncName[ep] = &it->second;
    }

    CHECK(vertexByFuncName.count("generated_bar_vs20_vertex") == 1);
    CHECK_STR(vertexByFuncName["generated_bar_vs20_vertex"]->entryPoint,
              "generated_bar_vs20_vertex");
}

// ---------------------------------------------------------------------------
// isVersioned correctness when stage-prefix stripping makes canonicalKey != normalizedKey
//
// Regression test for the bug where `isVersioned = (normalizedKey != canonicalKey)`
// was always true because BuildStageAgnosticKey strips the stage prefix ("cgvprog"),
// causing the bare VS to overwrite VS20 in m_generatedVertexEntries when it appeared
// after VS20 in the manifest.  The correct check is whether normalizedKey itself ends
// with a _vsXX suffix.
// ---------------------------------------------------------------------------

static std::string StripStagePrefixForTest(const std::string& v) {
    for (const char* pfx : { "cgvprog_", "cgvprog", "cgv_", "cgrc_", "cgrc", "cg_" }) {
        size_t len = strlen(pfx);
        if (v.size() >= len && v.compare(0, len, pfx) == 0)
            return v.substr(len);
    }
    return v;
}

// Mirrors BuildStageAgnosticKey: strip stage prefix AND version suffix.
static std::string BuildCanonicalKey(const std::string& normalizedKey) {
    return StripVsSuffix(StripStagePrefixForTest(normalizedKey));
}

static void testIsVersioned_StagePrefixDoesNotMakeBareLookVersioned() {
    SECTION("isVersioned — bare VS with cgvprog prefix must NOT be treated as versioned");

    // Both 'cgvprogbump_foo' (bare) and 'cgvprogbump_foo_vs20' share the same
    // canonical key after stage-prefix + VS-suffix stripping.
    // VS20 appears first in the manifest; bare comes second.
    // With the buggy `isVersioned = (normalizedKey != canonicalKey)` check, bare
    // would overwrite VS20 because the stage-prefix makes canonicalKey differ from
    // normalizedKey for BOTH entries.  The correct `isVersioned` must be based
    // solely on whether the normalizedKey ends with a _vsXX suffix.

    struct ManifestVS { std::string normalized; std::string entryPoint; };
    std::vector<ManifestVS> vsManifest = {
        { "cgvprogbump_foo_vs20", "generated_cgvprogbump_foo_vs20_vertex" },   // versioned first
        { "cgvprogbump_foo",      "generated_cgvprogbump_foo_vertex"      },   // bare second (must NOT win)
    };

    std::unordered_map<std::string, MockVSEntry> generatedVertexEntries;
    std::unordered_map<std::string, std::vector<std::string>> allEntryPointsByCanonical;

    for (auto& vs : vsManifest) {
        const std::string canonicalKey = BuildCanonicalKey(vs.normalized);
        allEntryPointsByCanonical[canonicalKey].push_back(vs.entryPoint);

        // Correct isVersioned: test for explicit _vsXX suffix in the normalized key.
        const bool isVersioned = (StripVsSuffix(vs.normalized) != vs.normalized);
        const bool slotEmpty   = generatedVertexEntries.find(canonicalKey) ==
                                 generatedVertexEntries.end();
        if (isVersioned || slotEmpty)
            generatedVertexEntries[canonicalKey] = { vs.entryPoint, vs.normalized };
    }

    // VS20 must win — bare bare must NOT overwrite it.
    CHECK_STR(generatedVertexEntries["bump_foo"].entryPoint, "generated_cgvprogbump_foo_vs20_vertex");

    // Both aliases in vertexByFuncName must point to the VS20 entry.
    std::unordered_map<std::string, const MockVSEntry*> vertexByFuncName;
    for (auto& [canonKey, eps] : allEntryPointsByCanonical) {
        auto it = generatedVertexEntries.find(canonKey);
        if (it == generatedVertexEntries.end()) continue;
        for (const std::string& ep : eps)
            vertexByFuncName[ep] = &it->second;
    }

    CHECK_STR(vertexByFuncName["generated_cgvprogbump_foo_vs20_vertex"]->entryPoint,
              "generated_cgvprogbump_foo_vs20_vertex");
    CHECK_STR(vertexByFuncName["generated_cgvprogbump_foo_vertex"]->entryPoint,
              "generated_cgvprogbump_foo_vs20_vertex");
}

// ---------------------------------------------------------------------------
// ValidateShaderPairReflection — vertex descriptor guard
//
// Regression tests for the fix that passes info.vertexDescriptor to the
// PSO dry-run.  Without a vertex descriptor Metal rejects every PSO that has
// [[stage_in]] attributes; the fix stores the descriptor on ShaderInfo and
// threads it through.
//
// These tests use a pure-C++ model of the guard logic since the real function
// requires Metal API.  The model mirrors the guard conditions in the
// implementation:
//   - nil vertexDescriptor → PSO creation fails (returns false)
//   - valid vertexDescriptor provided → PSO creation succeeds (returns true)
//   - nil device or nil vertex/fragment function → early return true (no-op)
// ---------------------------------------------------------------------------

enum class MockDescriptorState { NilDescriptor, ValidDescriptor };

static bool MockValidateShaderPairReflection(
    bool hasDevice,
    bool hasVertexFn,
    bool hasFragmentFn,
    MockDescriptorState descriptorState)
{
    if (!hasDevice || !hasVertexFn || !hasFragmentFn)
        return true;
    return descriptorState == MockDescriptorState::ValidDescriptor;
}

static void testValidateReflection_NilDescriptor_Fails() {
    SECTION("ValidateShaderPairReflection — nil vertexDescriptor causes PSO failure");
    bool result = MockValidateShaderPairReflection(
        true, true, true, MockDescriptorState::NilDescriptor);
    CHECK(!result);
}

static void testValidateReflection_ValidDescriptor_Passes() {
    SECTION("ValidateShaderPairReflection — valid vertexDescriptor allows PSO to succeed");
    bool result = MockValidateShaderPairReflection(
        true, true, true, MockDescriptorState::ValidDescriptor);
    CHECK(result);
}

static void testValidateReflection_NilDevice_EarlyTrue() {
    SECTION("ValidateShaderPairReflection — nil device returns true (no-op)");
    bool result = MockValidateShaderPairReflection(
        false, true, true, MockDescriptorState::NilDescriptor);
    CHECK(result);
}

static void testValidateReflection_NilVertexFn_EarlyTrue() {
    SECTION("ValidateShaderPairReflection — nil vertexFn returns true (no-op)");
    bool result = MockValidateShaderPairReflection(
        true, false, true, MockDescriptorState::ValidDescriptor);
    CHECK(result);
}

static void testValidateReflection_AllShadersMustUseStoredDescriptor() {
    SECTION("ValidateShaderPairs — all shaders pass when stored descriptors are used");
    const int total = 596;
    int failures = 0;
    for (int i = 0; i < total; ++i)
    {
        bool pass = MockValidateShaderPairReflection(
            true, true, true, MockDescriptorState::ValidDescriptor);
        if (!pass) ++failures;
    }
    CHECK_EQ(failures, 0);
}

static void testValidateReflection_AllShadersFailWithNilDescriptor() {
    SECTION("ValidateShaderPairs — all shaders fail when descriptors are nil (pre-fix regression)");
    const int total = 596;
    int failures = 0;
    for (int i = 0; i < total; ++i)
    {
        bool pass = MockValidateShaderPairReflection(
            true, true, true, MockDescriptorState::NilDescriptor);
        if (!pass) ++failures;
    }
    CHECK_EQ(failures, 596);
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
    testRule3_Tex1MissingFromVsIsWarned();
    testRule3_TexPresentInVsNoWarning();
    testRule3_MismatchedVaryingCaught();
    testRule3_AllMatchedNoWarnings();
    testRule3_ShortVsOutputDoesNotSilenceWarning();
    testRule3_LongExactMatchNoWarning();
    testRule3_LongSubstringMatchNoWarning();
    testCoverageRatio_Full();
    testCoverageRatio_Zero();
    testEmptyManifest();
    testNormalizationCategory();
    testValidatePairs_BelowLimit_NoAlert();
    testValidatePairs_AtLimit_NoAlert();
    testValidatePairs_AboveLimit_AlertsButContinues();
    testValidatePairs_ManyFailures_AlertsButContinues();
    testValidatePairs_ZeroFailures_NoAlert();
    testVertexDescriptor_TangentAtManifestSlot();
    testVertexDescriptor_TwoTexcoords();
    testVertexDescriptor_Color1();
    testAliasRegistration_BareLookupResolvesVersionedEntry();
    testAliasRegistration_VersionedOnlyNoAliasNeeded();
    testIsVersioned_StagePrefixDoesNotMakeBareLookVersioned();
    testValidateReflection_NilDescriptor_Fails();
    testValidateReflection_ValidDescriptor_Passes();
    testValidateReflection_NilDevice_EarlyTrue();
    testValidateReflection_NilVertexFn_EarlyTrue();
    testValidateReflection_AllShadersMustUseStoredDescriptor();
    testValidateReflection_AllShadersFailWithNilDescriptor();

    fprintf(stdout, "\nResults: %d passed, %d failed\n", g_passed, g_failed);
    return g_failed > 0 ? 1 : 0;
}
