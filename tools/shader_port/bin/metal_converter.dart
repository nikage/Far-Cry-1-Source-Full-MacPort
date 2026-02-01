import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:shader_port/metal_conversion_service.dart';
import 'package:shader_port/compiler_backend.dart';

Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'root',
      abbr: 'r',
      defaultsTo: Directory.current.path,
      help: 'Workspace root that contains tools/, RenderDll/, etc.',
    )
    ..addOption(
      'input-dir',
      help:
          'Directory that contains generated HLSL files (default: output/hlsl/Shaders/HWScripts/Declarations).',
    )
    ..addOption(
      'dxil-dir',
      help: 'Directory used to store compiled DXIL outputs.',
    )
    ..addOption(
      'metallib-dir',
      help: 'Directory used to store per-shader metallib outputs.',
    )
    ..addOption(
      'manifest',
      help: 'Path to a JSON manifest summarizing conversion results.',
    )
    ..addOption(
      'generated-manifest',
      help: 'Path to generated_manifest.json used for entry/stage metadata.',
    )
    ..addOption(
      'shader-model',
      defaultsTo: '6',
      help: 'Shader model to target (e.g., 6 or 3).',
    )
    ..addOption('dxc-path', help: 'Override path to the dxc compiler binary.')
    ..addOption('clang-path', help: 'Optional clang path for preprocessing.')
    ..addOption(
      'metal-shader-converter-path',
      help: 'Path to Apple\'s metal-shader-converter binary.',
    )
    ..addOption(
      'jobs',
      defaultsTo: '1',
      help: 'Maximum number of parallel compilation jobs.',
    )
    ..addFlag(
      'verbose',
      defaultsTo: false,
      help: 'Print subprocess stdout/stderr while compiling.',
    );

  late final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on ArgParserException catch (error) {
    _printUsage(parser, error.message);
    exitCode = 64;
    return;
  }

  final Directory rootDir = Directory(results['root'] as String).absolute;
  if (!rootDir.existsSync()) {
    stderr.writeln('Root directory does not exist: ${rootDir.path}');
    exitCode = 64;
    return;
  }

  String resolvePath(String? candidate, String fallbackRelative) {
    if (candidate == null || candidate.isEmpty) {
      return p.join(rootDir.path, fallbackRelative);
    }
    if (p.isAbsolute(candidate)) {
      return candidate;
    }
    return p.normalize(p.join(rootDir.path, candidate));
  }

  String? resolveOptionalBinary(String? candidate) {
    if (candidate == null || candidate.isEmpty) {
      return null;
    }
    if (p.isAbsolute(candidate)) {
      return candidate;
    }
    return p.normalize(p.join(rootDir.path, candidate));
  }

  final Directory inputDir = Directory(
    resolvePath(
      results['input-dir'] as String?,
      p.join('tools', 'shader_port', 'output', 'hlsl', 'Shaders', 'HWScripts', 'Declarations'),
    ),
  );
  if (!inputDir.existsSync()) {
    stderr.writeln('Input directory does not exist: ${inputDir.path}');
    exitCode = 66;
    return;
  }

  final Directory dxilDir = Directory(
    resolvePath(
      results['dxil-dir'] as String?,
      p.join('build', 'shader_port', 'metal_converter', 'dxil'),
    ),
  );
  final Directory metallibDir = Directory(
    resolvePath(
      results['metallib-dir'] as String?,
      p.join('build', 'shader_port', 'metal_converter', 'metallib'),
    ),
  );
  final File manifestFile = File(
    resolvePath(
      results['manifest'] as String?,
      p.join('build', 'shader_port', 'metal_converter', 'manifest.json'),
    ),
  );
  final File generatedManifest = File(
    resolvePath(
      results['generated-manifest'] as String?,
      p.join('RenderDll', 'XRenderMetal', 'Generated', 'generated_manifest.json'),
    ),
  );
  dxilDir.createSync(recursive: true);
  metallibDir.createSync(recursive: true);
  manifestFile.parent.createSync(recursive: true);

  final int jobs = int.tryParse(results['jobs'] as String? ?? '1') ?? 1;
  if (jobs <= 0) {
    stderr.writeln('The --jobs value must be a positive integer.');
    exitCode = 64;
    return;
  }
  final String shaderModelRaw = (results['shader-model'] as String? ?? '6').trim();
  final String shaderModel = shaderModelRaw == '3' ? '3' : '6';

  final String? clangPath = resolveOptionalBinary(results['clang-path'] as String?);
  final String? dxcPath = resolveOptionalBinary(results['dxc-path'] as String?);
  final String? metalConverterPath =
      resolveOptionalBinary(results['metal-shader-converter-path'] as String?);
  if (dxcPath == null || dxcPath.isEmpty) {
    stderr.writeln('The --dxc-path option is required.');
    exitCode = 64;
    return;
  }
  if (metalConverterPath == null || metalConverterPath.isEmpty) {
    stderr.writeln('The --metal-shader-converter-path option is required.');
    exitCode = 64;
    return;
  }
  final bool verbose = results['verbose'] as bool;
  if (!generatedManifest.existsSync()) {
    stderr.writeln('Generated manifest not found: ${generatedManifest.path}');
    exitCode = 66;
    return;
  }
  final Map<String, Map<String, String>> entryMap =
      _loadEntryMap(
        generatedManifest,
        shaderModel,
        inputDirPrefix: inputDir.path,
      );
  if (entryMap.isEmpty) {
    stderr.writeln('No manifest entries found in ${generatedManifest.path}');
    exitCode = 64;
    return;
  }
  if (verbose) {
    stdout.writeln('Entry map size: ${entryMap.length}');
    int shown = 0;
    for (final MapEntry<String, Map<String, String>> e in entryMap.entries) {
      stdout.writeln('Mapping sample: ${e.key} -> ${e.value}');
      shown++;
      if (shown >= 5) break;
    }
  }
  String? _entryFor(String relativePath) => entryMap[relativePath]?['entry'];
  String? _profileFor(String relativePath) => entryMap[relativePath]?['profile'];
  final CompilerBackend backend = CompilerBackend(
    CompilerBackendConfig(
      cacheDir: Directory(p.join(
        rootDir.path,
        'build',
        'shader_port',
        'metal_converter',
        'cache',
      )),
      clangPath: clangPath,
      dxcPath: dxcPath,
      metalShaderConverterPath: metalConverterPath,
      includeDirs: <String>[inputDir.path],
      entryResolver: (String relativePath) {
        final String? entry = _entryFor(relativePath);
        final String? profile = _profileFor(relativePath);
        if (entry == null || profile == null) {
          throw StateError('Missing entry/profile for $relativePath');
        }
        return (entry: entry, profile: profile);
      },
    ),
  );

  final MetalConversionService service = MetalConversionService(
    rootDir: rootDir,
    inputDir: inputDir,
    dxilDir: dxilDir,
    metallibDir: metallibDir,
    manifestFile: manifestFile,
    clangPath: clangPath,
    dxcPath: dxcPath,
    metalShaderConverterPath: metalConverterPath,
    jobs: jobs,
    verbose: verbose,
    backend: backend,
  );

  final MetalConversionSummary summary = await service.run();
  stdout.writeln('Processed ${summary.total} shaders');
  stdout.writeln('Succeeded: ${summary.succeeded}');
  stdout.writeln('Failed: ${summary.failed}');
  if (summary.succeeded > 0) {
    try {
      await _aggregateMetallib(
        rootDir,
        manifestFile,
        p.join(
          rootDir.path,
          'RenderDll',
          'XRenderMetal',
          'Generated',
          'GeneratedShaders.metallib',
        ),
      );
    } on Object catch (error) {
      stderr.writeln('Aggregation failed: $error');
      exitCode = 1;
    }
  }
  if (summary.failedEntries.isNotEmpty) {
    stderr.writeln('Failures:');
    for (final ConversionFailure failure in summary.failedEntries) {
      stderr.writeln('  ${failure.sourcePath}: ${failure.message}');
    }
    exitCode = 1;
  }
}

void _printUsage(ArgParser parser, [String? error]) {
  if (error != null && error.isNotEmpty) {
    stderr.writeln(error);
  }
  stderr.writeln('Usage: dart run tools/shader_port/bin/metal_converter.dart [options]');
  stderr.writeln(parser.usage);
}

Map<String, Map<String, String>> _loadEntryMap(
  File manifest,
  String shaderModel, {
  String? inputDirPrefix,
}) {
  final String normalizedPrefix = inputDirPrefix == null
      ? ''
      : p.normalize(inputDirPrefix).replaceAll('\\', '/');
  final dynamic parsed = jsonDecode(manifest.readAsStringSync());
  if (parsed is! List<dynamic>) {
    throw StateError('Generated manifest is not an array: ${manifest.path}');
  }
  final Map<String, Map<String, String>> map = <String, Map<String, String>>{};
  for (final dynamic entry in parsed) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    final String? source = entry['source'] as String?;
    final String? stage = entry['stage'] as String?;
    final String? entryPoint =
        (entry['entryPoint'] as String?) ?? (entry['fragment'] as String?);
    if (source == null || stage == null || entryPoint == null) {
      continue;
    }
    final String normalizedSource = source.replaceAll('\\', '/');
    final String lowerStage = stage.toLowerCase();
    final String profile = lowerStage == 'vertex'
        ? 'vs_${shaderModel}_0'
        : 'ps_${shaderModel}_0';
    final String withoutBase = normalizedSource.startsWith('Shaders/HWScripts/Declarations/')
        ? normalizedSource.substring('Shaders/HWScripts/Declarations/'.length)
        : normalizedSource;
    final String trimmed = normalizedPrefix.isNotEmpty &&
            normalizedSource.startsWith(normalizedPrefix)
        ? normalizedSource.substring(normalizedPrefix.length).replaceFirst(
              RegExp(r'^/'),
              '',
            )
        : normalizedSource;
    final String normalizedHlsl = p.setExtension(normalizedSource, '.hlsl');
    final String trimmedHlsl = p.setExtension(trimmed, '.hlsl');
    final String baseHlsl = p.setExtension(withoutBase, '.hlsl');
    final String baseName = p.basename(normalizedSource);
    final String baseNameHlsl = p.setExtension(baseName, '.hlsl');
    final List<String> keys = <String>[
      normalizedSource,
      trimmed,
      withoutBase,
      normalizedHlsl,
      trimmedHlsl,
      baseHlsl,
      baseName,
      baseNameHlsl,
      if (!normalizedSource.endsWith('.hlsl')) '$normalizedSource.hlsl',
      if (!trimmed.endsWith('.hlsl')) '$trimmed.hlsl',
      if (!withoutBase.endsWith('.hlsl')) '$withoutBase.hlsl',
      normalizedSource.replaceAll('.json', '.hlsl'),
      trimmed.replaceAll('.json', '.hlsl'),
      withoutBase.replaceAll('.json', '.hlsl'),
    ].toSet().toList();
    for (final String key in keys) {
      map[key] = <String, String>{
        'entry': entryPoint,
        'profile': profile,
      };
    }
  }
  return map;
}

// Exposed for unit testing.
Map<String, Map<String, String>> loadEntryMapForTest(
  File manifest,
  String shaderModel, {
  String? inputDirPrefix,
}) =>
    _loadEntryMap(
      manifest,
      shaderModel,
      inputDirPrefix: inputDirPrefix,
    );

Future<void> _aggregateMetallib(
  Directory rootDir,
  File converterManifest,
  String outputPath,
) async {
  if (!converterManifest.existsSync()) {
    throw StateError('Converter manifest not found: ${converterManifest.path}');
  }
  final dynamic parsed = jsonDecode(converterManifest.readAsStringSync());
  if (parsed is! List<dynamic>) {
    throw StateError('Converter manifest is not an array: ${converterManifest.path}');
  }
  final List<String> inputs = <String>[];
  for (final dynamic entry in parsed) {
    if (entry is! Map<String, dynamic>) continue;
    final String status = (entry['status'] as String? ?? '').toLowerCase();
    if (status != 'success') continue;
    final String? metallib = entry['metallib'] as String?;
    if (metallib == null || metallib.isEmpty) continue;
    final String abs = p.isAbsolute(metallib)
        ? p.normalize(metallib)
        : p.normalize(p.join(rootDir.path, metallib));
    if (File(abs).existsSync()) {
      inputs.add(abs);
    }
  }
  if (inputs.isEmpty) {
    throw StateError('No metallib inputs available for aggregation');
  }
  final File output = File(outputPath);
  output.parent.createSync(recursive: true);
  final List<String> args = <String>[
    '-sdk',
    'macosx',
    'metallib',
    ...inputs,
    '-o',
    output.path,
  ];
  final ProcessResult result = await Process.run('xcrun', args);
  if (result.exitCode != 0) {
    throw ProcessException(
      'xcrun',
      args,
      result.stderr is String ? result.stderr as String : '',
      result.exitCode,
    );
  }
}
