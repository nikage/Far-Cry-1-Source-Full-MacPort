import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'root',
      abbr: 'r',
      defaultsTo: Directory.current.path,
      help: 'Workspace root that contains Shaders/, RenderDll/, etc.',
    )
    ..addOption(
      'pak-file',
      help:
          'Path to Shaders.pak. '
          'Defaults to <root>/Assets/FCData/Shaders.pak, '
          'then <root>/FCData/Shaders.pak.',
    )
    ..addOption(
      'shaders-dir',
      help:
          'Directory containing unpacked .crycg/.cryps files. '
          'Defaults to <root>/Assets/Shaders/Source/Shaders, '
          'then <root>/Shaders/Legacy.',
    )
    ..addFlag(
      'extract',
      defaultsTo: true,
      help: 'Run extract.dart to unpack Shaders.pak.',
    )
    ..addFlag(
      'parse',
      defaultsTo: true,
      help: 'Run parser.dart to convert Cry scripts into IR.',
    )
    ..addFlag(
      'generate',
      defaultsTo: true,
      help: 'Run metal_generator.dart to produce .metal files + manifest.',
    )
    ..addFlag(
      'build',
      defaultsTo: true,
      help: 'Compile generated .metal files into a metallib.',
    )
    ..addOption(
      'generated-dir',
      help: 'Override the output directory for generated Metal sources.',
    )
    ..addOption(
      'air-dir',
      help: 'Temp directory for intermediate .air files.',
    )
    ..addOption(
      'metallib',
      help: 'Destination metallib path when --build is enabled.',
    )
    ..addFlag(
      'verbose',
      defaultsTo: false,
      help: 'Print subprocess stdout/stderr as it streams.',
    );

  late final ArgResults results;
  try {
    results = parser.parse(args);
  } on ArgParserException catch (error) {
    _printUsage(parser, error.toString());
    exitCode = 64;
    return;
  }

  final Directory rootDir = Directory(results['root'] as String).absolute;
  if (!rootDir.existsSync()) {
    _printUsage(parser, 'Root directory does not exist: ${rootDir.path}');
    exitCode = 64;
    return;
  }

  // Resolve default pak file and shaders directory, preferring the Assets/ layout.
  final String resolvedPakFile = results['pak-file'] as String? ??
      _firstExisting([
        p.join(rootDir.path, 'Assets', 'FCData', 'Shaders.pak'),
        p.join(rootDir.path, 'FCData', 'Shaders.pak'),
      ]);
  final String resolvedShadersDir = results['shaders-dir'] as String? ??
      _firstExisting([
        p.join(rootDir.path, 'Assets', 'Shaders', 'Source', 'Shaders'),
        p.join(rootDir.path, 'Shaders', 'Legacy'),
      ]);

  final bool verbose = results['verbose'] as bool;
  Future<void> runDart(String script, List<String> scriptArgs) async {
    final String scriptPath = p.normalize(p.join(rootDir.path, script));
    final List<String> arguments = <String>[scriptPath, ...scriptArgs];
    await _runProcess(
      'dart',
      arguments,
      workingDirectory: rootDir.path,
      verbose: verbose,
    );
  }

  if (results['extract'] as bool) {
    await runDart('tools/shader_port/extract.dart', <String>[
      rootDir.path,
      '--pak-file', resolvedPakFile,
    ]);
  }

  if (results['parse'] as bool) {
    await runDart('tools/shader_port/lib/parser.dart', <String>[
      rootDir.path,
      '--shaders-dir', resolvedShadersDir,
    ]);
  }

  if (results['generate'] as bool) {
    await runDart(
      'tools/shader_port/lib/metal_generator.dart',
      <String>[rootDir.path],
    );
  }

  if (results['build'] as bool) {
    final String generatedDir = results['generated-dir'] as String? ??
        p.join(rootDir.path, 'RenderDll', 'XRenderMetal', 'Generated');
    final String airDir = results['air-dir'] as String? ??
        p.join(rootDir.path, 'build', 'shader_port', 'generated_air');
    final Directory airDirectory = Directory(airDir);
    if (!airDirectory.existsSync()) {
      airDirectory.createSync(recursive: true);
    }
    final String metallibPath = results['metallib'] as String? ??
        p.join(
            rootDir.path, 'build', 'shader_port', 'GeneratedShaders.metallib');
    await runDart(
      'tools/shader_port/lib/build_metal.dart',
      <String>[
        rootDir.path,
        generatedDir,
        airDir,
        metallibPath,
      ],
    );
    stdout.writeln('Metallib written to $metallibPath');
  }
}

void _printUsage(ArgParser parser, [String? error]) {
  if (error != null) {
    stderr.writeln(error);
  }
  stderr.writeln('Usage: dart run bin/pipeline.dart [options]');
  stderr.writeln(parser.usage);
}

/// Returns the first path in [candidates] that exists on disk,
/// or the last candidate as a fallback (so callers get a meaningful error).
/// Returns the first path from [candidates] that exists on disk.
/// Falls back to the last candidate when none exist (caller decides how to handle).
// ignore: prefer_void_to_null — exposed for testing
String firstExistingPath(List<String> candidates) => _firstExisting(candidates);

String _firstExisting(List<String> candidates) {
  for (final String path in candidates) {
    if (File(path).existsSync() || Directory(path).existsSync()) {
      return path;
    }
  }
  return candidates.last;
}

Future<void> _runProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required bool verbose,
}) async {
  final Process process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (verbose) {
    stdout.addStream(process.stdout);
    stderr.addStream(process.stderr);
  } else {
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
  }
  final int code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, arguments, 'Exited with $code', code);
  }
}
