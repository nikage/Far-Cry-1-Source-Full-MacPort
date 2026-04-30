import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Directory? _tempDir;

Future<ProcessResult> _runCompileCheck(List<String> args) =>
    Process.run(
      'dart',
      ['run', 'bin/compile_check.dart', ...args],
      workingDirectory: Directory.current.path,
    );

void main() {
  setUp(() {
    _tempDir = Directory.systemTemp.createTempSync('compile_check_cli_test_');
  });

  tearDown(() {
    _tempDir?.deleteSync(recursive: true);
    _tempDir = null;
  });

  group('compile_check.dart CLI', () {
    test('exits 1 when generated directory does not exist', () async {
      final ProcessResult r = await _runCompileCheck([
        '--generated-dir',
        '${_tempDir!.path}/nonexistent',
      ]);
      expect(r.exitCode, 1);
      expect((r.stderr as String).toLowerCase(), contains('not found'));
    });

    test('exits 1 when generated directory exists but manifest is missing', () async {
      final Directory genDir = Directory(
        '${_tempDir!.path}/Generated',
      )..createSync(recursive: true);

      final ProcessResult r = await _runCompileCheck([
        '--generated-dir',
        genDir.path,
      ]);
      expect(r.exitCode, 1);
      expect((r.stderr as String).toLowerCase(), contains('manifest'));
    });

    test('exits 1 when manifest is empty', () async {
      final Directory genDir = Directory(
        '${_tempDir!.path}/Generated',
      )..createSync(recursive: true);
      File('${genDir.path}/generated_manifest.json').writeAsStringSync('[]');

      final ProcessResult r = await _runCompileCheck([
        '--generated-dir',
        genDir.path,
      ]);
      expect(r.exitCode, 1);
      expect((r.stderr as String).toLowerCase(), contains('empty'));
    });

    test('exits 1 when manifest has entries but no metal files exist', () async {
      final Directory genDir = Directory(
        '${_tempDir!.path}/Generated',
      )..createSync(recursive: true);

      final List<Map<String, dynamic>> manifest = [
        {
          'metal': 'Shaders/nonexistent.metal',
          'stage': 'vertex',
          'shader': 'TestShader',
        },
      ];
      File('${genDir.path}/generated_manifest.json')
          .writeAsStringSync(jsonEncode(manifest));

      final ProcessResult r = await _runCompileCheck([
        '--generated-dir',
        genDir.path,
      ]);
      expect(r.exitCode, 1);
      expect((r.stderr as String).toLowerCase(), contains('no metal files'));
    });

    test('skips malformed manifest entries with WARN and continues', () async {
      final Directory genDir = Directory(
        '${_tempDir!.path}/Generated',
      )..createSync(recursive: true);

      File('${genDir.path}/generated_manifest.json')
          .writeAsStringSync('[42, "bad"]');

      final ProcessResult r = await _runCompileCheck([
        '--generated-dir',
        genDir.path,
      ]);
      expect(r.stderr as String, contains('WARN'));
    });
  });
}
