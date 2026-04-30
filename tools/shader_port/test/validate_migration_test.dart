import 'package:test/test.dart';

import '../bin/validate_migration.dart';

void main() {
  group('runStages', () {
    test('returns 0 when all stages pass', () async {
      final List<String> ran = [];
      final StageRunner runner = (name, exe, args) async {
        ran.add(name);
        return 0;
      };

      final int code = await runStages(
        [
          Stage('generate', 'dart', []),
          Stage('compile-check', 'dart', []),
          Stage('validate-pairs', 'dart', []),
        ],
        runner,
      );

      expect(code, 0);
      expect(ran, ['generate', 'compile-check', 'validate-pairs']);
    });

    test('stops after stage 1 fails and returns its exit code', () async {
      final List<String> ran = [];
      final StageRunner runner = (name, exe, args) async {
        ran.add(name);
        return name == 'generate' ? 1 : 0;
      };

      final int code = await runStages(
        [
          Stage('generate', 'dart', []),
          Stage('compile-check', 'dart', []),
          Stage('validate-pairs', 'dart', []),
        ],
        runner,
      );

      expect(code, 1);
      expect(ran, ['generate']);
    });

    test('stops after stage 2 fails and returns its exit code', () async {
      final List<String> ran = [];
      final StageRunner runner = (name, exe, args) async {
        ran.add(name);
        return name == 'compile-check' ? 1 : 0;
      };

      final int code = await runStages(
        [
          Stage('generate', 'dart', []),
          Stage('compile-check', 'dart', []),
          Stage('validate-pairs', 'dart', []),
        ],
        runner,
      );

      expect(code, 1);
      expect(ran, ['generate', 'compile-check']);
    });

    test('returns non-zero exit code from failing stage verbatim', () async {
      final StageRunner runner = (name, exe, args) async => 2;

      final int code = await runStages(
        [Stage('validate-pairs', 'dart', [])],
        runner,
      );

      expect(code, 2);
    });

    test('passes executable and args to the runner unchanged', () async {
      String? capturedExe;
      List<String>? capturedArgs;
      final StageRunner runner = (name, exe, args) async {
        capturedExe = exe;
        capturedArgs = args;
        return 0;
      };

      await runStages(
        [Stage('check', 'dart', ['run', 'foo.dart', '--verbose'])],
        runner,
      );

      expect(capturedExe, 'dart');
      expect(capturedArgs, ['run', 'foo.dart', '--verbose']);
    });
  });

  group('--skip-generate flag', () {
    test('omits generate stage when skip is true', () async {
      final List<String> ran = [];
      final StageRunner runner = (name, exe, args) async {
        ran.add(name);
        return 0;
      };

      await runStages(
        [
          Stage('compile-check', 'dart', []),
          Stage('validate-pairs', 'dart', []),
        ],
        runner,
      );

      expect(ran, ['compile-check', 'validate-pairs']);
      expect(ran, isNot(contains('generate')));
    });
  });
}
