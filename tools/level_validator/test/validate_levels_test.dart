import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:level_validator/level_validator.dart';

Directory _makeTempLevelsDir(Map<String, List<String>> levelFiles) {
  final tmp = Directory.systemTemp.createTempSync('level_validator_test_');
  for (final entry in levelFiles.entries) {
    final levelDir = Directory(p.join(tmp.path, entry.key))..createSync();
    for (final filename in entry.value) {
      File(p.join(levelDir.path, filename)).writeAsStringSync('');
    }
  }
  return tmp;
}

void main() {
  group('validateLevelsDir', () {
    test('passes when every level has at least one pak', () {
      final tmp = _makeTempLevelsDir({
        'Boat': ['level.pak', 'levellm.pak', 'loadscreen_boat.dds'],
        'Bunker': ['level.pak'],
      });
      addTearDown(() => tmp.deleteSync(recursive: true));

      final report = validateLevelsDir(tmp);
      expect(report.passed, isTrue);
      expect(report.total, 2);
      expect(report.missing, isEmpty);
    });

    test('fails when a level folder has no pak', () {
      final tmp = _makeTempLevelsDir({
        'Boat': ['level.pak'],
        'Broken': ['LevelData.xml'],
      });
      addTearDown(() => tmp.deleteSync(recursive: true));

      final report = validateLevelsDir(tmp);
      expect(report.passed, isFalse);
      expect(report.missing.map((l) => l.name), contains('Broken'));
    });

    test('reports correct pak names per level', () {
      final tmp = _makeTempLevelsDir({
        'Carrier': ['level.pak', 'levellm.pak'],
      });
      addTearDown(() => tmp.deleteSync(recursive: true));

      final report = validateLevelsDir(tmp);
      final carrier = report.levels.firstWhere((l) => l.name == 'Carrier');
      expect(carrier.paks, containsAll(['level.pak', 'levellm.pak']));
    });

    test('ignores non-directory entries in Levels root', () {
      final tmp = _makeTempLevelsDir({'Dam': ['level.pak']});
      addTearDown(() => tmp.deleteSync(recursive: true));
      File(p.join(tmp.path, 'readme.txt')).writeAsStringSync('');

      final report = validateLevelsDir(tmp);
      expect(report.total, 1);
    });

    test('fails fast when Levels directory does not exist', () {
      expect(
        () => validateLevelsDir(Directory('/nonexistent/path/Levels')),
        throwsArgumentError,
      );
    });

    test('fails when all levels are missing paks', () {
      final tmp = _makeTempLevelsDir({
        'Empty1': ['LevelData.xml'],
        'Empty2': ['loadscreen_empty2.dds'],
      });
      addTearDown(() => tmp.deleteSync(recursive: true));

      final report = validateLevelsDir(tmp);
      expect(report.passed, isFalse);
      expect(report.missing.length, 2);
    });

    test('handles empty Levels directory without crashing', () {
      final tmp = Directory.systemTemp.createTempSync('level_validator_empty_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final report = validateLevelsDir(tmp);
      expect(report.passed, isTrue);
      expect(report.total, 0);
    });
  });
}
