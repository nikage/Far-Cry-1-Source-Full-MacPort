import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> _runBuildMetal(List<String> args) =>
    Process.run(
      'dart',
      ['run', 'lib/build_metal.dart', ...args],
      workingDirectory: Directory.current.path,
    );

void main() {
  group('build_metal.dart path construction / guard checks', () {
    test('exits 1 with usage message when fewer than 4 args are given', () async {
      final ProcessResult r = await _runBuildMetal(['a', 'b', 'c']);
      expect(r.exitCode, 1);
      expect((r.stderr as String), contains('Usage'));
    });

    test('exits 1 when generated directory does not exist', () async {
      final ProcessResult r = await _runBuildMetal([
        '.',
        '/nonexistent/generated',
        '/tmp/air',
        '/tmp/output.metallib',
      ]);
      expect(r.exitCode, 1);
      expect((r.stderr as String).toLowerCase(), contains('not found'));
    });

    test('exits 1 when manifest is missing in generated dir', () async {
      final Directory tmp =
          Directory.systemTemp.createTempSync('build_metal_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final Directory genDir = Directory('${tmp.path}/Generated')
        ..createSync(recursive: true);

      final ProcessResult r = await _runBuildMetal([
        '.',
        genDir.path,
        '${tmp.path}/air',
        '${tmp.path}/output.metallib',
      ]);
      expect(r.exitCode, 1);
      expect((r.stderr as String).toLowerCase(), contains('manifest'));
    });

    test('exits 1 when manifest is empty', () async {
      final Directory tmp =
          Directory.systemTemp.createTempSync('build_metal_test2_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final Directory genDir = Directory('${tmp.path}/Generated')
        ..createSync(recursive: true);
      File('${genDir.path}/generated_manifest.json')
          .writeAsStringSync('[]');

      final ProcessResult r = await _runBuildMetal([
        '.',
        genDir.path,
        '${tmp.path}/air',
        '${tmp.path}/output.metallib',
      ]);
      expect(r.exitCode, 1);
      expect((r.stderr as String).toLowerCase(), contains('empty'));
    });

    test('exits 1 when a metal file listed in manifest does not exist', () async {
      final Directory tmp =
          Directory.systemTemp.createTempSync('build_metal_test3_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final Directory genDir = Directory('${tmp.path}/Generated')
        ..createSync(recursive: true);
      File('${genDir.path}/generated_manifest.json').writeAsStringSync(
        jsonEncode([
          {'metal': 'CGVShaders/missing.metal', 'stage': 'vertex', 'shader': 'X'},
        ]),
      );

      final ProcessResult r = await _runBuildMetal([
        '.',
        genDir.path,
        '${tmp.path}/air',
        '${tmp.path}/output.metallib',
      ]);
      expect(r.exitCode, isNot(0));
    });
  });
}
