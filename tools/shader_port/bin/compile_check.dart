import 'dart:convert';
import 'dart:io';

import '../lib/compile_error_cluster.dart';

void main(List<String> args) {
  String rootArg = '.';
  String? generatedDirArg;
  bool verbose = false;
  List<String> metalFlags = ['-std=metal3.0'];

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--verbose' || args[i] == '-v') {
      verbose = true;
    } else if (args[i] == '--generated-dir' && i + 1 < args.length) {
      generatedDirArg = args[++i];
    } else if (args[i] == '--metal-std' && i + 1 < args.length) {
      metalFlags = ['-std=${args[++i]}'];
    } else if (!args[i].startsWith('--')) {
      rootArg = args[i];
    }
  }

  final Directory root = Directory(rootArg).absolute;
  final String sep = Platform.pathSeparator;

  final String generatedPath = generatedDirArg ??
      '${root.path}${sep}RenderDll${sep}XRenderMetal${sep}Generated';
  final Directory generatedDir = Directory(generatedPath);

  if (!generatedDir.existsSync()) {
    stderr.writeln('Generated directory not found: $generatedPath');
    stderr.writeln(
      'Run dart tools/shader_port/lib/metal_generator.dart first.',
    );
    exit(1);
  }

  final File manifest =
      File('$generatedPath${sep}generated_manifest.json');
  if (!manifest.existsSync()) {
    stderr.writeln('Manifest not found: ${manifest.path}');
    exit(1);
  }

  final List<dynamic> entries =
      jsonDecode(manifest.readAsStringSync(encoding: utf8)) as List<dynamic>;
  if (entries.isEmpty) {
    stderr.writeln('Manifest is empty — nothing to compile.');
    exit(1);
  }

  final List<String> metalFiles = [];
  for (final dynamic entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final String? metalFileName = entry['metal'] as String?;
    if (metalFileName == null || metalFileName.isEmpty) continue;
    final String filePath = '$generatedPath$sep$metalFileName';
    if (!File(filePath).existsSync()) {
      stderr.writeln('Warning: metal file missing: $filePath');
      continue;
    }
    metalFiles.add(filePath);
  }

  if (metalFiles.isEmpty) {
    stderr.writeln('No Metal files found in generated directory.');
    exit(1);
  }

  stdout.writeln(
    'Checking ${metalFiles.length} Metal shaders '
    '(flags: ${metalFlags.join(' ')}) ...',
  );

  final CompileCheckResult result = runCompileCheck(
    generatedPath,
    metalFiles,
    metalFlags: metalFlags,
  );

  stdout.writeln(formatReport(result));

  if (verbose && !result.allPassed) {
    stdout.writeln('\n--- All errors by file ---');
    for (final MapEntry<String, List<ShaderCompileError>> entry
        in result.errorsByFile.entries) {
      stdout.writeln('\n${entry.key}:');
      for (final ShaderCompileError e in entry.value) {
        stdout.writeln('  ${e.raw}');
      }
    }
  }
}
