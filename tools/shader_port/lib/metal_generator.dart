library metal_generator;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'reflection_adapter.dart';
import 'alias_auditor.dart';
import 'parser.dart' show parseTechniquePairs;

part 'shader_ir_models.dart';
part 'shader_ir_parser.dart';
part 'expression_translator.dart';
part 'transformers/lighting_transformers.dart';
part 'transformers/type_transformers.dart';
part 'transformers/hdr_transformers.dart';
part 'transformers/math_transformers.dart';
part 'transformers/uniform_transformers.dart';
part 'emission_strategies.dart';
part 'metal_fragment_builder.dart';

List<String> manifestLookupAliasesForNormalizedFragment(
  String normalized, {
  Map<String, List<String>>? aliasesTxtByTarget,
}) {
  final out = <String>[];
  void addUnique(String v) {
    if (!out.contains(v)) out.add(v);
  }
  switch (normalized) {
    case 'cgrcflare':
      addUnique('flare_from_light');
    default:
      break;
  }
  final extra = aliasesTxtByTarget?[normalized];
  if (extra != null) {
    for (final a in extra) {
      addUnique(a);
    }
  }
  return out;
}

/// Returns Aliases.txt targets (already normalized) that did not match any
/// manifest fragment normalized name. The manifest is the only source of truth
/// for shader registration; aliases pointing at a non-existent target would be
/// silently dropped at runtime, which is exactly what the strict policy bans.
/// The returned list is sorted to make CI output stable.
Map<String, String> loadTechniqueFragmentToVertexShaderMap(
  String rootPathWithSep,
  String sep,
) {
  final Map<String, String> out = {};
  final String shaderSourceRoot =
      '${rootPathWithSep}Assets${sep}Shaders${sep}Source';
  final Directory rootDir = Directory(shaderSourceRoot);
  if (!rootDir.existsSync()) {
    return out;
  }
  const Set<String> extensions = {
    '.crycg',
    '.fx',
    '.cfx',
    '.ext',
    '.txt',
  };
  for (final FileSystemEntity entity
      in rootDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final String lower = entity.path.toLowerCase();
    bool extOk = false;
    for (final String ext in extensions) {
      if (lower.endsWith(ext)) {
        extOk = true;
        break;
      }
    }
    if (!extOk) continue;
    late final String text;
    try {
      text = entity.readAsStringSync(encoding: utf8);
    } catch (_) {
      continue;
    }
    if (!text.contains('Technique')) continue;
    final Map<String, String> pairs = parseTechniquePairs(text);
    for (final MapEntry<String, String> e in pairs.entries) {
      if (e.key.isEmpty) continue;
      final String k = e.key.toLowerCase();
      out.putIfAbsent(k, () => e.value);
    }
  }
  return out;
}

List<String> findUnmatchedAliasTargets(
  Map<String, List<String>> aliasesTxtByTarget,
  Set<String> manifestNormalizedKeys,
) {
  final unmatched = aliasesTxtByTarget.keys
      .where((target) => !manifestNormalizedKeys.contains(target))
      .toList()
    ..sort();
  return unmatched;
}

void main(List<String> args) {
  String? overridesPath;
  String rootArg = '';
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--overrides' && i + 1 < args.length) {
      overridesPath = args[i + 1];
      i++;
    } else if (rootArg.isEmpty && !args[i].startsWith('--')) {
      rootArg = args[i];
    }
  }

  final Directory root =
      (rootArg.isEmpty ? Directory.current : Directory(rootArg)).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath = root.path.endsWith(sep) ? root.path : root.path + sep;

  final _ShaderPairOverrides overrides =
      _loadOverrides(overridesPath, rootPath, sep);

  final Map<String, String> techniqueFragToVertShader =
      loadTechniqueFragmentToVertexShaderMap(rootPath, sep);

  final Directory irDir = Directory(rootPath + 'tools${sep}shader_port${sep}output${sep}ir');
  if (!irDir.existsSync()) {
    stderr.writeln('Missing IR directory: ${irDir.path}');
    exit(1);
  }

  final File aliasesTxtFile = File(
      rootPath + 'Assets${sep}Shaders${sep}Source${sep}Shaders${sep}Aliases.txt');
  if (!aliasesTxtFile.existsSync()) {
    stderr.writeln('ERROR: Shaders/Aliases.txt not found at ${aliasesTxtFile.path}');
    exit(1);
  }
  final Map<String, List<String>> aliasesTxtByTarget =
      buildManifestLookupAliasesByTargetFromEntries(
          parseAliasesTxt(aliasesTxtFile.readAsStringSync(encoding: utf8)));
  final Directory outDir = Directory(rootPath + 'RenderDll${sep}XRenderMetal${sep}Generated');
  outDir.createSync(recursive: true);
  final File manifest = File(outDir.path + sep + 'generated_manifest.json');
  final ShaderIrParser parser = ShaderIrParser();

  // Pre-parse all IR JSON files so vertex and fragment shaders can be
  // processed in separate passes.
  final List<({
    String relative,
    ShaderIrParseResult result,
    ShaderIrData data,
    String metalFileName,
  })> allShaders = [];
  for (final FileSystemEntity entity
      in irDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.json')) continue;
    final dynamic parsed =
        jsonDecode(entity.readAsStringSync(encoding: utf8));
    if (parsed is! Map<String, dynamic>) continue;
    final Map<String, dynamic> ir = parsed;
    final String extension =
        (ir['extension'] as String? ?? '').toLowerCase();
    if (extension != 'cryps' && extension != 'crycg') continue;
    final String relative = entity.path
        .substring(irDir.path.length + 1)
        .replaceAll(RegExp(r'[\\/]'), '/');
    final ShaderIrParseResult result = parser.parse(ir, relative);
    final ShaderIrData data = result.data;
    final String metalFileName =
        '${relative.replaceAll('/', '_')}.metal';
    allShaders.add((
      relative: relative,
      result: result,
      data: data,
      metalFileName: metalFileName,
    ));
  }

  final List<Map<String, dynamic>> manifestEntries = [];
  int generated = 0;

  // Build vertex lookup tables from pre-parsed IR (no emission needed).
  // Entry point names are deterministic: 'generated_<normalizedName>_vertex'.
  final Map<String, String> vertexByNormalized = {
    for (final s in allShaders)
      if (s.data.stage == 'vertex')
        s.data.normalizedName: 'generated_${s.data.normalizedName}_vertex',
  };
  final Map<String, String> vertexShaderByName = {
    for (final s in allShaders)
      if (s.data.stage == 'vertex')
        s.data.shaderName: 'generated_${s.data.normalizedName}_vertex',
  };
  final Map<String, String> vertexNormByEntryPoint = {
    for (final s in allShaders)
      if (s.data.stage == 'vertex')
        'generated_${s.data.normalizedName}_vertex': s.data.normalizedName,
  };

  // Phase 1: resolve vertex–fragment pairing before emitting any shaders so
  // that VS requirement aggregation (Phase 1.5) can use the pairing map.
  final Map<
      String,
      ({
        String vertexEntryPoint,
        String? vertexNorm,
        String? overrideCategory,
      })> fragmentPairing = {};
  int overrideCount = 0;
  int techniquePairCount = 0;
  for (final s in allShaders) {
    if (s.data.stage != 'fragment') continue;
    final String norm = s.data.normalizedName;
    final _OverrideResult? ov = overrides.resolve(norm);
    if (ov != null) {
      final String? ep = vertexShaderByName[ov.vertexShader];
      if (ep != null) {
        fragmentPairing[norm] = (
          vertexEntryPoint: ep,
          vertexNorm: vertexNormByEntryPoint[ep],
          overrideCategory: ov.category,
        );
        overrideCount++;
        continue;
      }
    }
    final String? techVertName =
        techniqueFragToVertShader[s.data.shaderName.toLowerCase()];
    if (techVertName != null) {
      final String? techEp = vertexShaderByName[techVertName];
      if (techEp != null) {
        fragmentPairing[norm] = (
          vertexEntryPoint: techEp,
          vertexNorm: vertexNormByEntryPoint[techEp],
          overrideCategory: null,
        );
        techniquePairCount++;
        continue;
      }
    }
    final String? vep =
        _resolveVertexEntryPoint(norm, vertexByNormalized);
    if (vep != null) {
      fragmentPairing[norm] = (
        vertexEntryPoint: vep,
        vertexNorm: vertexNormByEntryPoint[vep],
        overrideCategory: null,
      );
    }
  }

  // Phase 1.5: aggregate per-VS output requirements from all paired FSes so
  // that the vertex output struct is wide enough to satisfy every fragment
  // that shares this vertex shader.
  final Map<String, Map<String, int>> vsRequiredOutputs =
      collectVsRequiredOutputs(allShaders, fragmentPairing);

  // Phase 2: emit vertex shaders using the aggregated output requirements,
  // and record the actual emitted output component maps for Phase 3.
  final Map<String, Map<String, int>> vertexOutputsByNorm = {};
  for (final s in allShaders) {
    if (s.data.stage != 'vertex') continue;
    final ShaderIrData data = s.data;
    final ShaderIrParseResult result = s.result;
    final File targetFile =
        File(outDir.path + sep + s.metalFileName);
    targetFile.parent.createSync(recursive: true);
    final Map<String, int>? vsReqs = vsRequiredOutputs[data.normalizedName];
    targetFile.writeAsStringSync(
      MetalFragmentBuilder(
        data,
        isVertexStage: true,
        vsOutputRequirements: vsReqs,
      ).build(),
    );
    final List<Map<String, dynamic>> vsOutputsList =
        summarizeVertexOutputs(data, vsReqs);
    vertexOutputsByNorm[data.normalizedName] = {
      for (final o in vsOutputsList)
        o['name'] as String: o['components'] as int,
    };
    final Map<String, dynamic> pipeline =
        derivePipelineMetadata(
            data.shaderName, result.directives, data.passStates);
    final List<Map<String, dynamic>> manifestVertexMetadata =
        orderVertexAttributes(data.vertexAttributeMetadata);
    final String entryPointName =
        'generated_${data.normalizedName}_vertex';
    final List<Map<String, dynamic>> vertexInputs =
        _summarizeVertexInputs(manifestVertexMetadata);
    manifestEntries.add({
      'source': s.relative,
      'metal': s.metalFileName,
      'shader': data.shaderName,
      'normalized': data.normalizedName,
      'fragment': entryPointName,
      'entryPoint': entryPointName,
      'stage': data.stage,
      'uniformStruct': data.uniformStruct,
      'uniformCount': data.uniforms.length,
      'textureCount': data.textures.length,
      'vertexAttributes': data.vertexAttributes,
      'vertexAttributeMetadata': manifestVertexMetadata,
      if (vertexInputs.isNotEmpty) 'vertexInputs': vertexInputs,
      if (vsOutputsList.isNotEmpty) 'vertexOutputs': vsOutputsList,
      'directives': result.directives,
      'maskReferences': data.maskReferences,
      'uniforms': data.uniforms
          .map((u) => {
                'name': u.name,
                'type': u.type,
                'semantic': u.semantic,
                if (u.arraySize != null) 'arraySize': u.arraySize,
              })
          .toList(),
      'textures': data.textures
          .map((t) => {
                'name': t.name,
                'type': t.type,
                'semantic': t.semantic,
                'slot': t.slot,
              })
          .toList(),
      'pipeline': pipeline,
    });
    generated++;
  }

  // Phase 3: emit fragment shaders, passing the paired vertex output
  // component map so stage_in field types match vertex output types exactly.
  for (final s in allShaders) {
    if (s.data.stage != 'fragment') continue;
    final ShaderIrData data = s.data;
    final ShaderIrParseResult result = s.result;
    final String norm = data.normalizedName;
    final ({
      String vertexEntryPoint,
      String? vertexNorm,
      String? overrideCategory,
    })? pairing = fragmentPairing[norm];
    // Use the manifest-paired VS's exact norm (including _vs20 suffix if
    // present).  The C++ runtime now consistently prefers the versioned variant
    // over the bare one when both share the same canonical key, so the FS
    // stage_in built against the versioned VS outputs will always match.
    final Map<String, int>? pairedOutputs = pairing?.vertexNorm != null
        ? vertexOutputsByNorm[pairing!.vertexNorm!]
        : null;
    final File targetFile =
        File(outDir.path + sep + s.metalFileName);
    targetFile.parent.createSync(recursive: true);
    targetFile.writeAsStringSync(
      MetalFragmentBuilder(
        data,
        isVertexStage: false,
        pairedVertexOutputs: pairedOutputs,
      ).build(),
    );
    final Map<String, dynamic> pipeline =
        derivePipelineMetadata(
            data.shaderName, result.directives, data.passStates);
    final String pipelineCategory = pairing?.overrideCategory ??
        _derivePipelineCategory(norm, data.shaderName);
    final List<String> fragmentLookupAliases =
        manifestLookupAliasesForNormalizedFragment(norm,
            aliasesTxtByTarget: aliasesTxtByTarget);
    manifestEntries.add({
      'source': s.relative,
      'metal': s.metalFileName,
      'shader': data.shaderName,
      'normalized': norm,
      'fragment': data.fragmentName,
      'entryPoint': data.fragmentName,
      'stage': data.stage,
      'uniformStruct': data.uniformStruct,
      'uniformCount': data.uniforms.length,
      'textureCount': data.textures.length,
      'vertexAttributes': data.vertexAttributes,
      'vertexAttributeMetadata': data.vertexAttributeMetadata,
      'directives': result.directives,
      'maskReferences': data.maskReferences,
      if (pairing != null) 'vertexEntryPoint': pairing.vertexEntryPoint,
      'pipelineCategory': pipelineCategory,
      if (fragmentLookupAliases.isNotEmpty)
        'lookupAliases': fragmentLookupAliases,
      'uniforms': data.uniforms
          .map((u) => {
                'name': u.name,
                'type': u.type,
                'semantic': u.semantic,
                if (u.arraySize != null) 'arraySize': u.arraySize,
              })
          .toList(),
      'textures': data.textures
          .map((t) => {
                'name': t.name,
                'type': t.type,
                'semantic': t.semantic,
                'slot': t.slot,
              })
          .toList(),
      'pipeline': pipeline,
    });
    generated++;
  }

  // Assign pipelineCategory to vertex entries.
  for (final e in manifestEntries) {
    if (e['stage'] != 'vertex') continue;
    if (!e.containsKey('pipelineCategory')) {
      e['pipelineCategory'] = _derivePipelineCategory(
          e['normalized'] as String, e['shader'] as String);
    }
  }

  manifest.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifestEntries));
  stdout.writeln('Generated $generated Metal shader files');
  stdout.writeln(
      'Paired: ${fragmentPairing.length} fragment shaders ($overrideCount via overrides, $techniquePairCount via technique sources)');

  final Set<String> manifestNormalizedKeys = manifestEntries
      .map((e) => (e['normalized'] as String?) ?? '')
      .where((s) => s.isNotEmpty)
      .toSet();
  final List<String> unmatchedAliasTargets =
      findUnmatchedAliasTargets(aliasesTxtByTarget, manifestNormalizedKeys);
  if (unmatchedAliasTargets.isNotEmpty) {
    stderr.writeln(
        'WARN: ${unmatchedAliasTargets.length} Aliases.txt target(s) do not match any manifest fragment normalized name — those aliases were dropped:');
    for (final target in unmatchedAliasTargets) {
      final List<String> orphans = aliasesTxtByTarget[target] ?? const [];
      stderr.writeln('  $target  <-  ${orphans.join(', ')}');
    }
    stderr.writeln(
        'Fix: either add the missing manifest fragment, or update Assets/Shaders/Source/Shaders/Aliases.txt to point at a valid normalized fragment name.');
  }
}

class _OverrideResult {
  const _OverrideResult(this.vertexShader, this.category);
  final String vertexShader;
  final String category;
}

class _PrefixMapping {
  const _PrefixMapping(this.prefix, this.vertex, this.category);
  final String prefix;
  final String vertex;
  final String category;
}

class _ShaderPairOverrides {
  _ShaderPairOverrides({
    required this.prefixMappings,
    required this.explicit,
  });

  final List<_PrefixMapping> prefixMappings;
  final Map<String, _OverrideResult> explicit;

  _OverrideResult? resolve(String normalizedFragName) {
    final _OverrideResult? ex = explicit[normalizedFragName];
    if (ex != null) return ex;
    for (final _PrefixMapping pm in prefixMappings) {
      if (normalizedFragName.startsWith(pm.prefix)) {
        return _OverrideResult(pm.vertex, pm.category);
      }
    }
    return null;
  }

  static const _ShaderPairOverrides empty = _ShaderPairOverrides._([], {});
  const _ShaderPairOverrides._(this.prefixMappings, this.explicit);
}

_ShaderPairOverrides _loadOverrides(
    String? overridesPath, String rootPath, String sep) {
  File? file;
  if (overridesPath != null) {
    file = File(overridesPath);
  } else {
    final File candidate = File(
        '${rootPath}tools${sep}shader_port${sep}config${sep}shader_pair_overrides.json');
    if (candidate.existsSync()) file = candidate;
  }
  if (file == null || !file.existsSync()) {
    return _ShaderPairOverrides.empty;
  }
  try {
    final dynamic raw = jsonDecode(file.readAsStringSync(encoding: utf8));
    if (raw is! Map<String, dynamic>) return _ShaderPairOverrides.empty;

    final List<_PrefixMapping> prefixMappings = [];
    final dynamic prefixRaw = raw['prefixMappings'];
    if (prefixRaw is List) {
      for (final dynamic pm in prefixRaw) {
        if (pm is Map<String, dynamic>) {
          final String? prefix = pm['prefix'] as String?;
          final String? vertex = pm['vertex'] as String?;
          final String category = (pm['category'] as String?) ?? 'mesh';
          if (prefix != null && vertex != null) {
            prefixMappings.add(_PrefixMapping(prefix, vertex, category));
          }
        }
      }
    }

    final Map<String, _OverrideResult> explicit = {};
    final dynamic explicitRaw = raw['explicit'];
    if (explicitRaw is Map<String, dynamic>) {
      for (final MapEntry<String, dynamic> entry in explicitRaw.entries) {
        if (entry.value is Map<String, dynamic>) {
          final Map<String, dynamic> val = entry.value as Map<String, dynamic>;
          final String? vertex = val['vertex'] as String?;
          final String category = (val['category'] as String?) ?? 'mesh';
          if (vertex != null) {
            explicit[entry.key] = _OverrideResult(vertex, category);
          }
        } else if (entry.value is String) {
          explicit[entry.key] = _OverrideResult(entry.value as String, 'mesh');
        }
      }
    }
    return _ShaderPairOverrides(
        prefixMappings: prefixMappings, explicit: explicit);
  } catch (e) {
    stderr.writeln('Error: failed to parse overrides file ${file.path}: $e');
    exit(1);
  }
}

String _derivePipelineCategory(String normalized, String shaderName) {
  final String lower = normalized.toLowerCase();
  if (lower.startsWith('cgrc_hdr_') ||
      lower.startsWith('cgrcblur') ||
      lower.contains('screen') ||
      lower.contains('glare') ||
      lower == 'cgrcflare' ||
      lower == 'cgrcoffset' ||
      lower == 'cgrcluminosity' ||
      lower == 'cgrcmotionamount' ||
      lower == 'cgrcdof' ||
      lower == 'cgpsbumpoffset') {
    return 'fullscreen';
  }
  if (lower.contains('shadow') || lower.contains('depth')) {
    return 'shadow';
  }
  if (lower.contains('terrain') || lower.contains('dot3')) {
    return 'terrain';
  }
  if (lower.contains('water') || lower.contains('ocean') ||
      lower.contains('reflectcmap') || lower.contains('refractcmap')) {
    return 'water';
  }
  if (lower.contains('heat') || lower.contains('heatvis')) {
    return 'heat';
  }
  if (lower.contains('plant') || lower.contains('tree') ||
      lower.contains('sprite') || lower.contains('bark') ||
      lower.contains('bush') || lower.contains('sunrabbits')) {
    return 'plant';
  }
  if (lower.contains('particle')) {
    return 'particle';
  }
  if (lower.contains('decal')) {
    return 'decal';
  }
  return 'mesh';
}

/// Tokens that appear only in fragment shader names and have no corresponding
/// token in vertex shader names — they are removed before matching.
const Set<String> _fragOnlyTokens = {
  'singlelight',
  'multiplelights',
  'multiplelight',
  'projsinglelight',
  'powerglossalpha',
  'powergloss',
  'noatten',
  'vertlight',
  'mult',
  'alphaglow',
  'glitter',
};

/// Token renaming rules: fragment token → equivalent vertex token.
/// Values containing '_' are expanded as multi-token sequences.
const Map<String, String> _fragTokenRename = {
  'glossalpha': 'gloss',
  'projnoatten': 'proj',
  'specgloss': 'specpass_gloss',
};

/// Adjacent-pair merges applied after single-token transforms.
/// Key = (token_a, token_b); value = merged replacement.
const Map<(String, String), String> _tokenPairMerge = {
  ('proj', 'atten'): 'projatten',
  ('proj', 'vertatten'): 'projvertatten',
};

/// Returns the vertex entryPoint for [fragmentNorm] by trying several
/// stem candidates, or null when no match is found.
///
/// CryEngine fragment shaders start with `cgrc` or `cgps`; vertex shaders
/// start with `cgvprog`. The pairing is declared at the technique/pass level
/// in the source shader template files; since those declarations are not
/// present in the individual `.crycg` program files in this source tree,
/// this function uses a multi-tier token-based naming heuristic that
/// encodes the common CryEngine naming conventions.
///
/// Coverage: the base heuristic resolves ~57% of fragment shaders; with the
/// additional alphaglow/specgloss token rules and HP↔Atten swap the resolved
/// set grows further.  Remaining gaps are handled by `shader_pair_overrides.json`
/// so that every fragment ultimately has `vertexEntryPoint` set.
String? _resolveVertexEntryPoint(
    String fragmentNorm, Map<String, String> vertexByNorm) {

  String? _lookup(String key) => vertexByNorm[key];

  String? _tryCandidates(String stem) {
    for (final String c in [
      'cgvprog${stem}_vs20',
      'cgvprog${stem}_vs30',
      'cgvprog${stem}',
      'cgvprog_${stem}_vs20',
      'cgvprog_${stem}',
    ]) {
      final String? e = _lookup(c);
      if (e != null) return e;
    }
    return null;
  }

  // 1. Strip fragment prefix.
  String stem = fragmentNorm;
  for (final String prefix in ['cgrc_', 'cgrc', 'cgps']) {
    if (stem.startsWith(prefix)) {
      stem = stem.substring(prefix.length);
      break;
    }
  }

  // 2. Strip version suffix.
  for (final String suffix in ['_ps20', '_ps30', '_ps14', '_ps11', '_ps']) {
    if (stem.endsWith(suffix)) {
      stem = stem.substring(0, stem.length - suffix.length);
      break;
    }
  }

  // 3. Quick identity check (fragment and vertex share normalized name).
  String? hit = _tryCandidates(stem);
  if (hit != null) return hit;
  hit = _lookup(fragmentNorm);
  if (hit != null) return hit;

  // 4. Token-based transform pipeline:
  //
  //   Split the stem on '_', apply per-token transforms, then rejoin.
  //   This handles the systematic naming differences between fragment and
  //   vertex shader names in CryEngine 1.x:
  //     - Fragment names include light-count qualifiers (singlelight, etc.)
  //       that vertex names omit — remove them.
  //     - Fragment names use "diff" / "spec" while vertex names say
  //       "diffpass" / "specpass" — add the "pass" suffix.
  //     - "glossalpha" in fragment == "gloss" in vertex — rename.
  //     - Standalone "proj" followed by "atten" merges to "projatten".
  //     - Some fragment names order "hp" and "proj" differently from
  //       vertex names — try both orderings.

  List<String> tokens = stem.split('_');

  // (a) Remove fragment-only tokens and rename others.
  //     Rename values containing '_' are expanded as multiple tokens.
  final List<String> renamedTokens = [];
  for (final String t in tokens) {
    if (_fragOnlyTokens.contains(t)) continue;
    final String renamed = _fragTokenRename[t] ?? t;
    if (renamed.contains('_')) {
      renamedTokens.addAll(renamed.split('_'));
    } else {
      renamedTokens.add(renamed);
    }
  }
  tokens = renamedTokens;

  // (b) Merge adjacent pairs.
  final List<String> merged = [];
  int i = 0;
  while (i < tokens.length) {
    if (i + 1 < tokens.length) {
      final (String, String) pair = (tokens[i], tokens[i + 1]);
      final String? replacement = _tokenPairMerge[pair];
      if (replacement != null) {
        merged.add(replacement);
        i += 2;
        continue;
      }
    }
    merged.add(tokens[i]);
    i++;
  }
  tokens = merged;

  String s = tokens.join('_');

  // (c) Apply "light-pass" suffix to diff/spec category tokens.
  //     diffspec → diffspecpass takes priority over diff → diffpass.
  String? _applyPassTransform(String stem) {
    final List<String> parts = stem.split('_');
    for (int idx = 0; idx < parts.length; idx++) {
      if (parts[idx] == 'diffspec') {
        parts[idx] = 'diffspecpass';
        return parts.join('_');
      }
      if (parts[idx] == 'diff') {
        parts[idx] = 'diffpass';
        return parts.join('_');
      }
      if (parts[idx] == 'spec') {
        parts[idx] = 'specpass';
        return parts.join('_');
      }
    }
    return null;
  }

  // (d) Build candidate list with optional hp↔proj reorder.
  final List<String> candidateStems = [s];
  final String? passStem = _applyPassTransform(s);
  if (passStem != null) candidateStems.add(passStem);

  // Try swapping two tokens at positions i and j.
  String? _swapTokens(String stem, String a, String b) {
    final List<String> parts = stem.split('_');
    final int ia = parts.indexOf(a);
    final int ib = parts.indexOf(b);
    if (ia == -1 || ib == -1 || ia == ib) return null;
    if (ia > ib) return null;
    final List<String> swapped = List<String>.from(parts);
    swapped[ia] = parts[ib];
    swapped[ib] = parts[ia];
    return swapped.join('_');
  }

  // Collect all variants (with and without pass, with and without position swaps)
  final List<String> allStems = [];
  for (final String base in candidateStems) {
    allStems.add(base);
    // hp↔proj swap (fragment sometimes reverses these)
    final String? hpProj = _swapTokens(base, 'hp', 'proj');
    if (hpProj != null) allStems.add(hpProj);
    // hp↔atten swap (fragment has HP before atten; vertex has atten before HP)
    final String? hpAtten = _swapTokens(base, 'hp', 'atten');
    if (hpAtten != null) allStems.add(hpAtten);
  }

  for (final String cs in allStems) {
    hit = _tryCandidates(cs);
    if (hit != null) return hit;
  }

  // 5. Gloss-stripping fallback: if the stem still has a 'gloss' token, try
  //    again without it.  HP vertex shaders rarely carry the gloss suffix.
  if (allStems.any((st) => st.split('_').contains('gloss'))) {
    final List<String> glossFree = allStems
        .map((st) => st.split('_').where((t) => t != 'gloss').join('_'))
        .toSet()
        .toList();
    for (final String cs in glossFree) {
      hit = _tryCandidates(cs);
      if (hit != null) return hit;
    }
  }

  // 6. Substring fallback: cleaned stem contains a vertex key.
  //    Both sides must be > 8 chars to avoid false positives on short names.
  if (s.length > 8) {
    for (final MapEntry<String, String> kv in vertexByNorm.entries) {
      if (kv.key.length > 8 && s.contains(kv.key)) return kv.value;
    }
  }

  return null;
}

String buildMetal(ShaderIrData data) {
  return MetalFragmentBuilder(
    data,
    isVertexStage: data.stage == 'vertex',
  ).build();
}

const int _kMetalVertexStreamGeneral = 0;
const int _kMetalVertexStreamTangents = 1;

List<Map<String, dynamic>> orderVertexAttributes(
  List<Map<String, dynamic>> metadata,
) {
  if (metadata.isEmpty) {
    return const [];
  }
  final List<Map<String, dynamic>> positions = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> normals = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> colors = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> texCoords = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> others = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> tangents = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> binormals = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> tNormals = <Map<String, dynamic>>[];
  for (final Map<String, dynamic> original in metadata) {
    final Map<String, dynamic> entry = Map<String, dynamic>.from(original);
    final String category =
        (entry['category'] as String? ?? '').toLowerCase();
    final String token = (entry['token'] as String? ?? '').toLowerCase();
    if (category == 'position') {
      positions.add(entry);
      continue;
    }
    if (category == 'normal') {
      if (token.contains('tnormal')) {
        tNormals.add(entry);
      } else {
        normals.add(entry);
      }
      continue;
    }
    if (category == 'tangent') {
      tangents.add(entry);
      continue;
    }
    if (category == 'binormal') {
      binormals.add(entry);
      continue;
    }
    if (category == 'color') {
      colors.add(entry);
      continue;
    }
    if (category == 'texcoord') {
      texCoords.add(entry);
      continue;
    }
    if (token.contains('tangent') ||
        token.contains('binormal') ||
        token.contains('tnormal')) {
      tNormals.add(entry);
      continue;
    }
    others.add(entry);
  }
  final bool requiresTangentFrame =
      tangents.isNotEmpty || binormals.isNotEmpty || tNormals.isNotEmpty;
  if (requiresTangentFrame) {
    if (normals.isEmpty) {
      normals.add(<String, dynamic>{
        'token': 'Normal',
        'category': 'normal',
        'semantic': 'NORMAL',
        'components': 3,
        'source': 'synthetic',
      });
    }
    if (colors.isEmpty) {
      colors.add(<String, dynamic>{
        'token': 'Color',
        'category': 'color',
        'semantic': 'COLOR',
        'components': 4,
        'index': 0,
        'source': 'synthetic',
      });
    }
    if (texCoords.isEmpty) {
      texCoords.add(<String, dynamic>{
        'token': 'TexCoord0',
        'category': 'texcoord',
        'semantic': 'TEXCOORD0',
        'components': 2,
        'index': 0,
        'source': 'synthetic',
      });
    }
  }
  colors.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final int aIndex = a['index'] is int ? a['index'] as int : 0;
    final int bIndex = b['index'] is int ? b['index'] as int : 0;
    return aIndex.compareTo(bIndex);
  });
  texCoords.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final int aIndex = a['index'] is int ? a['index'] as int : 0;
    final int bIndex = b['index'] is int ? b['index'] as int : 0;
    return aIndex.compareTo(bIndex);
  });
  others.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final String tokenA = (a['token'] as String? ?? '');
    final String tokenB = (b['token'] as String? ?? '');
    return tokenA.compareTo(tokenB);
  });
  final List<Map<String, dynamic>> primaryOrder = <Map<String, dynamic>>[
    ...positions,
    ...normals,
    ...colors,
    ...texCoords,
    ...others,
  ];
  final List<Map<String, dynamic>> tangentOrder = <Map<String, dynamic>>[
    ...tangents,
    ...binormals,
    ...tNormals,
  ];
  final List<Map<String, dynamic>> ordered = <Map<String, dynamic>>[];
  int slot = 0;
  for (final Map<String, dynamic> entry in primaryOrder) {
    entry['slot'] = slot;
    entry['bufferIndex'] = _kMetalVertexStreamGeneral;
    ordered.add(entry);
    slot++;
  }
  for (final Map<String, dynamic> entry in tangentOrder) {
    entry['slot'] = slot;
    entry['bufferIndex'] = _kMetalVertexStreamTangents;
    ordered.add(entry);
    slot++;
  }
  if (ordered.isEmpty) {
    return metadata;
  }
  ordered.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final int slotA = a['slot'] is int ? a['slot'] as int : 0;
    final int slotB = b['slot'] is int ? b['slot'] as int : 0;
    return slotA.compareTo(slotB);
  });
  return ordered;
}

List<Map<String, dynamic>> _summarizeVertexInputs(
  List<Map<String, dynamic>> metadata,
) {
  final List<Map<String, dynamic>> ordered = orderVertexAttributes(metadata);
  if (ordered.isEmpty) {
    return const [];
  }
  final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
  for (final Map<String, dynamic> entry in ordered) {
    final int slot = entry['slot'] is int ? entry['slot'] as int : result.length;
    result.add({
      'name': entry['token'] ?? 'attr$slot',
      'index': slot,
      'slot': slot,
      'bufferIndex': entry['bufferIndex'] is int
          ? entry['bufferIndex'] as int
          : _kMetalVertexStreamGeneral,
      if (entry.containsKey('category')) 'category': entry['category'],
      if (entry.containsKey('semantic')) 'semantic': entry['semantic'],
      if (entry.containsKey('components')) 'components': entry['components'],
      if (entry.containsKey('label')) 'label': entry['label'],
    });
  }
  return result;
}

List<Map<String, dynamic>> summarizeVertexOutputs(
  ShaderIrData data, [
  Map<String, int>? vsOutputRequirements,
]) {
  if (data.stage != 'vertex') {
    return const [];
  }
  final _InOutAnalyzer analyzer = _InOutAnalyzer(
    data.coreExpressions,
    data.coreFlow,
  );
  final Map<String, int> resolved =
      _resolveOutputComponentCounts(data, analyzer);
  if (vsOutputRequirements != null) {
    vsOutputRequirements.forEach((String field, int req) {
      resolved[field] = math.max(resolved[field] ?? 0, req);
    });
  }
  if (resolved.isEmpty) {
    return const [];
  }
  final List<Map<String, dynamic>> outputs = resolved.entries
      .where((MapEntry<String, int> entry) => entry.key != 'HPosition')
      .map(
        (MapEntry<String, int> entry) => <String, dynamic>{
          'name': entry.key,
          'components': entry.value,
        },
      )
      .toList()
    ..sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['name'] as String).compareTo(b['name'] as String),
    );
  return outputs;
}

/// Strips version suffixes used by vertex shader CG names (_vs10, _vs11,
/// _vs20, _vs30) from [norm]. The C++ runtime's BuildStageAgnosticKey does
/// the same so both the versioned and bare shader end up on the same canonical
/// key — we must widen both.
String _stripVsSuffix(String norm) {
  const List<String> suffixes = <String>[
    '_vs30', '_vs20', '_vs11', '_vs10',
  ];
  for (final String suffix in suffixes) {
    if (norm.endsWith(suffix)) {
      return norm.substring(0, norm.length - suffix.length);
    }
  }
  return norm;
}

Map<String, Map<String, int>> collectVsRequiredOutputs(
  List<({
    String relative,
    ShaderIrParseResult result,
    ShaderIrData data,
    String metalFileName,
  })> allShaders,
  Map<String, ({
    String vertexEntryPoint,
    String? vertexNorm,
    String? overrideCategory,
  })> fragmentPairing,
) {
  final Map<String, Map<String, int>> result = <String, Map<String, int>>{};

  void _mergeInto(String key, Map<String, int> additions) {
    final Map<String, int> bucket =
        result.putIfAbsent(key, () => <String, int>{});
    additions.forEach((String token, int components) {
      bucket[token] = math.max(bucket[token] ?? 0, components);
    });
  }

  for (final s in allShaders) {
    if (s.data.stage != 'fragment') continue;
    final String? vsNorm = fragmentPairing[s.data.normalizedName]?.vertexNorm;
    if (vsNorm == null) continue;

    // Use the same widening logic as _typeForInputField (incl. macro hints
    // such as texCUBE) so the VS output struct is widened to the width that
    // the FS stage_in will actually declare.
    final Map<String, int> inputReqs =
        MetalFragmentBuilder.computeInputRequirements(s.data);

    // Build a fast position-category lookup from the raw metadata.
    final Set<String> positionTokens = <String>{
      for (final Map<String, dynamic> meta in s.data.vertexAttributeMetadata)
        if ((meta['category'] as String? ?? '').toLowerCase() == 'position' &&
            meta['token'] is String)
          meta['token'] as String,
    };

    final Map<String, int> filtered = <String, int>{
      for (final MapEntry<String, int> e in inputReqs.entries)
        if (!positionTokens.contains(e.key)) e.key: e.value,
    };

    // Write requirements for the exact versioned VS norm (e.g. _vs20 variant).
    _mergeInto(vsNorm, filtered);
  }

  // Synchronize canonical ↔ versioned variants.
  //
  // The C++ runtime's BuildStageAgnosticKey strips _vs20 etc., so both the
  // bare and versioned VS shader compete for the SAME runtime slot.  Whichever
  // is loaded last wins.  Both variants must therefore output the SAME field
  // types; otherwise the FS stage_in built against one variant will fail PSO
  // validation when the other is selected at runtime.
  //
  // Strategy: merge every versioned key into its canonical bucket, then
  // propagate the canonical bucket back into all versioned keys — giving every
  // variant the max-widened union of requirements.
  final List<String> keys = result.keys.toList();
  // Pass 1 – versioned → canonical
  for (final String k in keys) {
    final String canonical = _stripVsSuffix(k);
    if (canonical != k) {
      _mergeInto(canonical, result[k]!);
    }
  }
  // Pass 2 – canonical → versioned
  for (final String k in keys) {
    final String canonical = _stripVsSuffix(k);
    if (canonical != k && result.containsKey(canonical)) {
      _mergeInto(k, result[canonical]!);
    }
  }

  return result;
}

int _componentCountFromType(String type) {
  final String lower = type.toLowerCase();
  if (lower.contains('float4')) {
    return 4;
  }
  if (lower.contains('float3')) {
    return 3;
  }
  if (lower.contains('float2')) {
    return 2;
  }
  return 1;
}

final RegExp _kTexVaryingPattern = RegExp(r'^tex\d+$', caseSensitive: false);

bool _isTexVaryingField(String field) => _kTexVaryingPattern.hasMatch(field);

bool _isColorField(String field) => field.toLowerCase().startsWith('color');

bool _isProjectiveTcField(String field) {
  final String lower = field.toLowerCase();
  if (lower.startsWith('texcoord')) {
    return false;
  }
  return lower.contains('tc');
}

Map<String, int> _resolveOutputComponentCounts(
  ShaderIrData data,
  _InOutAnalyzer analyzer,
) {
  final Map<String, int> declaredComponents = <String, int>{
    for (final MapEntry<String, String> entry in data.outputFieldTypes.entries)
      entry.key: _componentCountFromType(entry.value),
  };
  final Map<String, int> resolved = <String, int>{};
  final Map<String, int> attributeComponents = <String, int>{};

  for (final Map<String, dynamic> entry in data.vertexAttributeMetadata) {
    final String? token = (entry['token'] as String?)?.toLowerCase();
    final int? components = entry['components'] as int?;
    if (token == null || components == null) {
      continue;
    }
    if (token.startsWith('texcoord')) {
      final RegExpMatch? match = RegExp(r'^texcoord(\d+)$').firstMatch(token);
      if (match != null) {
        final String texName = 'Tex${match.group(1)}';
        attributeComponents[texName] =
            math.max(1, math.min(components, 4));
      }
    } else if (token == 'color') {
      attributeComponents['Color'] = 4;
    } else if (token.startsWith('color')) {
      final String suffix = token.substring('color'.length);
      if (suffix.isNotEmpty) {
        final String name =
            'Color${suffix[0].toUpperCase()}${suffix.substring(1)}';
        attributeComponents[name] = math.max(1, math.min(components, 4));
      }
    }
  }

  int _applyOutputComponentRules(
    String field,
    int components, {
    required bool enforceMinimum,
  }) {
    final int? attributeHint = attributeComponents[field];
    if (attributeHint != null) {
      components = math.max(components, attributeHint);
    }
    if (_isColorField(field) || field == 'HPosition') {
      return 4;
    }
    if (_isProjectiveTcField(field)) {
      components = math.max(components, 4);
    }
    if (components < 1) {
      components = 1;
    } else if (components > 4) {
      components = 4;
    }
    if (enforceMinimum && components < 2) {
      components = 2;
    }
    return components;
  }

  for (final String field in analyzer.outputFields) {
    final int? usage = analyzer.outputComponentUsage[field];
    int components = usage ?? 0;
    if (components == 0 && declaredComponents.containsKey(field)) {
      components = declaredComponents[field]!;
    } else if (components == 0) {
      components = 4;
    }
    resolved[field] = _applyOutputComponentRules(
      field,
      components,
      enforceMinimum: true,
    );
  }

  declaredComponents.forEach((String field, int components) {
    if (resolved.containsKey(field)) {
      return;
    }
    resolved[field] = _applyOutputComponentRules(
      field,
      components,
      enforceMinimum: false,
    );
  });

  if (resolved.containsKey('HPosition')) {
    resolved['HPosition'] = 4;
  }

  return resolved;
}

String normalizeName(String input) {
  final String lower = input.toLowerCase();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < lower.length; i++) {
    final int code = lower.codeUnitAt(i);
    if ((code >= 97 && code <= 122) || (code >= 48 && code <= 57)) {
      buffer.writeCharCode(code);
    } else {
      buffer.write('_');
    }
  }
  String normalized = buffer.toString().replaceAll(RegExp('_+'), '_');
  normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
  if (normalized.isEmpty) normalized = 'shader';
  return normalized;
}

Map<String, dynamic> derivePipelineMetadata(
  String shaderName,
  List<dynamic> directivesRaw,
  List<Map<String, dynamic>> passStates,
) {
  final String lowerName = shaderName.toLowerCase();
  final Set<String> directives = directivesRaw
      .whereType<String>()
      .map((d) => d.toLowerCase())
      .toSet();

  final Map<String, dynamic>? summary = _extractPrimaryPassSummary(passStates);

  bool blendEnabled = _summaryBlendEnabled(summary) ?? true;
  String blendMode = _summaryBlendMode(summary) ?? 'alpha';
  bool depthWrite = summary?['depthWrite'] as bool? ?? false;
  bool depthTest = summary?['depthTest'] as bool? ?? true;
  String depthCompare =
      _mapDepthFunc(summary?['depthFunc'] as String?) ?? 'lessEqual';
  String cullMode =
      _mapCullMode(summary?['cullMode'] as String?) ??
      (directives.contains('twosided') ? 'none' : 'back');
  final Map<String, dynamic> blendFactors = _summaryBlendFactors(summary);
  final Map<String, dynamic>? colorMask = _summaryColorMask(summary);

  if (lowerName.contains('shadow') ||
      lowerName.contains('depth') ||
      lowerName.contains('zpass') ||
      lowerName.contains('zonly')) {
    blendEnabled = false;
    depthWrite = true;
    depthTest = true;
    depthCompare = 'lessEqual';
  }

  if (lowerName.contains('opaque') ||
      lowerName.contains('solid') ||
      lowerName.contains('terrain')) {
    blendEnabled = false;
    depthWrite = true;
  }

  if (lowerName.contains('add') ||
      lowerName.contains('glow') ||
      lowerName.contains('flare') ||
      lowerName.contains('lightadd')) {
    blendMode = 'add';
    blendEnabled = true;
    depthWrite = false;
  }

  if (lowerName.contains('alpha') ||
      lowerName.contains('trans') ||
      lowerName.contains('hud') ||
      lowerName.contains('particle')) {
    blendMode = 'alpha';
    blendEnabled = true;
    depthWrite = false;
  }

  if (lowerName.contains('sky') ||
      lowerName.contains('post') ||
      lowerName.contains('screen')) {
    blendMode = 'alpha';
    blendEnabled = true;
    depthWrite = false;
    depthTest = true;
  }

  if (directives.contains('projected')) {
    depthWrite = false;
    depthTest = true;
  }

  if (directives.contains('twosided') || lowerName.contains('twoside')) {
    cullMode = 'none';
  }

  if (!blendEnabled) {
    blendMode = 'none';
  }

  final Map<String, dynamic> result = <String, dynamic>{
    'blendEnabled': blendEnabled,
    'blendMode': blendMode,
    'depthWrite': depthWrite,
    'depthTest': depthTest,
    'depthCompare': depthCompare,
    'cullMode': cullMode,
  };
  if (blendFactors.isNotEmpty) {
    result['blendFactors'] = blendFactors;
  }
  if (colorMask != null && colorMask.isNotEmpty) {
    result['colorMask'] = colorMask;
  }
  if (summary != null) {
    if (summary.containsKey('alphaFunc')) {
      result['alphaFunc'] = (summary['alphaFunc'] as String).toLowerCase();
    }
    if (summary.containsKey('alphaRef')) {
      result['alphaRef'] = summary['alphaRef'];
    }
  }
  return result;
}

Map<String, dynamic>? _extractPrimaryPassSummary(
  List<Map<String, dynamic>> passStates,
) {
  for (final Map<String, dynamic> pass in passStates) {
    final dynamic summary = pass['stateSummary'];
    if (summary is Map<String, dynamic> && summary.isNotEmpty) {
      return summary;
    }
  }
  return null;
}

bool? _summaryBlendEnabled(Map<String, dynamic>? summary) {
  final dynamic blend = summary?['blend'];
  if (blend is Map<String, dynamic>) {
    final dynamic enabled = blend['enabled'];
    if (enabled is bool) {
      return enabled;
    }
  }
  return null;
}

String? _summaryBlendMode(Map<String, dynamic>? summary) {
  final dynamic blend = summary?['blend'];
  if (blend is Map<String, dynamic>) {
    final dynamic mode = blend['mode'];
    if (mode is String && mode.isNotEmpty) {
      return mode.toLowerCase();
    }
    final String? src = _asUpper(blend['src']);
    final String? dst = _asUpper(blend['dst']);
    if (src != null && dst != null) {
      if (src == 'ONE' && dst == 'ONE') {
        return 'add';
      }
      if (src == 'SRCALPHA' &&
          (dst == 'INVSRCALPHA' || dst == 'ONE_MINUS_SRC_ALPHA')) {
        return 'alpha';
      }
      if (src == 'ONE' && dst == 'INVSRCALPHA') {
        return 'premultiplied';
      }
    }
  }
  return null;
}

Map<String, dynamic> _summaryBlendFactors(Map<String, dynamic>? summary) {
  final Map<String, dynamic> factors = <String, dynamic>{};
  final dynamic blend = summary?['blend'];
  if (blend is Map<String, dynamic>) {
    final String? src = _asUpper(blend['src']);
    final String? dst = _asUpper(blend['dst']);
    final String? srcAlpha = _asUpper(blend['srcAlpha']);
    final String? dstAlpha = _asUpper(blend['dstAlpha']);
    final String? op = _asUpper(blend['op']);
    final String? opAlpha = _asUpper(blend['opAlpha']);
    if (src != null) factors['src'] = src;
    if (dst != null) factors['dst'] = dst;
    if (srcAlpha != null) factors['srcAlpha'] = srcAlpha;
    if (dstAlpha != null) factors['dstAlpha'] = dstAlpha;
    if (op != null) factors['op'] = op;
    if (opAlpha != null) factors['opAlpha'] = opAlpha;
  }
  return factors;
}

Map<String, dynamic>? _summaryColorMask(Map<String, dynamic>? summary) {
  Map<String, dynamic>? mask = summary?['colorMask'] as Map<String, dynamic>?;
  if (mask == null || mask.isEmpty) {
    mask = summary?['colourmask'] as Map<String, dynamic>?;
  }
  return mask?.map(
    (String key, dynamic value) => MapEntry<String, dynamic>(key, value),
  );
}

String? _mapDepthFunc(String? func) {
  if (func == null || func.isEmpty) {
    return null;
  }
  final String lower = func.toLowerCase();
  switch (lower) {
    case 'less':
      return 'less';
    case 'lessequal':
    case 'less_equal':
    case 'lequal':
      return 'lessEqual';
    case 'greater':
      return 'greater';
    case 'greaterequal':
    case 'greater_equal':
    case 'gequal':
      return 'greaterEqual';
    case 'equal':
      return 'equal';
    case 'always':
      return 'always';
    case 'never':
      return 'never';
    default:
      return null;
  }
}

String? _mapCullMode(String? mode) {
  if (mode == null || mode.isEmpty) {
    return null;
  }
  final String lower = mode.toLowerCase();
  switch (lower) {
    case 'none':
    case 'disable':
    case 'disabled':
    case 'off':
      return 'none';
    case 'front':
      return 'front';
    case 'back':
      return 'back';
    default:
      return null;
  }
}

String? _asUpper(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return value.toUpperCase();
  }
  return null;
}

/// Testing shim exposing the private vertex-pairing heuristic.
/// Only use from tests.
String? resolveVertexEntryPointForTest(
    String fragmentNorm, Map<String, String> vertexByNorm) =>
    _resolveVertexEntryPoint(fragmentNorm, vertexByNorm);
