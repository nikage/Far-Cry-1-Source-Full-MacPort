import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

List<Map<String, dynamic>> _loadManifest() {
  final File f = File(
    p.join(Directory.current.path, '..', '..', 'RenderDll', 'XRenderMetal',
        'Generated', 'generated_manifest.json'),
  );
  if (!f.existsSync()) {
    throw TestFailure(
        'generated_manifest.json not found at ${f.path}. '
        'Run the Dart pipeline to generate it first.');
  }
  final dynamic decoded = jsonDecode(f.readAsStringSync());
  if (decoded is! List) throw TestFailure('Manifest must be a JSON array');
  return decoded.cast<Map<String, dynamic>>();
}

void main() {
  group('generated_manifest.json', () {
    late List<Map<String, dynamic>> manifest;

    setUpAll(() {
      manifest = _loadManifest();
    });

    test('is non-empty', () {
      expect(manifest, isNotEmpty);
    });

    test('every entry has required fields', () {
      const List<String> required = [
        'source',
        'metal',
        'shader',
        'normalized',
        'entryPoint',
        'stage',
      ];
      for (final Map<String, dynamic> entry in manifest) {
        for (final String field in required) {
          expect(
            entry[field],
            isNotNull,
            reason: 'entry "${entry['shader']}" missing required field "$field"',
          );
          expect(
            entry[field],
            isA<String>(),
            reason: 'entry "${entry['shader']}" field "$field" must be a String',
          );
          expect(
            (entry[field] as String).trim(),
            isNotEmpty,
            reason: 'entry "${entry['shader']}" field "$field" must be non-empty',
          );
        }
      }
    });

    test('stage is only "vertex" or "fragment"', () {
      for (final Map<String, dynamic> entry in manifest) {
        expect(
          entry['stage'],
          anyOf('vertex', 'fragment'),
          reason: 'entry "${entry['shader']}" has invalid stage "${entry['stage']}"',
        );
      }
    });

    test('has both vertex and fragment entries', () {
      final int vertexCount =
          manifest.where((e) => e['stage'] == 'vertex').length;
      final int fragmentCount =
          manifest.where((e) => e['stage'] == 'fragment').length;
      expect(vertexCount, greaterThan(0),
          reason: 'Expected at least one vertex shader entry');
      expect(fragmentCount, greaterThan(0),
          reason: 'Expected at least one fragment shader entry');
    });

    test('normalized names are all lowercase', () {
      for (final Map<String, dynamic> entry in manifest) {
        final String norm = entry['normalized'] as String;
        expect(
          norm,
          equals(norm.toLowerCase()),
          reason:
              'entry "${entry['shader']}" normalized name "$norm" must be lowercase',
        );
      }
    });

    test('vertex entries have entryPoint ending with _vertex', () {
      final Iterable<Map<String, dynamic>> vertices =
          manifest.where((e) => e['stage'] == 'vertex');
      for (final Map<String, dynamic> e in vertices) {
        expect(
          (e['entryPoint'] as String).endsWith('_vertex'),
          isTrue,
          reason:
              'vertex entry "${e['shader']}" entryPoint "${e['entryPoint']}" should end with "_vertex"',
        );
      }
    });

    test('fragment entries have entryPoint ending with _fragment', () {
      final Iterable<Map<String, dynamic>> fragments =
          manifest.where((e) => e['stage'] == 'fragment');
      for (final Map<String, dynamic> e in fragments) {
        expect(
          (e['entryPoint'] as String).endsWith('_fragment'),
          isTrue,
          reason:
              'fragment entry "${e['shader']}" entryPoint "${e['entryPoint']}" should end with "_fragment"',
        );
      }
    });

    test('metal file names are derived from source', () {
      for (final Map<String, dynamic> entry in manifest) {
        final String metal = entry['metal'] as String;
        expect(
          metal.endsWith('.metal'),
          isTrue,
          reason: 'entry "${entry['shader']}" metal field "$metal" must end with .metal',
        );
      }
    });

    test('uniformCount is a non-negative integer', () {
      for (final Map<String, dynamic> entry in manifest) {
        if (entry.containsKey('uniformCount')) {
          expect(
            entry['uniformCount'],
            isA<int>(),
            reason: 'entry "${entry['shader']}" uniformCount must be int',
          );
          expect(
            (entry['uniformCount'] as int) >= 0,
            isTrue,
            reason: 'entry "${entry['shader']}" uniformCount must be >= 0',
          );
        }
      }
    });

    test('textureCount is a non-negative integer', () {
      for (final Map<String, dynamic> entry in manifest) {
        if (entry.containsKey('textureCount')) {
          expect(
            entry['textureCount'],
            isA<int>(),
            reason: 'entry "${entry['shader']}" textureCount must be int',
          );
          expect(
            (entry['textureCount'] as int) >= 0,
            isTrue,
            reason: 'entry "${entry['shader']}" textureCount must be >= 0',
          );
        }
      }
    });

    test('vertex entries have vertexAttributes list', () {
      final Iterable<Map<String, dynamic>> vertices =
          manifest.where((e) => e['stage'] == 'vertex');
      for (final Map<String, dynamic> e in vertices) {
        expect(
          e['vertexAttributes'],
          isA<List>(),
          reason: 'vertex entry "${e['shader']}" must have vertexAttributes list',
        );
      }
    });

    test('pipeline metadata is present and has required shape', () {
      const List<String> pipelineKeys = [
        'blendEnabled',
        'depthWrite',
        'depthTest',
        'depthCompare',
        'cullMode',
      ];
      for (final Map<String, dynamic> entry in manifest) {
        if (entry.containsKey('pipeline')) {
          final dynamic pipeline = entry['pipeline'];
          expect(
            pipeline,
            isA<Map>(),
            reason: 'entry "${entry['shader']}" pipeline must be a Map',
          );
          final Map<String, dynamic> pm = (pipeline as Map).cast();
          for (final String key in pipelineKeys) {
            expect(
              pm.containsKey(key),
              isTrue,
              reason:
                  'entry "${entry['shader']}" pipeline missing key "$key"',
            );
          }
        }
      }
    });

    test('no duplicate (normalized, stage) pairs', () {
      final Map<String, int> seen = {};
      for (final Map<String, dynamic> entry in manifest) {
        final String key = '${entry['normalized']}:${entry['stage']}';
        seen[key] = (seen[key] ?? 0) + 1;
      }
      final List<String> dupes =
          seen.entries.where((e) => e.value > 1).map((e) => e.key).toList();
      expect(
        dupes,
        isEmpty,
        reason: 'Duplicate manifest entries found: $dupes',
      );
    });

    test('CGVShaders source files map to vertex stage', () {
      for (final Map<String, dynamic> entry in manifest) {
        final String src = (entry['source'] as String).replaceAll('\\', '/');
        if (src.contains('/CGVShaders/')) {
          expect(
            entry['stage'],
            'vertex',
            reason:
                'Source "${entry['source']}" is in CGVShaders but stage is "${entry['stage']}"',
          );
        }
      }
    });

    test('CGPShaders source files map to fragment stage', () {
      for (final Map<String, dynamic> entry in manifest) {
        final String src = (entry['source'] as String).replaceAll('\\', '/');
        if (src.contains('/CGPShaders/')) {
          expect(
            entry['stage'],
            'fragment',
            reason:
                'Source "${entry['source']}" is in CGPShaders but stage is "${entry['stage']}"',
          );
        }
      }
    });
  });
}
