import 'dart:io';

import '../lib/metal_config.dart' as metalCfg;

typedef StageRunner = Future<int> Function(
  String name,
  String executable,
  List<String> args,
);

class Stage {
  const Stage(this.name, this.executable, this.args);
  final String name;
  final String executable;
  final List<String> args;
}

StageRunner _makeProcessRunner(bool verbose) {
  return (String name, String executable, List<String> args) async {
    stdout.writeln('\n==> [$name]');
    if (verbose) stdout.writeln('    ${[executable, ...args].join(' ')}');
    final Process process = await Process.start(
      executable,
      args,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  };
}

Future<int> runStages(
  List<Stage> stages,
  StageRunner runner,
) async {
  for (final Stage stage in stages) {
    final int code = await runner(stage.name, stage.executable, stage.args);
    if (code != 0) return code;
  }
  return 0;
}

class BuildStagesResult {
  BuildStagesResult({
    required this.stages,
    required this.validateIrScript,
    required this.generatorScript,
    required this.compileCheckScript,
    required this.validatePairsScript,
    required this.skipValidateIr,
    required this.skipGenerate,
    required this.verbose,
    required this.strict,
    required this.metalStd,
    this.overridesPath,
  });

  final List<Stage> stages;
  final String validateIrScript;
  final String generatorScript;
  final String compileCheckScript;
  final String validatePairsScript;
  final bool skipValidateIr;
  final bool skipGenerate;
  final bool verbose;
  final bool strict;
  final String metalStd;
  final String? overridesPath;
}

BuildStagesResult buildStages({
  bool skipValidateIr = false,
  bool skipGenerate = false,
  bool verbose = false,
  bool strict = false,
  String metalStd = 'metal3.0',
  String? overridesPath,
  required String rootArg,
}) {
  final Directory root = Directory(rootArg).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath =
      root.path.endsWith(sep) ? root.path : '${root.path}$sep';
  final String generatedPath =
      '${rootPath}RenderDll${sep}XRenderMetal${sep}Generated';
  final String manifestPath = '$generatedPath${sep}generated_manifest.json';

  final String validateIrScript =
      '${rootPath}tools${sep}shader_port${sep}bin${sep}validate_ir.dart';
  final String generatorScript =
      '${rootPath}tools${sep}shader_port${sep}lib${sep}metal_generator.dart';
  final String compileCheckScript =
      '${rootPath}tools${sep}shader_port${sep}bin${sep}compile_check.dart';
  final String validatePairsScript =
      '${rootPath}tools${sep}shader_port${sep}bin${sep}validate_pairs.dart';

  final List<String> validateIrArgs = [
    'run',
    validateIrScript,
    rootArg,
  ];

  final List<String> generatorArgs = [
    'run',
    generatorScript,
    rootArg,
    if (overridesPath != null) ...['--overrides', overridesPath],
  ];

  final List<String> compileCheckArgs = [
    'run',
    compileCheckScript,
    rootArg,
    '--metal-std',
    metalStd,
    if (verbose) '--verbose',
  ];

  final List<String> validatePairsArgs = [
    'run',
    validatePairsScript,
    manifestPath,
    if (strict) '--strict',
  ];

  final List<Stage> stages = <Stage>[
    if (!skipValidateIr) Stage('validate-ir', 'dart', validateIrArgs),
    if (!skipGenerate) Stage('generate', 'dart', generatorArgs),
    Stage('compile-check', 'dart', compileCheckArgs),
    Stage('validate-pairs', 'dart', validatePairsArgs),
  ];

  return BuildStagesResult(
    stages: stages,
    validateIrScript: validateIrScript,
    generatorScript: generatorScript,
    compileCheckScript: compileCheckScript,
    validatePairsScript: validatePairsScript,
    skipValidateIr: skipValidateIr,
    skipGenerate: skipGenerate,
    verbose: verbose,
    strict: strict,
    metalStd: metalStd,
    overridesPath: overridesPath,
  );
}

/// Touches the CMake-managed stamp file that guards `GeneratedShaders.metallib`
/// so that the next `cmake --build` detects the generator output as changed.
///
/// Returns true if the stamp existed and was updated, false if it was absent.
bool touchGeneratedStamp(String rootArg) {
  final String sep = Platform.pathSeparator;
  final String rootPath = rootArg.endsWith(sep)
      ? rootArg.substring(0, rootArg.length - sep.length)
      : rootArg;
  final File stamp = File(
    '$rootPath${sep}build${sep}RenderDll${sep}XRenderMetal${sep}generated_shaders.stamp',
  );
  if (!stamp.existsSync()) return false;
  stamp.setLastModifiedSync(DateTime.now());
  return true;
}

Future<void> main(List<String> args) async {
  String rootArg = '.';
  bool skipValidateIr = false;
  bool skipGenerate = false;
  bool verbose = false;
  bool strict = false;
  String metalStd = metalCfg.metalStd;
  String? overridesPath;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--skip-validate-ir':
        skipValidateIr = true;
      case '--skip-generate':
        skipGenerate = true;
      case '--verbose':
      case '-v':
        verbose = true;
      case '--strict':
        strict = true;
      case '--metal-std':
        if (i + 1 < args.length) metalStd = args[++i];
      case '--overrides':
        if (i + 1 < args.length) overridesPath = args[++i];
      default:
        if (args[i].startsWith('--')) {
          stderr.writeln('Warning: unknown flag "${args[i]}" — ignored');
        } else {
          rootArg = args[i];
        }
    }
  }

  final built = buildStages(
    rootArg: rootArg,
    skipValidateIr: skipValidateIr,
    skipGenerate: skipGenerate,
    verbose: verbose,
    strict: strict,
    metalStd: metalStd,
    overridesPath: overridesPath,
  );

  if (!built.skipValidateIr && !File(built.validateIrScript).existsSync()) {
    stderr.writeln(
      'Error: validate-ir script not found: ${built.validateIrScript}',
    );
    exit(1);
  }
  if (!built.skipGenerate && !File(built.generatorScript).existsSync()) {
    stderr.writeln(
      'Error: generator script not found: ${built.generatorScript}',
    );
    exit(1);
  }
  if (!File(built.compileCheckScript).existsSync()) {
    stderr.writeln(
      'Error: compile-check script not found: ${built.compileCheckScript}',
    );
    exit(1);
  }
  if (!File(built.validatePairsScript).existsSync()) {
    stderr.writeln(
      'Error: validate-pairs script not found: ${built.validatePairsScript}',
    );
    exit(1);
  }

  stdout.writeln(
    'Shader migration validation (${built.stages.length} stages)',
  );

  final StageRunner runner = _makeProcessRunner(built.verbose);

  // Run stages one by one so we can hook post-generate behaviour.
  for (final Stage stage in built.stages) {
    final int code = await runner(stage.name, stage.executable, stage.args);
    if (code != 0) exit(code);

    // After the generator runs, touch GENERATED_STAMP so that the next
    // `cmake --build` knows the Metal source files have changed and recompiles
    // GeneratedShaders.metallib.  Without this, running validate_migration.dart
    // outside CMake leaves the stamp stale and the metallib is silently skipped.
    if (stage.name == 'generate') {
      final bool touched = touchGeneratedStamp(rootArg);
      if (built.verbose && touched) {
        stdout.writeln('  [info] Touched generated_shaders.stamp');
      }
    }
  }

  stdout.writeln('\nAll stages passed.');
}
