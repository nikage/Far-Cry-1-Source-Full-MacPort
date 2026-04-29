import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/pipeline.dart' show firstExistingPath;

// -----------------------------------------------------------------------
// SetFog math tests (mirrors MetalBaseRenderer::SetFog + ComputeFogParams)
// fogScale = 1.0 / (fogEnd - fogStart)
// fogBias  = fogEnd / (fogEnd - fogStart)
// Fog factor at distance d: fog = clamp(fogBias - fogScale * d, 0, 1)
//   d = fogStart → fog = 1.0 (fully visible)
//   d = fogEnd   → fog = 0.0 (fully fogged)
// -----------------------------------------------------------------------
double computeFogScale(double fogStart, double fogEnd) {
  final double range = fogEnd - fogStart;
  return range > 0.0001 ? 1.0 / range : 0.0;
}

double computeFogBias(double fogStart, double fogEnd) {
  final double range = fogEnd - fogStart;
  return range > 0.0001 ? fogEnd / range : 1.0;
}

double fogFactor(double fogStart, double fogEnd, double dist) {
  final double scale = computeFogScale(fogStart, fogEnd);
  final double bias = computeFogBias(fogStart, fogEnd);
  return (bias - scale * dist).clamp(0.0, 1.0);
}

void main() {
  group('SetFog math (fogScale / fogBias)', () {
    const double eps = 1e-5;

    test('normal range: start=10 end=200', () {
      const double s = 10.0, e = 200.0, range = 190.0;
      expect(computeFogScale(s, e), closeTo(1.0 / range, eps));
      expect(computeFogBias(s, e), closeTo(e / range, eps));
    });

    test('fog factor is 1.0 at fogStart', () {
      expect(fogFactor(10.0, 200.0, 10.0), closeTo(1.0, eps));
    });

    test('fog factor is 0.0 at fogEnd', () {
      expect(fogFactor(10.0, 200.0, 200.0), closeTo(0.0, eps));
    });

    test('fog factor is 0.5 at midpoint', () {
      expect(fogFactor(0.0, 100.0, 50.0), closeTo(0.5, eps));
    });

    test('fog factor clamps below 0 beyond fogEnd', () {
      expect(fogFactor(0.0, 100.0, 150.0), closeTo(0.0, eps));
    });

    test('fog factor clamps above 1 before fogStart', () {
      expect(fogFactor(50.0, 200.0, 10.0), closeTo(1.0, eps));
    });

    test('degenerate: start == end → scale=0 bias=1 (no fog)', () {
      expect(computeFogScale(100.0, 100.0), closeTo(0.0, eps));
      expect(computeFogBias(100.0, 100.0), closeTo(1.0, eps));
      expect(fogFactor(100.0, 100.0, 50.0), closeTo(1.0, eps));
    });

    test('degenerate: start > end → scale=0 bias=1', () {
      expect(computeFogScale(300.0, 100.0), closeTo(0.0, eps));
      expect(computeFogBias(300.0, 100.0), closeTo(1.0, eps));
    });

    test('start=0 end=500: bias=1.0', () {
      expect(computeFogBias(0.0, 500.0), closeTo(1.0, eps));
    });

    test('start=0 end=500: fog=1 at dist=0', () {
      expect(fogFactor(0.0, 500.0, 0.0), closeTo(1.0, eps));
    });

    test('start=0 end=500: fog=0 at dist=500', () {
      expect(fogFactor(0.0, 500.0, 500.0), closeTo(0.0, eps));
    });

    test('very large range does not overflow', () {
      expect(computeFogScale(0.0, 10000.0), greaterThan(0.0));
      expect(fogFactor(0.0, 10000.0, 5000.0), closeTo(0.5, 0.001));
    });
  });

  // -----------------------------------------------------------------------
  // pipeline.dart firstExistingPath tests
  // -----------------------------------------------------------------------
  group('pipeline.dart firstExistingPath', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pipeline_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('returns first existing path when first candidate exists', () {
      final String first = p.join(tempDir.path, 'first.pak');
      File(first).writeAsStringSync('');
      final String second = p.join(tempDir.path, 'second.pak');

      final String result = firstExistingPath([first, second]);
      expect(result, first);
    });

    test('returns second path when first does not exist', () {
      final String first = p.join(tempDir.path, 'missing.pak');
      final String second = p.join(tempDir.path, 'present.pak');
      File(second).writeAsStringSync('');

      final String result = firstExistingPath([first, second]);
      expect(result, second);
    });

    test('returns last candidate as fallback when none exist', () {
      final String fallback = p.join(tempDir.path, 'fallback.pak');
      final String result = firstExistingPath([
        p.join(tempDir.path, 'missing1.pak'),
        p.join(tempDir.path, 'missing2.pak'),
        fallback,
      ]);
      expect(result, fallback);
    });

    test('works for directories too', () {
      final String dir = p.join(tempDir.path, 'subdir');
      Directory(dir).createSync();

      final String result = firstExistingPath([
        p.join(tempDir.path, 'missing'),
        dir,
      ]);
      expect(result, dir);
    });

    test('prefers Assets/ layout over Legacy/', () {
      final String assetsPath =
          p.join(tempDir.path, 'Assets', 'FCData', 'Shaders.pak');
      final String legacyPath =
          p.join(tempDir.path, 'FCData', 'Shaders.pak');
      Directory(p.dirname(assetsPath)).createSync(recursive: true);
      File(assetsPath).writeAsStringSync('');

      final String result = firstExistingPath([assetsPath, legacyPath]);
      expect(result, assetsPath);
    });

    test('single candidate always returned regardless of existence', () {
      final String only = p.join(tempDir.path, 'only.pak');
      expect(firstExistingPath([only]), only);
    });
  });
}
