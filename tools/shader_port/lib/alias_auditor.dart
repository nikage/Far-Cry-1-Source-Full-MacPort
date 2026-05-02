/// Parser and resolver for CryEngine CustomAliases.txt shader alias tables.
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

/// Intermediate alias targets that are themselves registered in
/// InitializeShaderFallbacks (normalized → builtin or manifest name).
/// We resolve through these so that alias chains like
///   TerrainLake → LowSpecWaterOutdoor_FP → terrain
/// can be fully resolved.
const Map<String, String> kIntermediateAliases = {
  'lowspecwateroutdoor_fp': 'terrain',
  'lowspecwaterindoor_fp': 'terrain',
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
  if (kMetalBuiltins.contains(normalized)) return normalized;
  if (manifestNames.contains(normalized)) return normalized;
  final intermediate = kIntermediateAliases[normalized];
  if (intermediate != null) return _resolve(intermediate, manifestNames);
  return null;
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
        metalTarget: _resolve(p.target.toLowerCase(), manifestNames),
      ),
  ];
}
