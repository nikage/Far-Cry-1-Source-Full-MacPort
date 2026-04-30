import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shader_port/compiler_backend.dart';
import 'package:shader_port/metal_conversion_service.dart';
import 'package:test/test.dart';

void main() {
  late Directory rootDir;
  late Directory inputDir;
  late Directory dxilDir;
  late Directory metallibDir;
  late File manifestFile;

  setUp(() {
    rootDir = Directory.systemTemp.createTempSync('metal_converter_test_');
    inputDir = Directory(p.join(rootDir.path, 'input'))..createSync(recursive: true);
    dxilDir = Directory(p.join(rootDir.path, 'dxil'))..createSync(recursive: true);
    metallibDir = Directory(p.join(rootDir.path, 'metallib'))..createSync(recursive: true);
    manifestFile = File(p.join(rootDir.path, 'manifest.json'));
  });

  tearDown(() {
    if (rootDir.existsSync()) {
      rootDir.deleteSync(recursive: true);
    }
  });

  test('copies artifacts and records success in manifest', () async {
    final File shaderFile = File(p.join(inputDir.path, 'shader.hlsl'))
      ..createSync(recursive: true)
      ..writeAsStringSync('float4 main() : SV_Target { return 0; }');
    final File dxilSource = File(p.join(rootDir.path, 'dxil_source.dxil'))
      ..writeAsStringSync('dxil');
    final File metallibSource = File(p.join(rootDir.path, 'metallib_source.metallib'))
      ..writeAsStringSync('metallib');
    final CompilerArtifacts artifacts = CompilerArtifacts(
      source: shaderFile.readAsStringSync(),
      expandedFile: shaderFile,
      dxilFile: dxilSource,
      metallibFile: metallibSource,
      reflectionFile: null,
      reflection: null,
      diagnostics: const <CompilerDiagnostic>[],
      fromCache: false,
    );
    final Directory cacheDir = Directory(p.join(rootDir.path, 'cache'))..createSync(recursive: true);
    final _FakeCompilerBackend backend = _FakeCompilerBackend(
      CompilerBackendConfig(cacheDir: cacheDir),
      <String, CompilerArtifacts>{'shader.hlsl': artifacts},
    );
    final MetalConversionService service = MetalConversionService(
      rootDir: rootDir,
      inputDir: inputDir,
      dxilDir: dxilDir,
      metallibDir: metallibDir,
      manifestFile: manifestFile,
      jobs: 2,
      verbose: false,
      clangPath: 'clang',
      dxcPath: 'dxc',
      metalShaderConverterPath: 'msc',
      backend: backend,
      cacheDir: cacheDir,
    );
    final MetalConversionSummary summary = await service.run();
    expect(summary.total, 1);
    expect(summary.succeeded, 1);
    final File copiedDxil = File(p.join(dxilDir.path, 'shader.dxil'));
    final File copiedMetallib = File(p.join(metallibDir.path, 'shader.metallib'));
    expect(copiedDxil.existsSync(), isTrue);
    expect(copiedMetallib.existsSync(), isTrue);
    final List<dynamic> manifestEntries =
        jsonDecode(manifestFile.readAsStringSync()) as List<dynamic>;
    expect(manifestEntries.length, 1);
    expect(manifestEntries.first['status'], 'success');
    expect(manifestEntries.first['dxil'], endsWith('dxil/shader.dxil'));
  });

  test('records failure when metallib is missing', () async {
    final File shaderFile = File(p.join(inputDir.path, 'broken.hlsl'))
      ..createSync(recursive: true)
      ..writeAsStringSync('float4 main() : SV_Target { return 1; }');
    final File dxilSource = File(p.join(rootDir.path, 'broken.dxil'))
      ..writeAsStringSync('dxil');
    final CompilerArtifacts artifacts = CompilerArtifacts(
      source: shaderFile.readAsStringSync(),
      expandedFile: shaderFile,
      dxilFile: dxilSource,
      metallibFile: null,
      reflectionFile: null,
      reflection: null,
      diagnostics: <CompilerDiagnostic>[
        CompilerDiagnostic(
          message: 'metallib missing',
          severity: CompilerDiagnosticSeverity.error,
          source: 'metal',
        ),
      ],
      fromCache: false,
    );
    final Directory cacheDir = Directory(p.join(rootDir.path, 'cache'))..createSync(recursive: true);
    final _FakeCompilerBackend backend = _FakeCompilerBackend(
      CompilerBackendConfig(cacheDir: cacheDir),
      <String, CompilerArtifacts>{'broken.hlsl': artifacts},
    );
    final MetalConversionService service = MetalConversionService(
      rootDir: rootDir,
      inputDir: inputDir,
      dxilDir: dxilDir,
      metallibDir: metallibDir,
      manifestFile: manifestFile,
      jobs: 1,
      verbose: false,
      clangPath: 'clang',
      dxcPath: 'dxc',
      metalShaderConverterPath: 'msc',
      backend: backend,
      cacheDir: cacheDir,
    );
    final MetalConversionSummary summary = await service.run();
    expect(summary.failed, 1);
    expect(summary.failedEntries.first.message, contains('Metallib artifact missing'));
    final List<dynamic> manifestEntries =
        jsonDecode(manifestFile.readAsStringSync()) as List<dynamic>;
    expect(manifestEntries.first['status'], 'failed');
    expect(manifestEntries.first['reason'], 'Metallib artifact missing');
    expect(File(p.join(dxilDir.path, 'broken.dxil')).existsSync(), isFalse);
  });

  test('run() with empty input directory returns zero-count summary and writes empty manifest', () async {
    final Directory cacheDir = Directory(p.join(rootDir.path, 'cache'))
      ..createSync(recursive: true);
    final _FakeCompilerBackend backend = _FakeCompilerBackend(
      CompilerBackendConfig(cacheDir: cacheDir),
      <String, CompilerArtifacts>{},
    );
    final MetalConversionService service = MetalConversionService(
      rootDir: rootDir,
      inputDir: inputDir,
      dxilDir: dxilDir,
      metallibDir: metallibDir,
      manifestFile: manifestFile,
      jobs: 1,
      verbose: false,
      clangPath: 'clang',
      dxcPath: 'dxc',
      metalShaderConverterPath: 'msc',
      backend: backend,
      cacheDir: cacheDir,
    );
    final MetalConversionSummary summary = await service.run();
    expect(summary.total, 0);
    expect(summary.succeeded, 0);
    expect(summary.failed, 0);
    expect(summary.failedEntries, isEmpty);
    final List<dynamic> manifestEntries =
        jsonDecode(manifestFile.readAsStringSync()) as List<dynamic>;
    expect(manifestEntries, isEmpty);
  });

  test('run() processes multiple shaders and reports correct total', () async {
    final Directory cacheDir = Directory(p.join(rootDir.path, 'cache'))
      ..createSync(recursive: true);

    CompilerArtifacts makeArtifacts(File shaderFile, File dxilSrc, File metallibSrc) {
      return CompilerArtifacts(
        source: shaderFile.readAsStringSync(),
        expandedFile: shaderFile,
        dxilFile: dxilSrc,
        metallibFile: metallibSrc,
        reflectionFile: null,
        reflection: null,
        diagnostics: const <CompilerDiagnostic>[],
        fromCache: false,
      );
    }

    final File shaderA = File(p.join(inputDir.path, 'a.hlsl'))
      ..writeAsStringSync('float4 mainA() : SV_Target { return 0; }');
    final File shaderB = File(p.join(inputDir.path, 'b.hlsl'))
      ..writeAsStringSync('float4 mainB() : SV_Target { return 1; }');

    final File dxilA = File(p.join(rootDir.path, 'a.dxil'))..writeAsStringSync('dxil_a');
    final File metallibA = File(p.join(rootDir.path, 'a.metallib'))..writeAsStringSync('metallib_a');
    final File dxilB = File(p.join(rootDir.path, 'b.dxil'))..writeAsStringSync('dxil_b');
    final File metallibB = File(p.join(rootDir.path, 'b.metallib'))..writeAsStringSync('metallib_b');

    final _FakeCompilerBackend backend = _FakeCompilerBackend(
      CompilerBackendConfig(cacheDir: cacheDir),
      <String, CompilerArtifacts>{
        'a.hlsl': makeArtifacts(shaderA, dxilA, metallibA),
        'b.hlsl': makeArtifacts(shaderB, dxilB, metallibB),
      },
    );
    final MetalConversionService service = MetalConversionService(
      rootDir: rootDir,
      inputDir: inputDir,
      dxilDir: dxilDir,
      metallibDir: metallibDir,
      manifestFile: manifestFile,
      jobs: 2,
      verbose: false,
      clangPath: 'clang',
      dxcPath: 'dxc',
      metalShaderConverterPath: 'msc',
      backend: backend,
      cacheDir: cacheDir,
    );
    final MetalConversionSummary summary = await service.run();
    expect(summary.total, 2);
    expect(summary.succeeded, 2);
    expect(summary.failed, 0);
    final List<dynamic> manifestEntries =
        jsonDecode(manifestFile.readAsStringSync()) as List<dynamic>;
    expect(manifestEntries.length, 2);
  });
}

class _FakeCompilerBackend extends CompilerBackend {
  _FakeCompilerBackend(CompilerBackendConfig config, this.records) : super(config);

  final Map<String, CompilerArtifacts> records;

  @override
  CompilerArtifacts compile(File source, String relativePath) {
    final CompilerArtifacts? artifacts = records[relativePath];
    if (artifacts == null) {
      throw StateError('No artifacts stubbed for $relativePath');
    }
    return artifacts;
  }
}
