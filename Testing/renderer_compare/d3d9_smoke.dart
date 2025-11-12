import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final Directory root = (args.isEmpty ? Directory.current : Directory(args.first)).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath = root.path.endsWith(sep) ? root.path : root.path + sep;
  final Directory hlslDir = Directory(rootPath + 'tools${sep}shader_port${sep}output${sep}hlsl');
  if (!hlslDir.existsSync()) {
    stderr.writeln('Missing HLSL output directory: ${hlslDir.path}');
    exit(1);
  }
  int hlslCount = 0;
  for (final FileSystemEntity entity in hlslDir.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.hlsl')) hlslCount++;
  }
  if (hlslCount == 0) {
    stderr.writeln('No HLSL shaders found in ${hlslDir.path}');
    exit(1);
  }
  final File indexFile = File(hlslDir.path + sep + 'index.json');
  if (indexFile.existsSync()) {
    final dynamic parsed = jsonDecode(indexFile.readAsStringSync());
    if (parsed is Map<String, dynamic>) {
      final int expected = parsed['count'] is int ? parsed['count'] as int : 0;
      if (expected != 0 && expected != hlslCount) {
        stderr.writeln('Mismatch between generated count ($hlslCount) and index ($expected)');
        exit(1);
      }
    }
  }
  final Directory dxilDir = Directory(rootPath + 'build${sep}shader_port${sep}dxil');
  if (dxilDir.existsSync()) {
    int dxilCount = 0;
    for (final FileSystemEntity entity in dxilDir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dxil')) dxilCount++;
    }
    if (dxilCount == 0) {
      stderr.writeln('DXIL directory is present but empty: ${dxilDir.path}');
      exit(1);
    }
  }
  stdout.writeln('Verified $hlslCount generated HLSL shaders');
}
