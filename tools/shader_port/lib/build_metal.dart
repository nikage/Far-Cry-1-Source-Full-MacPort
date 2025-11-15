import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length < 4) {
    stderr.writeln('Usage: build_metal.dart <root> <generatedDir> <airDir> <outputMetallib>');
    exit(1);
  }
  final Directory generatedDir = Directory(args[1]);
  final Directory airDir = Directory(args[2]);
  final File metallibFile = File(args[3]);
  if (!generatedDir.existsSync()) {
    stderr.writeln('Generated directory not found: ${generatedDir.path}');
    exit(1);
  }
  airDir.createSync(recursive: true);
  final File manifest = File(generatedDir.path + Platform.pathSeparator + 'generated_manifest.json');
  if (!manifest.existsSync()) {
    stderr.writeln('Manifest not found: ${manifest.path}');
    exit(1);
  }
  final List<dynamic> entries = jsonDecode(manifest.readAsStringSync(encoding: utf8)) as List<dynamic>;
  if (entries.isEmpty) {
    stderr.writeln('Manifest is empty, nothing to compile');
    exit(1);
  }
  final List<String> airFiles = [];
  for (final dynamic entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final String? metalFileName = entry['metal'] as String?;
    if (metalFileName == null || metalFileName.isEmpty) continue;
    final File metalFile = File(generatedDir.path + Platform.pathSeparator + metalFileName);
    if (!metalFile.existsSync()) {
      stderr.writeln('Generated Metal file missing: ${metalFile.path}');
      exit(1);
    }
    final String airName = metalFileName.replaceAll('.metal', '.air');
    final File airFile = File(airDir.path + Platform.pathSeparator + airName);
    final ProcessResult compileResult = Process.runSync('xcrun', [
      '-sdk',
      'macosx',
      'metal',
      // FIXME: compile to metal 4
      '-std=macos-metal2.0',
      '-c',
      metalFile.path,
      '-o',
      airFile.path
    ]);
    if (compileResult.exitCode != 0) {
      stderr.writeln('Failed to compile ${metalFile.path}: ${compileResult.stderr}');
      exit(compileResult.exitCode);
    }
    airFiles.add(airFile.path);
  }
  final List<String> metallibArgs = [
    '-sdk',
    'macosx',
    'metallib',
    ...airFiles,
    '-o',
    metallibFile.path
  ];
  final ProcessResult metallibResult = Process.runSync('xcrun', metallibArgs);
  if (metallibResult.exitCode != 0) {
    stderr.writeln('Failed to link metallib: ${metallibResult.stderr}');
    exit(metallibResult.exitCode);
  }
}
