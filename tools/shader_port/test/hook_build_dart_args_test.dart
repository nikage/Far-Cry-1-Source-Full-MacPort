import 'package:test/test.dart';

import '../bin/hook_validate_migration.dart';

void main() {
  group('buildDartArgs', () {
    test('plain dart bin produces [run, script, root]', () {
      expect(
        buildDartArgs('dart', 'validate_migration.dart', '/project'),
        ['run', 'validate_migration.dart', '/project'],
      );
    });

    test('fvm dart bin prepends the fvm sub-command', () {
      expect(
        buildDartArgs('fvm dart', 'validate_migration.dart', '/project'),
        ['dart', 'run', 'validate_migration.dart', '/project'],
      );
    });

    test('result always contains script path', () {
      final List<String> args =
          buildDartArgs('dart', '/path/to/validate.dart', '.');
      expect(args, contains('/path/to/validate.dart'));
    });

    test('result always contains project root', () {
      final List<String> args =
          buildDartArgs('dart', 'validate.dart', '/some/root');
      expect(args, contains('/some/root'));
    });

    test('result always contains run subcommand', () {
      final List<String> args =
          buildDartArgs('dart', 'validate.dart', '/root');
      expect(args, contains('run'));
    });

    test('no empty strings in result', () {
      final List<String> args =
          buildDartArgs('dart', 'validate.dart', '/root');
      expect(args.where((s) => s.isEmpty), isEmpty);
    });

    test('fvm dart result contains no empty strings', () {
      final List<String> args =
          buildDartArgs('fvm dart', 'validate.dart', '/root');
      expect(args.where((s) => s.isEmpty), isEmpty);
    });
  });

  group('isRelevantChange — output/ir detection', () {
    test('returns true when an output/ir JSON file changed', () {
      expect(
        isRelevantChange([
          'tools/shader_port/output/ir/CGVShaders/CGVProgAmbientTempl.crycg.json',
        ]),
        isTrue,
      );
    });

    test('returns false for unrelated files even with similar names', () {
      expect(
        isRelevantChange(['some/other/path/data.json']),
        isFalse,
      );
    });
  });
}
