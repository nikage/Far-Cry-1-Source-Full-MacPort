import 'dart:io';

import 'package:test/test.dart';

import '../lib/pair_validator.dart';

List<Map<String, dynamic>> _manifest({
  List<Map<String, dynamic>> extras = const [],
}) {
  return [
    {
      'shader': 'CGVProgSimple',
      'normalized': 'cgvprogsimple',
      'stage': 'vertex',
      'entryPoint': 'generated_cgvprogsimple_vertex',
      'pipelineCategory': 'mesh',
      'vertexOutputs': [
        {'name': 'Tex0', 'components': 2},
        {'name': 'Color', 'components': 4},
      ],
    },
    {
      'shader': 'CGVProgScreen',
      'normalized': 'cgvprogscreen',
      'stage': 'vertex',
      'entryPoint': 'generated_cgvprogscreen_vertex',
      'pipelineCategory': 'fullscreen',
      'vertexOutputs': [
        {'name': 'Tex0', 'components': 2},
      ],
    },
    ...extras,
  ];
}

void main() {
  group('pair_validator — Rule 1 (every non-fullscreen fragment must be paired)', () {
    test('passes when all fragments have vertexEntryPoint', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCAmbient',
          'normalized': 'cgrcambient',
          'stage': 'fragment',
          'entryPoint': 'CGRCAmbient_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          'vertexAttributes': [],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.passed, isTrue);
      expect(r.errors, isEmpty);
      expect(r.pairedFragments, 1);
    });

    test('passes when fullscreen fragment has no vertexEntryPoint', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRC_HDR_Bloom_PS20',
          'normalized': 'cgrc_hdr_bloom_ps20',
          'stage': 'fragment',
          'entryPoint': 'cgrc_hdr_bloom_ps20_frag',
          'pipelineCategory': 'fullscreen',
          'vertexAttributes': [],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.passed, isTrue);
      expect(r.fullscreenFragments, 1);
      expect(r.pairedFragments, 0);
    });

    test('fails when mesh fragment has no vertexEntryPoint', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCMissingPair',
          'normalized': 'cgrcmissingpair',
          'stage': 'fragment',
          'entryPoint': 'cgrcmissingpair_frag',
          'pipelineCategory': 'mesh',
          'vertexAttributes': [],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.passed, isFalse);
      expect(r.errors, hasLength(1));
      expect(r.errors.first.rule, '1');
      expect(r.errors.first.shader, 'CGRCMissingPair');
    });

    test('fails for every unpaired non-fullscreen fragment', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCX',
          'normalized': 'cgrcx',
          'stage': 'fragment',
          'entryPoint': 'cgrcx_frag',
          'pipelineCategory': 'mesh',
          'vertexAttributes': [],
        },
        {
          'shader': 'CGRCY',
          'normalized': 'cgrcy',
          'stage': 'fragment',
          'entryPoint': 'cgrcy_frag',
          'pipelineCategory': 'shadow',
          'vertexAttributes': [],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.errors.where((e) => e.rule == '1'), hasLength(2));
    });
  });

  group('pair_validator — Rule 2 (vertexEntryPoint must reference a real vertex)', () {
    test('passes when vertexEntryPoint exists', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCGood',
          'normalized': 'cgrcgood',
          'stage': 'fragment',
          'entryPoint': 'cgrcgood_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          'vertexAttributes': [],
        },
      ]);
      expect(validate(m).passed, isTrue);
    });

    test('fails when vertexEntryPoint references nonexistent vertex', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCBad',
          'normalized': 'cgrcbad',
          'stage': 'fragment',
          'entryPoint': 'cgrcbad_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_doesnotexist_vertex',
          'vertexAttributes': [],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.passed, isFalse);
      expect(r.errors.first.rule, '2');
      expect(r.errors.first.message, contains('doesnotexist'));
    });
  });

  group('pair_validator — Rule 3 (structural compatibility warnings)', () {
    test('no warning when VS outputs cover FS varyings', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCMatched',
          'normalized': 'cgrcmatched',
          'stage': 'fragment',
          'entryPoint': 'cgrcmatched_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          'vertexAttributes': ['Tex0', 'Color'],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.passed, isTrue);
      expect(r.warnings, isEmpty);
    });

    test('warning when FS needs named varying not in VS outputs', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCMismatch',
          'normalized': 'cgrcmismatch',
          'stage': 'fragment',
          'entryPoint': 'cgrcmismatch_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          // "ShadowTc" and "ReflTc" are custom varyings not in the VS outputs.
          'vertexAttributes': ['ShadowTc', 'ReflTc'],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.passed, isTrue);
      expect(r.warnings, isNotEmpty);
      expect(r.warnings.first.rule, '3');
    });

    test('standard CG semantics are not flagged as missing', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCSemantics',
          'normalized': 'cgrcsemantics',
          'stage': 'fragment',
          'entryPoint': 'cgrcsemantics_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          'vertexAttributes': ['POSITION_3', 'TEXCOORD0_2', 'COLOR0_4'],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.warnings, isEmpty);
    });
  });

  group('pair_validator — Rule 3c (component-count mismatch warnings)', () {
    test('no warning when FS metadata component counts match VS outputs', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCMatchedCounts',
          'normalized': 'cgrcmatchedcounts',
          'stage': 'fragment',
          'entryPoint': 'cgrcmatchedcounts_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          'vertexAttributes': ['Tex0'],
          'vertexAttributeMetadata': [
            {'token': 'Tex0', 'components': 2, 'category': 'texcoord'},
          ],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.passed, isTrue);
      expect(r.warnings.where((w) => w.rule == '3c'), isEmpty);
    });

    test('no warning when VS output exceeds FS metadata component count', () {
      // VS outputs Tex0=2, FS metadata declares Tex0=1 (VS > FS).
      // The generator widens the FS stage_in to match VS, so this is safe.
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCTex2Mismatch',
          'normalized': 'cgrctex2mismatch',
          'stage': 'fragment',
          'entryPoint': 'cgrctex2mismatch_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          'vertexAttributes': ['Tex0'],
          'vertexAttributeMetadata': [
            {'token': 'Tex0', 'components': 1, 'category': 'texcoord'},
          ],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.passed, isTrue);
      expect(r.warnings.where((w) => w.rule == '3c'), isEmpty);
    });

    test('warning when FS metadata has more components than VS output', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCTex0MoreComponents',
          'normalized': 'cgrctex0morecomponents',
          'stage': 'fragment',
          'entryPoint': 'cgrctex0morecomponents_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          'vertexAttributes': ['Tex0'],
          'vertexAttributeMetadata': [
            {'token': 'Tex0', 'components': 4, 'category': 'texcoord'},
          ],
        },
      ]);
      final ValidatorResult r = validate(m);
      final List<ValidationError> rule3c =
          r.warnings.where((w) => w.rule == '3c').toList();
      expect(rule3c, hasLength(1));
      expect(rule3c.first.message, contains('Tex0'));
    });

    test('no warning when FS metadata token not present in VS outputs', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCUnpairedToken',
          'normalized': 'cgrcunpairedtoken',
          'stage': 'fragment',
          'entryPoint': 'cgrcunpairedtoken_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          'vertexAttributes': [],
          'vertexAttributeMetadata': [
            {'token': 'Tex9', 'components': 3, 'category': 'texcoord'},
          ],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.warnings.where((w) => w.rule == '3c'), isEmpty);
    });

    test('no warnings when VS outputs exceed FS metadata in multiple fields', () {
      // VS outputs Tex0=3, Tex1=4; FS metadata declares Tex0=2, Tex1=2 (VS > FS).
      // Both are safe — generator widens FS to match VS for each field.
      final List<Map<String, dynamic>> m = [
        {
          'shader': 'CGVMultiOut',
          'normalized': 'cgvmultiout',
          'stage': 'vertex',
          'entryPoint': 'generated_cgvmultiout_vertex',
          'pipelineCategory': 'mesh',
          'vertexOutputs': [
            {'name': 'Tex0', 'components': 3},
            {'name': 'Tex1', 'components': 4},
          ],
        },
        {
          'shader': 'CGRCMultiMismatch',
          'normalized': 'cgrcmultimismatch',
          'stage': 'fragment',
          'entryPoint': 'cgrcmultimismatch_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvmultiout_vertex',
          'vertexAttributes': [],
          'vertexAttributeMetadata': [
            {'token': 'Tex0', 'components': 2, 'category': 'texcoord'},
            {'token': 'Tex1', 'components': 2, 'category': 'texcoord'},
          ],
        },
      ];
      final ValidatorResult r = validate(m);
      expect(r.warnings.where((w) => w.rule == '3c'), isEmpty);
    });

    test('warning when VS output has fewer components than FS metadata (real blocker)', () {
      // VS outputs Tex0=2; FS metadata declares Tex0=3 (VS < FS).
      // Generator cannot widen VS — Metal will reject the PSO at runtime.
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCTex0Undersupply',
          'normalized': 'cgrctex0undersupply',
          'stage': 'fragment',
          'entryPoint': 'cgrctex0undersupply_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          'vertexAttributes': ['Tex0'],
          'vertexAttributeMetadata': [
            {'token': 'Tex0', 'components': 3, 'category': 'texcoord'},
          ],
        },
      ]);
      final ValidatorResult r = validate(m);
      final List<ValidationError> rule3c =
          r.warnings.where((w) => w.rule == '3c').toList();
      expect(rule3c, hasLength(1));
      expect(rule3c.first.message, contains('Tex0'));
      expect(rule3c.first.message, contains('2'));
      expect(rule3c.first.message, contains('3'));
    });

    test('real-world Refractive mismatch: VS Tex1=float2, FS metadata=float4', () {
      final List<Map<String, dynamic>> m = [
        {
          'shader': 'CGVProgRefractive',
          'normalized': 'cgvprogrefractive',
          'stage': 'vertex',
          'entryPoint': 'generated_cgvprogrefractive_vertex',
          'pipelineCategory': 'mesh',
          'vertexOutputs': [
            {'name': 'Tex0', 'components': 2},
            {'name': 'Tex1', 'components': 2},
          ],
        },
        {
          'shader': 'CGRCRefractive',
          'normalized': 'cgrcrefractive',
          'stage': 'fragment',
          'entryPoint': 'cgrcrefractive_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogrefractive_vertex',
          'vertexAttributes': ['TEXCOORD0_2', 'TEXCOORD1_4'],
          'vertexAttributeMetadata': [
            {'token': 'Tex0', 'components': 2, 'category': 'texcoord'},
            {'token': 'Tex1', 'components': 4, 'category': 'texcoord'},
          ],
        },
      ];
      final ValidatorResult r = validate(m);
      final List<ValidationError> rule3c =
          r.warnings.where((w) => w.rule == '3c').toList();
      expect(rule3c, hasLength(1));
      expect(rule3c.first.message, contains('Tex1'));
      expect(rule3c.first.message, contains('2'));
      expect(rule3c.first.message, contains('4'));
    });
  });

  group('pair_validator — coverage metrics', () {
    test('reports correct totals for mixed manifest', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCPaired',
          'normalized': 'cgrcpaired',
          'stage': 'fragment',
          'entryPoint': 'cgrcpaired_frag',
          'pipelineCategory': 'mesh',
          'vertexEntryPoint': 'generated_cgvprogsimple_vertex',
          'vertexAttributes': [],
        },
        {
          'shader': 'CGRC_HDR_A_PS20',
          'normalized': 'cgrc_hdr_a_ps20',
          'stage': 'fragment',
          'entryPoint': 'cgrc_hdr_a_frag',
          'pipelineCategory': 'fullscreen',
          'vertexAttributes': [],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.totalFragments, 2);
      expect(r.pairedFragments, 1);
      expect(r.fullscreenFragments, 1);
      expect(r.coverageRatio, 1.0);
    });

    test('coverageRatio is 0 when all fragments are unpaired mesh shaders', () {
      final List<Map<String, dynamic>> m = _manifest(extras: [
        {
          'shader': 'CGRCA',
          'normalized': 'cgrca',
          'stage': 'fragment',
          'entryPoint': 'cgrca_frag',
          'pipelineCategory': 'mesh',
          'vertexAttributes': [],
        },
      ]);
      final ValidatorResult r = validate(m);
      expect(r.coverageRatio, 0.0);
    });

    test('empty manifest produces no errors', () {
      expect(validate([]).passed, isTrue);
      expect(validate([]).totalFragments, 0);
    });
  });

  group('pair_validator — real manifest integration', () {
    test('generated_manifest.json passes all rules', () {
      const String manifestPath =
          '../../RenderDll/XRenderMetal/Generated/generated_manifest.json';
      if (!File(manifestPath).existsSync()) {
        markTestSkipped(
            'generated_manifest.json not present; run metal_generator first');
        return;
      }
      final ValidatorResult r = validateManifestFile(manifestPath);
      expect(
        r.errors.where((e) => e.rule != '0').toList(),
        isEmpty,
        reason: 'Pairing errors:\n${r.errors.map((e) => e.toString()).join('\n')}',
      );
      expect(r.coverageRatio, 1.0,
          reason: 'Expected 100% coverage, got '
              '${(r.coverageRatio * 100).toStringAsFixed(1)}%');
    });
  });

  group('validateManifestFile — error paths', () {
    test('returns rule-0 error when file does not exist', () {
      const String missingPath = '/tmp/does_not_exist_manifest_xyz.json';
      final ValidatorResult r = validateManifestFile(missingPath);
      expect(r.passed, isFalse);
      expect(r.errors, hasLength(1));
      expect(r.errors.first.rule, '0');
      expect(r.errors.first.message, contains('not found'));
    });

    test('returns rule-0 error when manifest root is a JSON object, not array', () {
      final Directory tmpDir = Directory.systemTemp.createTempSync('pair_validator_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final File manifestFile = File('${tmpDir.path}/manifest.json')
        ..writeAsStringSync('{"key": "value"}');
      final ValidatorResult r = validateManifestFile(manifestFile.path);
      expect(r.passed, isFalse);
      expect(r.errors.first.rule, '0');
      expect(r.errors.first.message, contains('JSON array'));
    });

    test('returns rule-0 error when manifest root is a JSON number', () {
      final Directory tmpDir = Directory.systemTemp.createTempSync('pair_validator_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final File manifestFile = File('${tmpDir.path}/manifest.json')
        ..writeAsStringSync('42');
      final ValidatorResult r = validateManifestFile(manifestFile.path);
      expect(r.passed, isFalse);
      expect(r.errors.first.rule, '0');
    });

    test('passes with zero errors for an empty JSON array manifest', () {
      final Directory tmpDir = Directory.systemTemp.createTempSync('pair_validator_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final File manifestFile = File('${tmpDir.path}/manifest.json')
        ..writeAsStringSync('[]');
      final ValidatorResult r = validateManifestFile(manifestFile.path);
      expect(r.passed, isTrue);
      expect(r.totalFragments, 0);
    });

    test('non-zero coverageRatio when file not found', () {
      const String missingPath = '/tmp/also_missing_manifest.json';
      final ValidatorResult r = validateManifestFile(missingPath);
      expect(r.totalFragments, 0);
      expect(r.coverageRatio, 1.0);
    });
  });
}
