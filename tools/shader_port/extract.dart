import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final Directory root = (args.isEmpty ? Directory.current : Directory(args.first)).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath = root.path.endsWith(sep) ? root.path : root.path + sep;
  final File pakFile = File(rootPath + 'FCData${sep}Shaders.pak');
  if (!pakFile.existsSync()) {
    stderr.writeln('Missing file: ${pakFile.path}');
    exit(1);
  }
  final Directory targetDir = Directory(rootPath + 'Shaders${sep}Legacy');
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
  final File manifestFile = File(rootPath + 'tools${sep}shader_port${sep}output${sep}extracted_shaders.json');
  manifestFile.parent.createSync(recursive: true);
  manifestFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  stdout.writeln('Extracted ${manifest.length} shader scripts to ${targetDir.path}');
}
