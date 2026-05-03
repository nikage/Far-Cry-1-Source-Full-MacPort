import 'dart:io';
import 'package:level_validator/level_validator.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: validate_levels <path/to/FCData/Levels>');
    exit(1);
  }

  final levelsDir = Directory(args.first);

  late ValidationReport report;
  try {
    report = validateLevelsDir(levelsDir);
  } on ArgumentError catch (e) {
    stderr.writeln('ERROR: ${e.message}');
    exit(1);
  }

  stdout.writeln('Level PAK validation — ${levelsDir.path}');
  stdout.writeln('${'─' * 60}');

  for (final level in report.levels) {
    final status = level.hasPak ? '✓' : '✗';
    final pakList = level.hasPak ? level.paks.join(', ') : 'NO PAK FILES';
    stdout.writeln('  $status  ${level.name.padRight(20)} $pakList');
  }

  stdout.writeln('${'─' * 60}');
  stdout.writeln('Levels checked: ${report.total}');

  if (!report.passed) {
    stderr.writeln(
      '\nFAILED: ${report.missing.length} level(s) have no *.pak file:',
    );
    for (final level in report.missing) {
      stderr.writeln('  • ${level.name}');
    }
    stderr.writeln(
      '\nEach level folder must contain at least level.pak so that\n'
      'LevelData.xml, terrain data, and mission XML can be found at runtime.',
    );
    exit(1);
  }

  stdout.writeln('\nPASSED: all ${report.total} levels have PAK coverage.');
}
