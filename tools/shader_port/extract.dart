import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) {
  final ArgParser argParser = ArgParser()
    ..addOption(
      'pak-file',
      help: 'Path to Shaders.pak. Defaults to <root>/FCData/Shaders.pak.',
    )
    ..addOption(
      'output-dir',
      help:
          'Directory where unpacked shader files are written. '
          'Defaults to <root>/Shaders/Legacy.',
    );
  final ArgResults parsed = argParser.parse(args);
  final Directory root =
      (parsed.rest.isEmpty ? Directory.current : Directory(parsed.rest.first)).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath = root.path.endsWith(sep) ? root.path : root.path + sep;

  final File pakFile = parsed['pak-file'] != null
      ? File(parsed['pak-file'] as String)
      : File(rootPath + 'FCData${sep}Shaders.pak');
  if (!pakFile.existsSync()) {
    stderr.writeln('Missing file: ${pakFile.path}');
    exit(1);
  }

  final Directory targetDir = parsed['output-dir'] != null
      ? Directory(parsed['output-dir'] as String).absolute
      : Directory(rootPath + 'Shaders${sep}Legacy');
  targetDir.createSync(recursive: true);
  final Directory staging = Directory.systemTemp.createTempSync('shader_pak_extract_');
  final ProcessResult unzipResult = Process.runSync('unzip', ['-qo', pakFile.path, '-d', staging.path]);
  if (unzipResult.exitCode != 0) {
    stderr.writeln(unzipResult.stderr);
    staging.deleteSync(recursive: true);
    exit(unzipResult.exitCode);
  }
  final List<Map<String, String>> manifest = [];
  final Iterable<FileSystemEntity> entries = staging.listSync(recursive: true, followLinks: false);
  for (final FileSystemEntity entity in entries) {
    if (entity is! File) continue;
    final String lower = entity.path.toLowerCase();
    if (!(lower.endsWith('.cryps') || lower.endsWith('.crycg'))) continue;
    final String relative = entity.path.substring(staging.path.length + 1);
    final String destinationPath = targetDir.path + sep + relative.replaceAll(RegExp(r'[\\/]'), sep);
    final File destinationFile = File(destinationPath);
    destinationFile.parent.createSync(recursive: true);
    destinationFile.writeAsBytesSync(entity.readAsBytesSync());
    manifest.add({
      'source': entity.path,
      'relative': relative,
      'destination': destinationFile.path
    });
  }
  staging.deleteSync(recursive: true);
  final File manifestFile = File(
    p.join(rootPath, 'tools', 'shader_port', 'output', 'extracted_shaders.json'),
  );
  manifestFile.parent.createSync(recursive: true);
  manifestFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  stdout.writeln('Extracted ${manifest.length} shader scripts to ${targetDir.path}');
}
