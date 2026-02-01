import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef DxcProfileEntry = ({String entry, String profile});

enum CompilerDiagnosticSeverity { info, warning, error }

class CompilerDiagnostic {
  CompilerDiagnostic({
    required this.message,
    required this.severity,
    required this.source,
    this.exitCode,
  });

  final String message;
  final CompilerDiagnosticSeverity severity;
  final String source;
  final int? exitCode;
}

class CompilerBackendConfig {
  CompilerBackendConfig({
    required this.cacheDir,
    this.clangPath,
    this.dxcPath,
    this.metalShaderConverterPath,
    List<String>? includeDirs,
    List<String>? defines,
    this.entryResolver,
  })  : includeDirs = includeDirs ?? const <String>[],
        defines = defines ?? const <String>[];

  final Directory cacheDir;
  final String? clangPath;
  final String? dxcPath;
  final String? metalShaderConverterPath;
  final List<String> includeDirs;
  final List<String> defines;
  final DxcProfileEntry? Function(String relativePath)? entryResolver;
}

class CompilerArtifacts {
  CompilerArtifacts({
    required this.source,
    required this.expandedFile,
    this.dxilFile,
    this.metallibFile,
    this.reflectionFile,
    this.reflection,
    required this.diagnostics,
    required this.fromCache,
  });

  final String source;
  final File expandedFile;
  final File? dxilFile;
  final File? metallibFile;
  final File? reflectionFile;
  final Map<String, dynamic>? reflection;
  final List<CompilerDiagnostic> diagnostics;
  final bool fromCache;
}

class CompilerBackend {
  CompilerBackend(this.config) {
    config.cacheDir.createSync(recursive: true);
  }

  final CompilerBackendConfig config;

  CompilerArtifacts compile(File source, String relativePath) {
    final Directory artifactDir = _artifactDirectory(relativePath);
    final File expandedFile = File(p.join(artifactDir.path, 'expanded.cg')); 
    final File dxilFile = File(p.join(artifactDir.path, 'shader.dxil'));
    final File metallibFile = File(p.join(artifactDir.path, 'shader.metallib'));
    final File reflectionFile = File('${metallibFile.path}.json');
    final List<CompilerDiagnostic> diagnostics = <CompilerDiagnostic>[];
    final bool needsRefresh = !_isUpToDate(source, expandedFile);
    if (needsRefresh) {
      artifactDir.createSync(recursive: true);
      _preprocessSource(source, expandedFile, diagnostics);
      if (config.dxcPath != null) {
        _compileDxil(expandedFile, dxilFile, relativePath, diagnostics);
      }
      if (config.metalShaderConverterPath != null && dxilFile.existsSync()) {
        _runMetalShaderConverter(dxilFile, metallibFile, diagnostics);
      }
    }
    final String expandedSource = expandedFile.existsSync()
        ? expandedFile.readAsStringSync()
        : source.readAsStringSync();
    Map<String, dynamic>? reflection;
    if (reflectionFile.existsSync()) {
      reflection = _readReflection(reflectionFile);
    }
    return CompilerArtifacts(
      source: expandedSource,
      expandedFile: expandedFile,
      dxilFile: dxilFile.existsSync() ? dxilFile : null,
      metallibFile: metallibFile.existsSync() ? metallibFile : null,
      reflectionFile: reflectionFile.existsSync() ? reflectionFile : null,
      reflection: reflection,
      diagnostics: diagnostics,
      fromCache: !needsRefresh,
    );
  }

  Directory _artifactDirectory(String relativePath) {
    final String safeName = relativePath.replaceAll(RegExp(r'[\\/]+'), '_');
    return Directory(p.join(config.cacheDir.path, safeName));
  }

  bool _isUpToDate(File source, File expandedFile) {
    if (!expandedFile.existsSync()) {
      return false;
    }
    final DateTime srcTime = source.lastModifiedSync();
    final DateTime outTime = expandedFile.lastModifiedSync();
    return !srcTime.isAfter(outTime);
  }

  void _preprocessSource(
    File input,
    File output,
    List<CompilerDiagnostic> diagnostics,
  ) {
    if (config.clangPath == null) {
      output.writeAsStringSync(input.readAsStringSync());
      return;
    }
    final List<String> args = <String>[
      '-E',
      '-P',
      '-x',
      'c',
      input.path,
      '-o',
      output.path,
    ];
    for (final String dir in config.includeDirs) {
      args.add('-I$dir');
    }
    for (final String define in config.defines) {
      args.add('-D$define');
    }
    try {
      final ProcessResult result = Process.runSync(config.clangPath!, args);
      if (result.exitCode != 0) {
        diagnostics.add(
          CompilerDiagnostic(
            message: (result.stderr as String?) ?? 'clang preprocessing failed',
            severity: CompilerDiagnosticSeverity.error,
            source: 'clang',
            exitCode: result.exitCode,
          ),
        );
        output.writeAsStringSync(input.readAsStringSync());
      }
    } on ProcessException catch (error) {
      diagnostics.add(
        CompilerDiagnostic(
          message: error.toString(),
          severity: CompilerDiagnosticSeverity.error,
          source: 'clang',
          exitCode: error.errorCode,
        ),
      );
      output.writeAsStringSync(input.readAsStringSync());
    }
  }

  void _compileDxil(
    File input,
    File output,
    String relativePath,
    List<CompilerDiagnostic> diagnostics,
  ) {
    final DxcProfileEntry? resolved = config.entryResolver?.call(relativePath);
    if (resolved == null) {
      throw StateError('Missing DXC entry/profile for $relativePath');
    }
    final List<String> args = <String>[
      input.path,
      '-E',
      resolved.entry,
      '-T',
      resolved.profile,
      '-Fo',
      output.path,
    ];
    for (final String dir in config.includeDirs) {
      args.add('-I$dir');
    }
    try {
      if (config.dxcPath == null) {
        throw StateError('dxc path is null');
      }
      final ProcessResult result = Process.runSync(config.dxcPath!, args);
      final bool succeeded = result.exitCode == 0;
      if (!succeeded || _isVerbose()) {
        stdout.writeln('dxc ${args.join(' ')} (exit ${result.exitCode})');
      }
      if (result.exitCode != 0) {
        diagnostics.add(
          CompilerDiagnostic(
            message: (result.stderr as String?) ?? 'dxc compilation failed',
            severity: CompilerDiagnosticSeverity.error,
            source: 'dxc',
            exitCode: result.exitCode,
          ),
        );
        if (output.existsSync()) {
          output.deleteSync();
        }
      }
    } on ProcessException catch (error) {
      diagnostics.add(
        CompilerDiagnostic(
          message: error.toString(),
          severity: CompilerDiagnosticSeverity.error,
          source: 'dxc',
          exitCode: error.errorCode,
        ),
      );
      if (output.existsSync()) {
        output.deleteSync();
      }
    }
  }

  void _runMetalShaderConverter(
    File dxil,
    File metallib,
    List<CompilerDiagnostic> diagnostics,
  ) {
    final List<String> args = <String>[
      dxil.path,
      '-o',
      metallib.path,
    ];
    try {
      if (config.metalShaderConverterPath == null) {
        throw StateError('metal-shader-converter path is null');
      }
      final ProcessResult result =
          Process.runSync(config.metalShaderConverterPath!, args);
      final bool succeeded = result.exitCode == 0;
      if (!succeeded || _isVerbose()) {
        stdout.writeln('metal-shader-converter ${args.join(' ')} (exit ${result.exitCode})');
      }
      if (result.exitCode != 0) {
        diagnostics.add(
          CompilerDiagnostic(
            message:
                (result.stderr as String?) ?? 'metal shader converter failed',
            severity: CompilerDiagnosticSeverity.error,
            source: 'metal-shaderconverter',
            exitCode: result.exitCode,
          ),
        );
        if (metallib.existsSync()) {
          metallib.deleteSync();
        }
      }
    } on ProcessException catch (error) {
      diagnostics.add(
        CompilerDiagnostic(
          message: error.toString(),
          severity: CompilerDiagnosticSeverity.error,
          source: 'metal-shaderconverter',
          exitCode: error.errorCode,
        ),
      );
      if (metallib.existsSync()) {
        metallib.deleteSync();
      }
    }
  }

  String _profileForPath(String relativePath) {
    final String lower = relativePath.toLowerCase();
    if (lower.contains('/cgvshaders/') || lower.contains('cgvshader')) {
      return 'vs_3_0';
    }
    return 'ps_3_0';
  }

  Map<String, dynamic>? _readReflection(File file) {
    try {
      final String data = file.readAsStringSync();
      if (data.isEmpty) {
        return null;
      }
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  bool _isVerbose() {
    final String? env = Platform.environment['CONVERTER_DEBUG_LOG'];
    return env != null && env.toLowerCase() == 'true';
  }
}
