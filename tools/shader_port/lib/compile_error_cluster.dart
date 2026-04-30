import 'dart:io';

class ShaderCompileError {
  const ShaderCompileError({
    required this.file,
    required this.line,
    required this.column,
    required this.severity,
    required this.message,
    required this.raw,
  });

  final String file;
  final int line;
  final int column;
  final String severity;
  final String message;
  final String raw;
}

class ErrorCluster {
  ErrorCluster({required this.key, required this.example});

  final String key;
  final String example;
  int count = 1;
  final List<String> affectedFiles = [];
}

class CompileCheckResult {
  CompileCheckResult({
    required this.totalShaders,
    required this.failedShaders,
    required this.clusters,
    required this.errorsByFile,
  });

  final int totalShaders;
  final int failedShaders;
  final List<ErrorCluster> clusters;
  final Map<String, List<ShaderCompileError>> errorsByFile;

  bool get allPassed => failedShaders == 0;
}

final RegExp _diagPattern = RegExp(
  r'^(.+):(\d+):(\d+):\s+(error|warning|note):\s+(.+)$',
);

List<ShaderCompileError> parseCompilerOutput(String stderr, String filePath) {
  final List<ShaderCompileError> errors = [];
  for (final String line in stderr.split('\n')) {
    final RegExpMatch? match = _diagPattern.firstMatch(line.trim());
    if (match == null) continue;
    final String severity = match.group(4)!;
    if (severity != 'error') continue;
    errors.add(ShaderCompileError(
      file: match.group(1)!,
      line: int.tryParse(match.group(2)!) ?? 0,
      column: int.tryParse(match.group(3)!) ?? 0,
      severity: severity,
      message: match.group(5)!,
      raw: line.trim(),
    ));
  }
  return errors;
}

String clusterKey(String message) {
  String key = message;
  key = key.replaceAll(RegExp(r"'[^']*'"), "'X'");
  key = key.replaceAll(RegExp(r'"[^"]*"'), '"X"');
  key = key.replaceAll(RegExp(r'\b\d+\b'), 'N');
  if (key.length > 80) key = key.substring(0, 80);
  return key;
}

List<ErrorCluster> clusterErrors(
    Map<String, List<ShaderCompileError>> errorsByFile) {
  final Map<String, ErrorCluster> map = {};
  for (final MapEntry<String, List<ShaderCompileError>> entry
      in errorsByFile.entries) {
    final String file = entry.key;
    for (final ShaderCompileError error in entry.value) {
      final String key = clusterKey(error.message);
      if (map.containsKey(key)) {
        map[key]!.count++;
        if (!map[key]!.affectedFiles.contains(file)) {
          map[key]!.affectedFiles.add(file);
        }
      } else {
        final ErrorCluster cluster = ErrorCluster(
          key: key,
          example: error.message,
        );
        cluster.affectedFiles.add(file);
        map[key] = cluster;
      }
    }
  }
  final List<ErrorCluster> sorted = map.values.toList()
    ..sort((ErrorCluster a, ErrorCluster b) => b.count.compareTo(a.count));
  return sorted;
}

CompileCheckResult runCompileCheck(
  String generatedDir,
  List<String> metalFiles, {
  List<String> metalFlags = const ['-std=metal3.0'],
  String Function(String, List<String>)? compilerRunner,
}) {
  final Map<String, List<ShaderCompileError>> errorsByFile = {};
  int failed = 0;

  for (final String metalFile in metalFiles) {
    final String stderr = compilerRunner != null
        ? compilerRunner(metalFile, metalFlags)
        : _xcrunMetal(metalFile, metalFlags);

    final List<ShaderCompileError> errors =
        parseCompilerOutput(stderr, metalFile);
    if (errors.isNotEmpty) {
      failed++;
      errorsByFile[metalFile] = errors;
    }
  }

  final List<ErrorCluster> clusters = clusterErrors(errorsByFile);

  return CompileCheckResult(
    totalShaders: metalFiles.length,
    failedShaders: failed,
    clusters: clusters,
    errorsByFile: errorsByFile,
  );
}

String _xcrunMetal(String filePath, List<String> extraFlags) {
  final ProcessResult result = Process.runSync('xcrun', [
    '-sdk',
    'macosx',
    'metal',
    ...extraFlags,
    '-c',
    filePath,
    '-o',
    '/dev/null',
  ]);
  return result.stderr as String;
}

String formatReport(CompileCheckResult result) {
  final StringBuffer buf = StringBuffer();
  buf.writeln(
    'Compile check: ${result.totalShaders} shaders, '
    '${result.failedShaders} failed, '
    '${result.totalShaders - result.failedShaders} passed.',
  );
  if (result.allPassed) {
    buf.writeln('All shaders compile successfully.');
    return buf.toString();
  }
  buf.writeln();
  buf.writeln(
    '${'Count'.padRight(6)}  ${'Files'.padRight(6)}  Error pattern',
  );
  buf.writeln('-' * 90);
  for (final ErrorCluster cluster in result.clusters) {
    final String count = cluster.count.toString().padRight(6);
    final String files = cluster.affectedFiles.length.toString().padRight(6);
    buf.writeln('$count  $files  ${cluster.key}');
  }
  if (result.clusters.length <= 20) {
    buf.writeln();
    buf.writeln('--- Per-file errors (first 5 files) ---');
    int shown = 0;
    for (final MapEntry<String, List<ShaderCompileError>> entry
        in result.errorsByFile.entries) {
      if (shown++ >= 5) break;
      buf.writeln('\n${entry.key}:');
      for (final ShaderCompileError e in entry.value.take(5)) {
        buf.writeln('  ${e.raw}');
      }
    }
  }
  return buf.toString();
}
