/// Parser and resolver for CryEngine CustomAliases.txt shader alias tables.
///
/// **Aliases.txt** (engine `Shaders/Aliases.txt`) is a flat tab/space–separated
/// table: `AliasName  TargetName`. The Metal generator folds these into each
/// manifest fragment entry's `lookupAliases` so runtime resolves legacy names
/// without a C++ fallback table.
///
/// The file consists of conditional blocks:
///   { <cvar|GPU> = <value>
///     AliasName  TargetName  [; optional comment]
///     ...
///   }
///
/// This library:
///   1. Parses every alias pair from every block (regardless of condition).
///   2. Resolves each pair's target to a canonical Metal shader name by
///      consulting a set of generated manifest names and the known builtins.
///   3. Returns [AuditResult] records describing each alias.
library alias_auditor;

/// Metal built-in shader names that exist without being in the manifest.
const Set<String> kMetalBuiltins = {
  'basic',
  'colortex',
  'terrain',
  'sky',
  'simple',
  'color',
  'unlit',
};

/// Intermediate alias targets (normalized → builtin or manifest name).
/// We resolve through these so that alias chains like
///   TerrainLake → LowSpecWaterOutdoor_FP → cgrclowmedwater
/// can be fully resolved.
const Map<String, String> kIntermediateAliases = {
  'lowspecwateroutdoor_fp': 'cgrclowmedwater',
  'lowspecwaterindoor_fp': 'cgrcindoorwater',
  'lavavolume': 'terrain',
  'terrain_fp': 'terrain',
  'terrainshadowpass_fp': 'terrain',
  'terrainlowlod_fp': 'terrain',
  'terrainwaterbeach_fp': 'terrain',
  'terrainwaterbottom_fp': 'terrain',
  'terrainwaterbottomsimple_fp': 'terrain',
  'terrainwithdefaultdetailtexture_fp': 'terrain',
  'cgrcterra': 'terrain',
};

const Map<String, String> kAliasesTxtTargetToManifestNormalized = {
  'nodraw': 'cgrcdefault',
  'templbumpdiffuse': 'cgrcbump_diff',
  'templbumpdiffuse_nocm': 'cgrcbump_diff_singlelight_atten',
  'templbumpspec': 'cgrcbump_diffspec_singlelight_ps20',
  'templbumpspec_hp': 'cgrcbump_diffspec_singlelight_hp_atten',
  'templbumpspec_nocm': 'cgrcbump_diffspec_singlelight',
  'templbumpspec_glossalpha_envcmamb':
      'cgrcbump_diffspec_singlelight_glossalpha_envcm_ps20',
};

String resolveAliasesTxtTarget(String normalizedTarget) {
  return kAliasesTxtTargetToManifestNormalized[normalizedTarget] ??
      normalizedTarget;
}

/// One alias entry extracted from CustomAliases.txt.
class AliasPair {
  final String alias;
  final String target;
  final String blockCondition;
  const AliasPair(this.alias, this.target, this.blockCondition);
}

/// Result of auditing a single alias.
class AuditResult {
  final String alias;
  final String rawTarget;
  final String? metalTarget;
  const AuditResult({
    required this.alias,
    required this.rawTarget,
    this.metalTarget,
  });
}

/// Parses [content] (the full text of CustomAliases.txt) and returns
/// a deduplicated list of all alias→target pairs found in any block.
/// Pairs whose alias appears multiple times keep only the first occurrence.
List<AliasPair> parseCustomAliases(String content) {
  final pairs = <AliasPair>[];
  final seenAliases = <String>{};

  String currentCondition = '';
  bool inBlock = false;

  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();

    if (line == '{') {
      inBlock = true;
      currentCondition = '';
      continue;
    }
    if (line == '}') {
      inBlock = false;
      currentCondition = '';
      continue;
    }

    if (!inBlock) continue;
    if (line.isEmpty || line.startsWith(';')) continue;

    // Condition header: "GPU = NV1X", "r_Quality_BumpMapping = 3", etc.
    if (line.contains('=') && !line.startsWith('Templ') && !line.startsWith('CGRC') &&
        !RegExp(r'^\w+\s+\w').hasMatch(line)) {
      currentCondition = line;
      continue;
    }

    // Strip inline comments (anything after first unquoted ';')
    final commentIdx = line.indexOf(';');
    final stripped = (commentIdx >= 0 ? line.substring(0, commentIdx) : line).trim();
    if (stripped.isEmpty) continue;

    // Split on whitespace: first token = alias, second = target
    final parts = stripped.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;

    final alias = parts[0].trim();
    final target = parts[1].trim();
    if (alias.isEmpty || target.isEmpty) continue;

    if (!seenAliases.contains(alias.toLowerCase())) {
      seenAliases.add(alias.toLowerCase());
      pairs.add(AliasPair(alias, target, currentCondition));
    }
  }

  return pairs;
}

/// Resolves [name] (already lowercased) to a Metal shader name.
/// Returns null if the name cannot be resolved.
String? _resolve(String normalized, Set<String> manifestNames) {
  final String resolved = resolveCustomAliasesTargetForManifest(normalized);
  if (kMetalBuiltins.contains(resolved)) return resolved;
  if (manifestNames.contains(resolved)) return resolved;
  return null;
}

/// Normalizes a shader name the same way the Metal loader does
/// (`ConvertDOSToUnixName` + lowercase).
String normalizeCryShaderLookupName(String name) {
  if (name.isEmpty) return '';
  return name.replaceAll(r'\', '/').toLowerCase();
}

/// One row from `Shaders/Aliases.txt` (flat alias table, no `{` blocks).
typedef AliasesTxtEntry = ({String alias, String target});

/// Parses the content of **Aliases.txt**: non-empty lines, optional `;` comment,
/// first two whitespace-separated tokens are alias and target.
/// Duplicate aliases (case-insensitive): first occurrence wins.
List<AliasesTxtEntry> parseAliasesTxt(String content) {
  final pairs = <AliasesTxtEntry>[];
  final seenAliases = <String>{};

  for (final rawLine in content.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith(';')) continue;
    final commentIdx = line.indexOf(';');
    if (commentIdx >= 0) {
      line = line.substring(0, commentIdx).trim();
    }
    if (line.isEmpty) continue;

    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;

    final alias = parts[0].trim();
    final target = parts[1].trim();
    if (alias.isEmpty || target.isEmpty) continue;

    final key = alias.toLowerCase();
    if (seenAliases.contains(key)) continue;
    seenAliases.add(key);
    pairs.add((alias: alias, target: target));
  }

  return pairs;
}

/// Groups normalized **target** names → alternate lookup names for manifest
/// `lookupAliases` (targets are manifest `normalized` fragment keys).
Map<String, List<String>> buildManifestLookupAliasesByTargetFromEntries(
  List<AliasesTxtEntry> entries,
) {
  final map = <String, List<String>>{};
  for (final p in entries) {
    final String t =
        resolveAliasesTxtTarget(normalizeCryShaderLookupName(p.target));
    final a = normalizeCryShaderLookupName(p.alias);
    if (t.isEmpty || a.isEmpty || t == a) continue;
    map.putIfAbsent(t, () => []).add(a);
  }
  return map;
}

/// Chains [kIntermediateAliases] (legacy FP / template names) then applies
/// [resolveAliasesTxtTarget] for **CustomAliases.txt** right-hand sides so they
/// fold onto manifest `normalized` keys the same way **Aliases.txt** targets do.
String resolveCustomAliasesTargetForManifest(String normalizedTarget) {
  String t = normalizedTarget;
  for (int i = 0; i < 32; i++) {
    final String? next = kIntermediateAliases[t];
    if (next == null || next == t) break;
    t = next;
  }
  return resolveAliasesTxtTarget(t);
}

/// Same grouping as [buildManifestLookupAliasesByTargetFromEntries], but for
/// pairs from [parseCustomAliases]. Uses [resolveCustomAliasesTargetForManifest].
Map<String, List<String>> buildManifestLookupAliasesByTargetFromCustomAliasPairs(
  List<AliasPair> pairs,
) {
  final map = <String, List<String>>{};
  for (final p in pairs) {
    final String t = resolveCustomAliasesTargetForManifest(
        normalizeCryShaderLookupName(p.target));
    final String a = normalizeCryShaderLookupName(p.alias);
    if (t.isEmpty || a.isEmpty || t == a) continue;
    map.putIfAbsent(t, () => []).add(a);
  }
  return map;
}

/// Merges alias-by-target maps (e.g. **Aliases.txt** + **CustomAliases.txt**).
/// Duplicate aliases under the same target are skipped.
Map<String, List<String>> mergeManifestLookupAliasMaps(
  Map<String, List<String>> a,
  Map<String, List<String>> b,
) {
  final out = <String, List<String>>{
    for (final MapEntry<String, List<String>> e in a.entries)
      e.key: List<String>.from(e.value),
  };
  for (final MapEntry<String, List<String>> e in b.entries) {
    final List<String> list = out.putIfAbsent(e.key, () => []);
    for (final String alias in e.value) {
      if (!list.contains(alias)) list.add(alias);
    }
  }
  return out;
}

/// Audits [pairs] against [manifestNames] (normalized shader names from the
/// generated Metal manifest) and returns one [AuditResult] per unique alias.
List<AuditResult> auditAliases(
  List<AliasPair> pairs,
  Set<String> manifestNames,
) {
  return [
    for (final p in pairs)
      AuditResult(
        alias: p.alias,
        rawTarget: p.target,
        metalTarget:
            _resolve(normalizeCryShaderLookupName(p.target), manifestNames),
      ),
  ];
}
