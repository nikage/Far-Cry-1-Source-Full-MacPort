import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'compiler_backend.dart';

Directory _defaultCacheDir(Directory rootDir) =>
    Directory(p.join(rootDir.path, 'build', 'shader_port', 'metal_converter', 'cache'));

class MetalConversionService {
  MetalConversionService({
    required this.rootDir,
    required this.inputDir,
    required this.dxilDir,
    required this.metallibDir,
    required this.manifestFile,
    required this.jobs,
    required this.verbose,
    this.clangPath,
    this.dxcPath,
    this.metalShaderConverterPath,
    CompilerBackend? backend,
    Directory? cacheDir,
  })  : assert(jobs > 0),
        _cacheDir = cacheDir ??
            backend?.config.cacheDir ??
            _defaultCacheDir(rootDir),
        _backend = backend ??
            CompilerBackend(
              CompilerBackendConfig(
                cacheDir: cacheDir ??
                    backend?.config.cacheDir ??
                    _defaultCacheDir(rootDir),
                clangPath: clangPath,
                dxcPath: dxcPath,
                metalShaderConverterPath: metalShaderConverterPath,
                includeDirs: <String>[inputDir.path],
              ),
            );

  final Directory rootDir;
  final Directory inputDir;
  final Directory dxilDir;
  final Directory metallibDir;
  final File manifestFile;
  final String? clangPath;
  final String? dxcPath;
  final String? metalShaderConverterPath;
  final int jobs;
  final bool verbose;
  final Directory _cacheDir;
  final CompilerBackend _backend;

  Future<MetalConversionSummary> run() async {
    if (dxcPath == null || dxcPath!.isEmpty) {
      throw StateError('dxc path is required to build DXIL outputs');
    }
    if (metalShaderConverterPath == null || metalShaderConverterPath!.isEmpty) {
      throw StateError('metal-shader-converter path is required to build metallib outputs');
    }
    _cacheDir.createSync(recursive: true);
    final List<File> shaders = _collectShaders();
    if (shaders.isEmpty) {
      _writeManifest(const <Map<String, dynamic>>[]);
      return MetalConversionSummary.empty();
    }
    final List<Map<String, dynamic>> manifestEntries = <Map<String, dynamic>>[];
    final List<ConversionFailure> failures = <ConversionFailure>[];
    int succeeded = 0;
    final List<_ConversionResult?> results =
        List<_ConversionResult?>.filled(shaders.length, null);
    int nextIndex = 0;
    final int workerCount = jobs > shaders.length ? shaders.length : jobs;

    Future<void> worker() async {
      while (true) {
        if (nextIndex >= shaders.length) {
          break;
        }
        final int currentIndex = nextIndex;
        nextIndex++;
        final File shader = shaders[currentIndex];
        final _ConversionResult result = await Future<_ConversionResult>.delayed(
          Duration.zero,
          () => _convertShader(shader),
        );
        results[currentIndex] = result;
        if (verbose) {
          if (result.success) {
            stdout.writeln('Converted ${result.relativeSource}');
          } else {
            stderr.writeln(
              'Failed ${result.relativeSource}: ${result.failure?.message ?? 'unknown'}',
            );
          }
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount == 0 ? 1 : workerCount, (_) => worker()),
    );

    for (final _ConversionResult? result in results) {
      if (result == null) {
        continue;
      }
      manifestEntries.add(_manifestEntryFor(result));
      if (result.success) {
        succeeded++;
      } else if (result.failure != null) {
        failures.add(result.failure!);
      }
    }
    _writeManifest(manifestEntries);
    return MetalConversionSummary(
      total: shaders.length,
      succeeded: succeeded,
      failed: failures.length,
      failedEntries: failures,
    );
  }

  List<File> _collectShaders() {
    if (!inputDir.existsSync()) {
      return const <File>[];
    }
    final List<File> files = <File>[];
    for (final FileSystemEntity entity in inputDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (!entity.path.toLowerCase().endsWith('.hlsl')) {
        continue;
      }
      files.add(entity);
    }
    files.sort((File a, File b) => a.path.compareTo(b.path));
    return files;
  }

  _ConversionResult _convertShader(File shader) {
    final String relative = _relativeToInput(shader.path);
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final CompilerArtifacts artifacts = _backend.compile(shader, relative);
      stopwatch.stop();
      final List<CompilerDiagnostic> diagnostics = artifacts.diagnostics;
      final File? dxilSource = artifacts.dxilFile;
      final File? metallibSource = artifacts.metallibFile;
      if (dxilSource == null) {
        return _ConversionResult.failure(
          relative,
          stopwatch.elapsed,
          diagnostics,
          'DXIL artifact missing',
        );
      }
      if (metallibSource == null) {
        return _ConversionResult.failure(
          relative,
          stopwatch.elapsed,
          diagnostics,
          'Metallib artifact missing',
        );
      }
      final File dxilTarget = _materializeOutput(dxilSource, dxilDir, relative, '.dxil');
      final File metallibTarget = _materializeOutput(metallibSource, metallibDir, relative, '.metallib');
      return _ConversionResult.success(
        relative,
        stopwatch.elapsed,
        diagnostics,
        dxilTarget,
        metallibTarget,
        artifacts.fromCache,
      );
    } catch (error) {
      stopwatch.stop();
      return _ConversionResult.failure(
        relative,
        stopwatch.elapsed,
        const <CompilerDiagnostic>[],
        error.toString(),
      );
    }
  }

  File _materializeOutput(
    File source,
    Directory baseDir,
    String relative,
    String extension,
  ) {
    final String targetRelative = p.setExtension(relative, extension);
    final File target = File(p.join(baseDir.path, targetRelative));
    target.parent.createSync(recursive: true);
    return source.copySync(target.path);
  }

  void _writeManifest(List<Map<String, dynamic>> entries) {
    final JsonEncoder encoder = const JsonEncoder.withIndent('  ');
    manifestFile.writeAsStringSync(encoder.convert(entries));
  }

  String _relativeToInput(String path) {
    final String normalizedInput = p.normalize(inputDir.path);
    final String normalizedTarget = p.normalize(path);
    final String relative = p.relative(normalizedTarget, from: normalizedInput);
    return relative.replaceAll('\\', '/');
  }

  String _relativeToRoot(String path) {
    final String normalizedRoot = p.normalize(rootDir.path);
    final String normalizedTarget = p.normalize(path);
    final String relative = p.relative(normalizedTarget, from: normalizedRoot);
    return relative.replaceAll('\\', '/');
  }

  List<Map<String, dynamic>> _diagnosticsToJson(
    List<CompilerDiagnostic> diagnostics,
  ) {
    return diagnostics
        .map(
          (CompilerDiagnostic diagnostic) => <String, dynamic>{
            'message': diagnostic.message,
            'severity': diagnostic.severity.name,
            'source': diagnostic.source,
            if (diagnostic.exitCode != null) 'exitCode': diagnostic.exitCode,
          },
        )
        .toList();
  }

  Map<String, dynamic> _manifestEntryFor(_ConversionResult result) {
    final List<Map<String, dynamic>> diagnosticsJson =
        _diagnosticsToJson(result.diagnostics);
    if (!result.success) {
      return <String, dynamic>{
        'source': result.relativeSource,
        'status': 'failed',
        'durationMs': result.duration.inMilliseconds,
        'diagnostics': diagnosticsJson,
        'reason': result.failure?.message,
      };
    }
    return <String, dynamic>{
      'source': result.relativeSource,
      'status': 'success',
      'durationMs': result.duration.inMilliseconds,
      'dxil': result.dxilFile != null
          ? _relativeToRoot(result.dxilFile!.path)
          : null,
      'metallib': result.metallibFile != null
          ? _relativeToRoot(result.metallibFile!.path)
          : null,
      'fromCache': result.fromCache,
      'diagnostics': diagnosticsJson,
    };
  }
}

class MetalConversionSummary {
  const MetalConversionSummary({
    required this.total,
    required this.succeeded,
    required this.failed,
    required this.failedEntries,
  });

  final int total;
  final int succeeded;
  final int failed;
  final List<ConversionFailure> failedEntries;

  factory MetalConversionSummary.empty() => const MetalConversionSummary(
        total: 0,
        succeeded: 0,
        failed: 0,
        failedEntries: <ConversionFailure>[],
      );
}

class ConversionFailure {
  const ConversionFailure({
    required this.sourcePath,
    required this.message,
    required this.diagnostics,
  });

  final String sourcePath;
  final String message;
  final List<String> diagnostics;
}

class _ConversionResult {
  _ConversionResult.success(
    this.relativeSource,
    this.duration,
    this.diagnostics,
    this.dxilFile,
    this.metallibFile,
    this.fromCache,
  )   : success = true,
        failure = null;

  _ConversionResult.failure(
    this.relativeSource,
    this.duration,
    this.diagnostics,
    String reason,
  )   : success = false,
        dxilFile = null,
        metallibFile = null,
        fromCache = false,
        failure = ConversionFailure(
          sourcePath: relativeSource,
          message: reason,
          diagnostics: diagnostics
              .map(
                (CompilerDiagnostic diagnostic) =>
                    '${diagnostic.severity.name}:${diagnostic.source}:${diagnostic.message}',
              )
              .toList(),
        );

  final bool success;
  final String relativeSource;
  final Duration duration;
  final List<CompilerDiagnostic> diagnostics;
  final File? dxilFile;
  final File? metallibFile;
  final bool fromCache;
  final ConversionFailure? failure;
}









