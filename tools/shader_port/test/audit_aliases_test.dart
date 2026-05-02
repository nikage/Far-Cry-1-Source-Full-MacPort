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

    test('returns empty list for empty input', () {
      expect(parseCustomAliases(''), isEmpty);
    });

    test('preserves original alias casing', () {
      final pairs = parseCustomAliases(_sampleAliases);
      expect(pairs.map((p) => p.alias), contains('TerrainLake_NoFresnel'));
    });
  });

  group('auditAliases', () {
    final manifestNames = <String>{'cgrcflare', 'cgrcambienttempl', 'cgrcambient'};

    test('resolves alias whose target is a Metal builtin via kIntermediateAliases', () {
      final pairs = [const AliasPair('TerrainLake', 'LowSpecWaterOutdoor_FP', '')];
      final results = auditAliases(pairs, manifestNames);
      expect(results.single.metalTarget, equals('terrain'));
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

    test('resolves chain: alias → intermediate → builtin', () {
      final pairs = [const AliasPair('TerrainWater_OnlySky', 'LowSpecWaterOutdoor_FP', '')];
      final results = auditAliases(pairs, manifestNames);
      expect(results.single.metalTarget, equals('terrain'));
    });

    test('resolves WaterVolume via kIntermediateAliases chain', () {
      final pairs = [const AliasPair('WaterVolume', 'LowSpecWaterIndoor_FP', '')];
      final results = auditAliases(pairs, manifestNames);
      expect(results.single.metalTarget, equals('terrain'));
    });

    test('all known builtins resolve to themselves', () {
      for (final b in kMetalBuiltins) {
        final pairs = [AliasPair('SomeAlias', b, '')];
        final results = auditAliases(pairs, manifestNames);
        expect(results.single.metalTarget, equals(b), reason: 'builtin: $b');
      }
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

    test('all NV1X water aliases resolve via kIntermediateAliases to terrain', () {
      final pairs = parseCustomAliases(input);
      final results = auditAliases(pairs, {});
      for (final r in results) {
        expect(r.metalTarget, equals('terrain'),
            reason: '${r.alias} -> ${r.rawTarget} should resolve to terrain');
      }
    });
  });
}
