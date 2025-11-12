import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final Directory root = (args.isEmpty ? Directory.current : Directory(args.first)).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath = root.path.endsWith(sep) ? root.path : root.path + sep;
  final File manifest = File(rootPath + 'RenderDll${sep}XRenderMetal${sep}Generated${sep}generated_manifest.json');
  if (!manifest.existsSync()) {
    stderr.writeln('Generated manifest not found: ${manifest.path}');
    exit(1);
  }
  final List<dynamic> entries = jsonDecode(manifest.readAsStringSync(encoding: utf8)) as List<dynamic>;
  if (entries.isEmpty) {
    stderr.writeln('Generated manifest is empty');
    exit(1);
  }
  final String metallibPath = args.length > 1
      ? args[1]
      : rootPath + 'cmake-build-debug${sep}GeneratedShaders.metallib';
  final File metallibFile = File(metallibPath);
  if (!metallibFile.existsSync()) {
    stderr.writeln('Generated metallib not found: ${metallibFile.path}');
    exit(1);
  }
  stdout.writeln('Validated ${entries.length} generated shader entries and metallib at ${metallibFile.path}');
}
