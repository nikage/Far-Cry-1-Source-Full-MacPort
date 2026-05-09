import 'dart:io';

import 'package:test/test.dart';
import '../lib/alias_auditor.dart';

const _sampleAliases = '''
{
  GPU = NV1X

  TerrainLake LowSpecWaterOutdoor_FP
  TerrainLake_NoFresnel LowSpecWaterOutdoor_FP
  TerrainWater_OnlySky  LowSpecWaterOutdoor_FP
  TerrainWater LowSpecWaterOutdoor_FP  
  WaterVolume LowSpecWaterIndoor_FP
  TemplBumpDiffuse  TemplDiffuse_FP
  ; this is a comment line
  TemplAlphaBlend   TemplAlphaBlend_FP
  CGRCFlare  CGRCFlare  ; same name
}

{
  r_Quality_BumpMapping = 3

  TemplBumpSpec  TemplBumpSpec_PS20
  TerrainLake    TemplBumpDiffuse
}
''';

void main() {
  group('parseAliasesTxt (Shaders/Aliases.txt)', () {
    const flat = r'''
TBumpSpec		TemplBumpSpec
TBumpSpec_NOCM		TemplBumpSpec_NOCM
no_draw			nodraw
; ignored
''';

    test('parses tab or space separated alias target pairs', () {
      final rows = parseAliasesTxt(flat);
      expect(rows.length, equals(3));
      expect(rows[0].alias, equals('TBumpSpec'));
      expect(rows[0].target, equals('TemplBumpSpec'));
      expect(rows[1].alias, equals('TBumpSpec_NOCM'));
      expect(rows[2].alias, equals('no_draw'));
      expect(rows[2].target, equals('nodraw'));
    });

    test('buildManifestLookupAliasesByTargetFromEntries normalizes like Metal', () {
      final map = buildManifestLookupAliasesByTargetFromEntries(parseAliasesTxt(flat));
      expect(map['cgrcbump_diffspec_singlelight_ps20'], contains('tbumpspec'));
      expect(map['cgrcdefault'], contains('no_draw'));
    });

    test('resolveAliasesTxtTarget maps legacy template targets to manifest keys', () {
      expect(resolveAliasesTxtTarget('templbumpdiffuse'), equals('cgrcbump_diff'));
      expect(resolveAliasesTxtTarget('nodraw'), equals('cgrcdefault'));
      expect(resolveAliasesTxtTarget('cgrcflare'), equals('cgrcflare'));
    });

    test('mergeAliasesTxtTargetManifestOverrides augments resolveAliasesTxtTarget', () {
      resetAliasesTxtTargetManifestEffectiveForTests();
      addTearDown(resetAliasesTxtTargetManifestEffectiveForTests);
      expect(resolveAliasesTxtTarget('custom_fp_target'), equals('custom_fp_target'));
      mergeAliasesTxtTargetManifestOverrides(
          <String, String>{'custom_fp_target': 'cgrcflare'});
      expect(resolveAliasesTxtTarget('custom_fp_target'), equals('cgrcflare'));
    });

    test('partitionManifestAndBuiltinAliasMaps splits builtin targets', () {
      final Map<String, List<String>> merged = <String, List<String>>{
        'terrain': <String>['terrainlowlod'],
        'cgrcflare': <String>['crylight'],
      };
      final ({
        Map<String, List<String>> manifest,
        Map<String, List<String>> builtin
      }) p = partitionManifestAndBuiltinAliasMaps(merged);
      expect(p.builtin['terrain'], contains('terrainlowlod'));
      expect(p.manifest['cgrcflare'], contains('crylight'));
    });

    test('buildManifestLookupAliasesByTargetFromEntries uses intermediate chain', () {
      final Map<String, List<String>> map = buildManifestLookupAliasesByTargetFromEntries(
          parseAliasesTxt('TerrainAlias LavaVolume'));
      expect(map['terrain'], contains('terrainalias'));
    });

    test('normalizeCryShaderLookupName lowercases and flips slashes', () {
      expect(normalizeCryShaderLookupName(r'Foo\Bar'), equals('foo/bar'));
    });

    test('deduplicates aliases case-insensitively (first wins)', () {
      final rows = parseAliasesTxt('a One\nA Two');
      expect(rows.length, equals(1));
      expect(rows[0].target, equals('One'));
    });
  });

  group('parseCustomAliases', () {
    test('extracts alias pairs from all blocks', () {
      final pairs = parseCustomAliases(_sampleAliases);
      final aliases = {for (final p in pairs) p.alias: p.target};
      expect(aliases, containsPair('TerrainLake', 'LowSpecWaterOutdoor_FP'));
      expect(aliases, containsPair('TerrainLake_NoFresnel', 'LowSpecWaterOutdoor_FP'));
      expect(aliases, containsPair('TerrainWater_OnlySky', 'LowSpecWaterOutdoor_FP'));
      expect(aliases, containsPair('WaterVolume', 'LowSpecWaterIndoor_FP'));
      expect(aliases, containsPair('TemplBumpDiffuse', 'TemplDiffuse_FP'));
      expect(aliases, containsPair('TemplAlphaBlend', 'TemplAlphaBlend_FP'));
    });

    test('strips inline comments (;)', () {
      final pairs = parseCustomAliases(_sampleAliases);
      final cgrcp = pairs.where((p) => p.alias == 'CGRCFlare').single;
      expect(cgrcp.target, equals('CGRCFlare'));
    });

    test('skips pure comment lines', () {
      final pairs = parseCustomAliases(_sampleAliases);
      expect(pairs.any((p) => p.alias.startsWith(';')), isFalse);
    });

    test('deduplicates: first occurrence wins', () {
      final pairs = parseCustomAliases(_sampleAliases);
      final lakePairs = pairs.where((p) => p.alias.toLowerCase() == 'terrainlake').toList();
      expect(lakePairs.length, equals(1));
      expect(lakePairs.first.target, equals('LowSpecWaterOutdoor_FP'));
    });

    test(
        'buildManifestLookupAliasesByTargetFromCustomAliasPairs folds outdoor/indoor water to CGRC fragments',
        () {
      final pairs = parseCustomAliases(_sampleAliases);
      final map = buildManifestLookupAliasesByTargetFromCustomAliasPairs(pairs);
      expect(map['cgrclowmedwater'], contains('terrainwater_onlysky'));
      expect(map['cgrclowmedwater'], contains('terrainlake'));
      expect(map['cgrcindoorwater'], contains('watervolume'));
    });

    test('mergeManifestLookupAliasMaps merges without duplicate aliases per target',
        () {
      final a = <String, List<String>>{
        'cgrcflare': <String>['crylight'],
      };
      final b = <String, List<String>>{
        'cgrcflare': <String>['crylight'],
        'cgrclowmedwater': <String>['terrainwater_onlysky'],
      };
      final m = mergeManifestLookupAliasMaps(a, b);
      expect(m['cgrcflare'], equals(<String>['crylight']));
      expect(m['cgrclowmedwater'], contains('terrainwater_onlysky'));
    });

    test('returns empty list for empty input', () {
      expect(parseCustomAliases(''), isEmpty);
    });

    test('preserves original alias casing', () {
      final pairs = parseCustomAliases(_sampleAliases);
      expect(pairs.map((p) => p.alias), contains('TerrainLake_NoFresnel'));
    });
  });

  group('auditAliases', () {
    final manifestNames = <String>{
      'cgrcflare',
      'cgrcambienttempl',
      'cgrcambient',
      'cgrclowmedwater',
      'cgrcindoorwater',
    };

    test(
        'resolves LowSpecWaterOutdoor_FP targets to cgrclowmedwater when present in manifest',
        () {
      final pairs = [const AliasPair('TerrainLake', 'LowSpecWaterOutdoor_FP', '')];
      final results = auditAliases(pairs, manifestNames);
      expect(results.single.metalTarget, equals('cgrclowmedwater'));
    });

    test('resolves alias whose target is directly in the manifest', () {
      final pairs = [const AliasPair('Flare_training', 'CGRCFlare', '')];
      final results = auditAliases(pairs, manifestNames);
      expect(results.single.metalTarget, equals('cgrcflare'));
    });

    test('resolves alias whose target is a Metal builtin', () {
      final pairs = [const AliasPair('02_Carrier', 'basic', '')];
      final results = auditAliases(pairs, manifestNames);
      expect(results.single.metalTarget, equals('basic'));
    });

    test('returns null metalTarget for genuinely unresolved alias', () {
      final pairs = [const AliasPair('FakeShader', 'UnknownTarget', '')];
      final results = auditAliases(pairs, manifestNames);
      expect(results.single.metalTarget, isNull);
    });

    test('resolves chain: alias → LowSpecWaterOutdoor_FP → cgrclowmedwater', () {
      final pairs = [const AliasPair('TerrainWater_OnlySky', 'LowSpecWaterOutdoor_FP', '')];
      final results = auditAliases(pairs, manifestNames);
      expect(results.single.metalTarget, equals('cgrclowmedwater'));
    });

    test('resolves WaterVolume via LowSpecWaterIndoor_FP → cgrcindoorwater', () {
      final pairs = [const AliasPair('WaterVolume', 'LowSpecWaterIndoor_FP', '')];
      final results = auditAliases(pairs, manifestNames);
      expect(results.single.metalTarget, equals('cgrcindoorwater'));
    });

    test('all known builtins resolve to themselves', () {
      for (final b in kMetalBuiltins) {
        final pairs = [AliasPair('SomeAlias', b, '')];
        final results = auditAliases(pairs, manifestNames);
        expect(results.single.metalTarget, equals(b), reason: 'builtin: $b');
      }
    });
  });

  group('Aliases.txt committed entries — strict regression', () {
    // Locate the project root regardless of where the test process is
    // launched from by walking up from Directory.current until a directory
    // containing BOTH `tools/shader_port` and `Assets/Shaders` is found.
    File _findAliasesTxt() {
      Directory dir = Directory.current;
      for (int i = 0; i < 10; i++) {
        final bool isRoot =
            Directory('${dir.path}/tools/shader_port').existsSync() &&
                Directory('${dir.path}/Assets/Shaders').existsSync();
        if (isRoot) {
          return File('${dir.path}/Assets/Shaders/Source/Shaders/Aliases.txt');
        }
        final Directory parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      throw StateError(
          'Could not locate project root containing tools/shader_port and Assets/Shaders');
    }

    test('contains CryLight -> CGRCFlare (lens flare alias)', () {
      final File aliases = _findAliasesTxt();
      expect(aliases.existsSync(), isTrue,
          reason: 'Aliases.txt must exist at Assets/Shaders/Source/Shaders/Aliases.txt');
      final List<AliasesTxtEntry> entries =
          parseAliasesTxt(aliases.readAsStringSync());
      final AliasesTxtEntry? crylight = entries
          .where((e) => e.alias.toLowerCase() == 'crylight')
          .firstOrNull;
      expect(crylight, isNotNull,
          reason: 'CryLight alias must be present so the engine\'s '
              'LoadRendererShaderSafe("CryLight") call resolves');
      expect(crylight!.target, equalsIgnoringCase('CGRCFlare'),
          reason: 'CryLight is the legacy name of the lens-flare shader '
              'whose Metal counterpart is CGRCFlare (manifest normalized: cgrcflare)');
    });

    test('CryLight alias produces lookupAliases entry on cgrcflare target', () {
      final File aliases = _findAliasesTxt();
      final Map<String, List<String>> byTarget =
          buildManifestLookupAliasesByTargetFromEntries(
              parseAliasesTxt(aliases.readAsStringSync()));
      expect(byTarget['cgrcflare'], contains('crylight'),
          reason: 'parser+builder must emit crylight under target cgrcflare so '
              'the manifest fragment receives it via lookupAliases');
    });

    test('contains Default -> CGRCDefault (engine default material alias)', () {
      final File aliases = _findAliasesTxt();
      final List<AliasesTxtEntry> entries =
          parseAliasesTxt(aliases.readAsStringSync());
      final AliasesTxtEntry? def = entries
          .where((e) => e.alias.toLowerCase() == 'default')
          .firstOrNull;
      expect(def, isNotNull,
          reason: 'Default alias must be present so '
              'LoadRendererShaderSafe("Default") resolves');
      expect(def!.target, equalsIgnoringCase('CGRCDefault'),
          reason: 'engine\'s "Default" is the canonical default material '
              'shader; its Metal port is CGRCDefault. Mapping to '
              'cgrcambienttempl/basic is forbidden by the strict policy.');
    });

    test('Default alias produces lookupAliases entry on cgrcdefault target',
        () {
      final File aliases = _findAliasesTxt();
      final Map<String, List<String>> byTarget =
          buildManifestLookupAliasesByTargetFromEntries(
              parseAliasesTxt(aliases.readAsStringSync()));
      expect(byTarget['cgrcdefault'], contains('default'),
          reason: 'parser+builder must emit default under target cgrcdefault');
    });

    test('contains ScreenTexMap -> CGRCScreenTexMap (screen blit alias)', () {
      final File aliases = _findAliasesTxt();
      final List<AliasesTxtEntry> entries =
          parseAliasesTxt(aliases.readAsStringSync());
      final AliasesTxtEntry? row = entries
          .where((e) => e.alias.toLowerCase() == 'screentexmap')
          .firstOrNull;
      expect(row, isNotNull,
          reason: 'ScreenTexMap alias must be present so '
              'LoadRendererShaderSafe("ScreenTexMap") resolves on Metal');
      expect(row!.target, equalsIgnoringCase('CGRCScreenTexMap'),
          reason: 'logical ScreenTexMap maps to ported fragment CGRCScreenTexMap');
    });

    test('ScreenTexMap alias produces lookupAliases entry on cgrcscreentexmap',
        () {
      final File aliases = _findAliasesTxt();
      final Map<String, List<String>> byTarget =
          buildManifestLookupAliasesByTargetFromEntries(
              parseAliasesTxt(aliases.readAsStringSync()));
      expect(byTarget['cgrcscreentexmap'], contains('screentexmap'),
          reason: 'manifest lookupAliases must register normalized engine name');
    });

    test('contains ParticleLight -> CGRCParticleLight (decal particle light)',
        () {
      final File aliases = _findAliasesTxt();
      final List<AliasesTxtEntry> entries =
          parseAliasesTxt(aliases.readAsStringSync());
      final AliasesTxtEntry? row = entries
          .where((e) => e.alias.toLowerCase() == 'particlelight')
          .firstOrNull;
      expect(row, isNotNull,
          reason: 'ParticleLight must alias for CDecalManager EF_SYSTEM load');
      expect(row!.target, equalsIgnoringCase('CGRCParticleLight'),
          reason: 'Metal port fragment CGRCParticleLight');
    });

    test('ParticleLight alias produces lookupAliases on cgrcparticlelight',
        () {
      final File aliases = _findAliasesTxt();
      final Map<String, List<String>> byTarget =
          buildManifestLookupAliasesByTargetFromEntries(
              parseAliasesTxt(aliases.readAsStringSync()));
      expect(byTarget['cgrcparticlelight'], contains('particlelight'));
    });

    test('contains BumpSunGlow -> CGRCBumpSunGlow (terrain sun road EF_SYSTEM)',
        () {
      final File aliases = _findAliasesTxt();
      final List<AliasesTxtEntry> entries =
          parseAliasesTxt(aliases.readAsStringSync());
      final AliasesTxtEntry? row = entries
          .where((e) => e.alias.toLowerCase() == 'bumpsunglow')
          .firstOrNull;
      expect(row, isNotNull,
          reason: 'BumpSunGlow must alias for terrain_water_quad EF_SYSTEM load');
      expect(row!.target, equalsIgnoringCase('CGRCBumpSunGlow'),
          reason: 'Metal port fragment CGRCBumpSunGlow');
    });

    test('BumpSunGlow alias produces lookupAliases on cgrcbumpsunglow', () {
      final File aliases = _findAliasesTxt();
      final Map<String, List<String>> byTarget =
          buildManifestLookupAliasesByTargetFromEntries(
              parseAliasesTxt(aliases.readAsStringSync()));
      expect(byTarget['cgrcbumpsunglow'], contains('bumpsunglow'));
    });

    test('contains Decal_VP -> CGVProgDecal', () {
      final File aliases = _findAliasesTxt();
      final List<AliasesTxtEntry> entries =
          parseAliasesTxt(aliases.readAsStringSync());
      final AliasesTxtEntry? row = entries
          .where((e) => e.alias.toLowerCase() == 'decal_vp')
          .firstOrNull;
      expect(row, isNotNull);
      expect(row!.target, equalsIgnoringCase('CGVProgDecal'));
    });

    test('Decal_VP alias produces lookupAliases on cgvprogdecal', () {
      final File aliases = _findAliasesTxt();
      final Map<String, List<String>> byTarget =
          buildManifestLookupAliasesByTargetFromEntries(
              parseAliasesTxt(aliases.readAsStringSync()));
      expect(byTarget['cgvprogdecal'], contains('decal_vp'));
    });

    test('contains Decal_2D_VP -> CGVProgDecal_2D_Atten', () {
      final File aliases = _findAliasesTxt();
      final List<AliasesTxtEntry> entries =
          parseAliasesTxt(aliases.readAsStringSync());
      final AliasesTxtEntry? row = entries
          .where((e) => e.alias.toLowerCase() == 'decal_2d_vp')
          .firstOrNull;
      expect(row, isNotNull);
      expect(row!.target, equalsIgnoringCase('CGVProgDecal_2D_Atten'));
    });

    test('Decal_2D_VP alias produces lookupAliases on cgvprogdecal_2d_atten',
        () {
      final File aliases = _findAliasesTxt();
      final Map<String, List<String>> byTarget =
          buildManifestLookupAliasesByTargetFromEntries(
              parseAliasesTxt(aliases.readAsStringSync()));
      expect(byTarget['cgvprogdecal_2d_atten'], contains('decal_2d_vp'));
    });

    test('Aliases.txt template targets fold onto CGRC manifest keys', () {
      final File aliases = _findAliasesTxt();
      final Map<String, List<String>> byTarget =
          buildManifestLookupAliasesByTargetFromEntries(
              parseAliasesTxt(aliases.readAsStringSync()));
      expect(byTarget.containsKey('templbumpspec'), isFalse);
      expect(byTarget['cgrcbump_diffspec_singlelight_ps20'], contains('tbumpspec'));
      expect(byTarget['cgrcbump_diff'], contains('tbd'));
    });
  });

  group('integration: known missing aliases in NV1X block', () {
    const input = '''
{
  GPU = NV1X

  TerrainLake LowSpecWaterOutdoor_FP
  TerrainLake_NoFresnel LowSpecWaterOutdoor_FP
  TerrainLake_Deformed  LowSpecWaterOutdoor_FP
  TerrainWater_OnlySky  LowSpecWaterOutdoor_FP
  TerrainDeepWater  LowSpecWaterOutdoor_FP
  TerrainOcean2 LowSpecWaterOutdoor_FP
  TerrainWater_TempleRiver LowSpecWaterOutdoor_FP
  TerrainRiver  LowSpecWaterOutdoor_FP
  WaterVolumeBumpReflCM LowSpecWaterIndoor_FP
}
''';

    test(
        'NV1X water aliases resolve to cgrclowmedwater / cgrcindoorwater when in manifest',
        () {
      final pairs = parseCustomAliases(input);
      final manifest = <String>{'cgrclowmedwater', 'cgrcindoorwater'};
      final results = auditAliases(pairs, manifest);
      for (final r in results) {
        final String low = r.alias.toLowerCase();
        if (low == 'watervolumebumpreflcm') {
          expect(r.metalTarget, equals('cgrcindoorwater'),
              reason: '${r.alias} -> ${r.rawTarget}');
        } else {
          expect(r.metalTarget, equals('cgrclowmedwater'),
              reason: '${r.alias} -> ${r.rawTarget}');
        }
      }
    });
  });
}
