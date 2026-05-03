import 'dart:io';
import 'package:path/path.dart' as p;

class LevelResult {
  final String name;
  final List<String> paks;

  const LevelResult({required this.name, required this.paks});

  bool get hasPak => paks.isNotEmpty;
}

class ValidationReport {
  final List<LevelResult> levels;

  const ValidationReport(this.levels);

  List<LevelResult> get missing => levels.where((l) => !l.hasPak).toList();
  bool get passed => missing.isEmpty;
  int get total => levels.length;
}

ValidationReport validateLevelsDir(Directory levelsDir) {
  if (!levelsDir.existsSync()) {
    throw ArgumentError('Levels directory does not exist: ${levelsDir.path}');
  }

  final results = levelsDir
      .listSync()
      .whereType<Directory>()
      .map((dir) {
        final paks = dir
            .listSync()
            .whereType<File>()
            .where((f) => p.extension(f.path).toLowerCase() == '.pak')
            .map((f) => p.basename(f.path))
            .toList()
          ..sort();
        return LevelResult(name: p.basename(dir.path), paks: paks);
      })
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  return ValidationReport(results);
}
