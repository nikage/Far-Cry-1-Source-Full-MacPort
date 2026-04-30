import 'dart:io';

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

Future<void> main(List<String> args) async {
  String rootArg = '.';
  bool skipGenerate = false;
  bool verbose = false;
  bool strict = false;
  String metalStd = 'metal3.0';
  String? overridesPath;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
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
        if (!args[i].startsWith('--')) rootArg = args[i];
    }
  }

  final Directory root = Directory(rootArg).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath =
      root.path.endsWith(sep) ? root.path : '${root.path}$sep';
  final String generatedPath =
      '${rootPath}RenderDll${sep}XRenderMetal${sep}Generated';
  final String manifestPath =
      '$generatedPath${sep}generated_manifest.json';

  final String generatorScript =
      '${rootPath}tools${sep}shader_port${sep}lib${sep}metal_generator.dart';
  final String compileCheckScript =
      '${rootPath}tools${sep}shader_port${sep}bin${sep}compile_check.dart';
  final String validatePairsScript =
      '${rootPath}tools${sep}shader_port${sep}bin${sep}validate_pairs.dart';

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
    if (!skipGenerate)
      Stage('generate', 'dart', generatorArgs),
    Stage('compile-check', 'dart', compileCheckArgs),
    Stage('validate-pairs', 'dart', validatePairsArgs),
  ];

  stdout.writeln('Shader migration validation (${stages.length} stages)');

  final StageRunner runner = _makeProcessRunner(verbose);
  final int exitCode = await runStages(stages, runner);
  if (exitCode != 0) exit(exitCode);

  stdout.writeln('\nAll stages passed.');
}
