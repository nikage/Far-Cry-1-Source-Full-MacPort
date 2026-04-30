import 'package:test/test.dart';

import '../lib/compile_error_cluster.dart';

void main() {
  group('parseCompilerOutput', () {
    test('parses a standard Metal error line', () {
      const String stderr = '/tmp/foo.metal:12:5: error: use of undeclared identifier \'ModelViewProj\'';
      final List<ShaderCompileError> errors =
          parseCompilerOutput(stderr, '/tmp/foo.metal');
      expect(errors, hasLength(1));
      expect(errors.first.line, 12);
      expect(errors.first.column, 5);
      expect(errors.first.severity, 'error');
      expect(errors.first.message,
          contains('use of undeclared identifier'));
    });

    test('ignores warning lines', () {
      const String stderr =
          '/tmp/foo.metal:3:1: warning: unused variable \'x\'\n'
          '/tmp/foo.metal:5:1: error: expected \';\' after expression';
      final List<ShaderCompileError> errors =
          parseCompilerOutput(stderr, '/tmp/foo.metal');
      expect(errors, hasLength(1));
      expect(errors.first.message, contains("expected ';'"));
    });

    test('ignores note lines', () {
      const String stderr =
          '/tmp/foo.metal:7:1: note: candidate function not viable';
      final List<ShaderCompileError> errors =
          parseCompilerOutput(stderr, '/tmp/foo.metal');
      expect(errors, isEmpty);
    });

    test('returns empty list for empty stderr', () {
      final List<ShaderCompileError> errors =
          parseCompilerOutput('', '/tmp/foo.metal');
      expect(errors, isEmpty);
    });

    test('handles multiple errors', () {
      const String stderr =
          '/tmp/a.metal:1:1: error: undeclared identifier \'foo\'\n'
          '/tmp/a.metal:2:1: error: undeclared identifier \'bar\'';
      final List<ShaderCompileError> errors =
          parseCompilerOutput(stderr, '/tmp/a.metal');
      expect(errors, hasLength(2));
    });
  });

  group('clusterKey', () {
    test('replaces single-quoted tokens with X', () {
      final String key = clusterKey("use of undeclared identifier 'ModelViewProj'");
      expect(key, "use of undeclared identifier 'X'");
    });

    test('replaces double-quoted tokens with X', () {
      final String key = clusterKey('no member named "foo" in struct');
      expect(key, 'no member named "X" in struct');
    });

    test('replaces numbers', () {
      final String key = clusterKey('expected 4 arguments, got 3');
      expect(key, 'expected N arguments, got N');
    });

    test('truncates long messages', () {
      final String long = 'a' * 200;
      expect(clusterKey(long).length, lessThanOrEqualTo(80));
    });

    test('different identifier names produce same cluster key', () {
      final String k1 =
          clusterKey("use of undeclared identifier 'ModelViewProj'");
      final String k2 =
          clusterKey("use of undeclared identifier 'CameraPos'");
      expect(k1, k2);
    });
  });

  group('clusterErrors', () {
    test('groups errors with the same pattern', () {
      final Map<String, List<ShaderCompileError>> byFile = {
        '/tmp/a.metal': [
          const ShaderCompileError(
            file: '/tmp/a.metal',
            line: 1,
            column: 1,
            severity: 'error',
            message: "use of undeclared identifier 'ModelViewProj'",
            raw: '/tmp/a.metal:1:1: error: use of undeclared identifier \'ModelViewProj\'',
          ),
        ],
        '/tmp/b.metal': [
          const ShaderCompileError(
            file: '/tmp/b.metal',
            line: 2,
            column: 1,
            severity: 'error',
            message: "use of undeclared identifier 'CameraPos'",
            raw: '/tmp/b.metal:2:1: error: use of undeclared identifier \'CameraPos\'',
          ),
        ],
      };
      final List<ErrorCluster> clusters = clusterErrors(byFile);
      expect(clusters, hasLength(1));
      expect(clusters.first.count, 2);
      expect(clusters.first.affectedFiles, hasLength(2));
    });

    test('keeps distinct error patterns separate', () {
      final Map<String, List<ShaderCompileError>> byFile = {
        '/tmp/a.metal': [
          const ShaderCompileError(
            file: '/tmp/a.metal',
            line: 1,
            column: 1,
            severity: 'error',
            message: "use of undeclared identifier 'foo'",
            raw: '',
          ),
          const ShaderCompileError(
            file: '/tmp/a.metal',
            line: 2,
            column: 1,
            severity: 'error',
            message: "expected ';' after expression",
            raw: '',
          ),
        ],
      };
      final List<ErrorCluster> clusters = clusterErrors(byFile);
      expect(clusters, hasLength(2));
    });

    test('returns clusters sorted by count descending', () {
      final Map<String, List<ShaderCompileError>> byFile = {
        '/tmp/a.metal': [
          const ShaderCompileError(
            file: '/tmp/a.metal',
            line: 1,
            column: 1,
            severity: 'error',
            message: "expected ';' after expression",
            raw: '',
          ),
        ],
        '/tmp/b.metal': [
          const ShaderCompileError(
            file: '/tmp/b.metal',
            line: 1,
            column: 1,
            severity: 'error',
            message: "use of undeclared identifier 'foo'",
            raw: '',
          ),
          const ShaderCompileError(
            file: '/tmp/b.metal',
            line: 2,
            column: 1,
            severity: 'error',
            message: "use of undeclared identifier 'bar'",
            raw: '',
          ),
        ],
      };
      final List<ErrorCluster> clusters = clusterErrors(byFile);
      expect(clusters.first.count, greaterThanOrEqualTo(clusters.last.count));
    });

    test('returns empty list when no errors', () {
      expect(clusterErrors({}), isEmpty);
    });
  });

  group('runCompileCheck', () {
    test('returns all-passed result when compiler runner emits no errors', () {
      final CompileCheckResult result = runCompileCheck(
        '/generated',
        ['/generated/shader_a.metal', '/generated/shader_b.metal'],
        compilerRunner: (_, __) => '',
      );
      expect(result.allPassed, isTrue);
      expect(result.totalShaders, 2);
      expect(result.failedShaders, 0);
      expect(result.clusters, isEmpty);
    });

    test('counts failures and clusters errors from compiler runner', () {
      final CompileCheckResult result = runCompileCheck(
        '/generated',
        ['/generated/a.metal', '/generated/b.metal'],
        compilerRunner: (String file, _) {
          return '$file:1:1: error: use of undeclared identifier \'ModelViewProj\'';
        },
      );
      expect(result.failedShaders, 2);
      expect(result.clusters, hasLength(1));
      expect(result.clusters.first.count, 2);
    });

    test('does not exit when some shaders fail', () {
      int callCount = 0;
      final CompileCheckResult result = runCompileCheck(
        '/generated',
        ['/generated/a.metal', '/generated/b.metal', '/generated/c.metal'],
        compilerRunner: (String file, _) {
          callCount++;
          if (file.endsWith('a.metal')) {
            return '$file:1:1: error: type \'half4\' cannot be used here';
          }
          return '';
        },
      );
      expect(callCount, 3);
      expect(result.failedShaders, 1);
      expect(result.totalShaders, 3);
    });
  });

  group('formatReport', () {
    test('reports all-passed message when no errors', () {
      final CompileCheckResult result = runCompileCheck(
        '/generated',
        ['/generated/a.metal'],
        compilerRunner: (_, __) => '',
      );
      final String report = formatReport(result);
      expect(report, contains('All shaders compile successfully'));
    });

    test('includes cluster table when errors exist', () {
      final CompileCheckResult result = runCompileCheck(
        '/generated',
        ['/generated/a.metal'],
        compilerRunner: (String file, _) =>
            '$file:1:1: error: use of undeclared identifier \'foo\'',
      );
      final String report = formatReport(result);
      expect(report, contains('Count'));
      expect(report, contains("undeclared identifier"));
    });
  });
}
