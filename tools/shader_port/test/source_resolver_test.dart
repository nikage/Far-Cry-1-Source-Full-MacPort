import 'dart:io';

import 'package:shader_port/compiler_backend.dart';
import 'package:shader_port/source_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('FileShaderSourceResolver', () {
    test('reads file contents verbatim', () {
      final Directory tmpDir = Directory.systemTemp.createTempSync('shader_port');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final File shaderFile = File('${tmpDir.path}/test.crycg');
      shaderFile.writeAsStringSync('MainInput { uniform float4 Test; }');
      final ShaderSourceResolver resolver = const FileShaderSourceResolver();
      final ShaderSource result = resolver.resolve(shaderFile, 'Testing/test.crycg');
      expect(result.content, contains('MainInput'));
    });

    test('artifacts field is null for file resolver', () {
      final Directory tmpDir = Directory.systemTemp.createTempSync('shader_port');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final File shaderFile = File('${tmpDir.path}/a.crycg')
        ..writeAsStringSync('// empty');
      final ShaderSource result =
          const FileShaderSourceResolver().resolve(shaderFile, 'a.crycg');
      expect(result.artifacts, isNull);
    });
  });

  group('CompilerShaderSourceResolver', () {
    test('returns source from CompilerArtifacts.source', () {
      final Directory tmpDir = Directory.systemTemp.createTempSync('shader_port');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      final File shaderFile = File('${tmpDir.path}/shader.hlsl')
        ..writeAsStringSync('float4 main() : SV_Target { return 0; }');
      final CompilerArtifacts artifacts = CompilerArtifacts(
        source: 'float4 expanded_main() : SV_Target { return 1; }',
        expandedFile: shaderFile,
        dxilFile: null,
        metallibFile: null,
        reflectionFile: null,
        reflection: null,
        diagnostics: const <CompilerDiagnostic>[],
        fromCache: false,
      );
      final Directory cacheDir = Directory('${tmpDir.path}/cache')
        ..createSync(recursive: true);
      final _FakeCompilerBackend backend = _FakeCompilerBackend(
        CompilerBackendConfig(cacheDir: cacheDir),
        artifacts,
      );
      final CompilerShaderSourceResolver resolver =
          CompilerShaderSourceResolver(backend);
      final ShaderSource result = resolver.resolve(shaderFile, 'shader.hlsl');

      expect(result.content, 'float4 expanded_main() : SV_Target { return 1; }');
      expect(result.artifacts, isNotNull);
    });

    test('artifacts field carries the CompilerArtifacts from backend', () {
      final Directory tmpDir = Directory.systemTemp.createTempSync('shader_port');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      final File shaderFile = File('${tmpDir.path}/s.hlsl')
        ..writeAsStringSync('// src');
      final CompilerArtifacts artifacts = CompilerArtifacts(
        source: '// expanded',
        expandedFile: shaderFile,
        dxilFile: null,
        metallibFile: null,
        reflectionFile: null,
        reflection: null,
        diagnostics: const <CompilerDiagnostic>[],
        fromCache: true,
      );
      final Directory cacheDir = Directory('${tmpDir.path}/cache')
        ..createSync(recursive: true);
      final _FakeCompilerBackend backend = _FakeCompilerBackend(
        CompilerBackendConfig(cacheDir: cacheDir),
        artifacts,
      );
      final ShaderSource result =
          CompilerShaderSourceResolver(backend).resolve(shaderFile, 's.hlsl');
      expect(result.artifacts?.fromCache, isTrue);
    });
  });
}

class _FakeCompilerBackend extends CompilerBackend {
  _FakeCompilerBackend(CompilerBackendConfig config, this._artifacts)
      : super(config);

  final CompilerArtifacts _artifacts;

  @override
  CompilerArtifacts compile(File source, String relativePath) => _artifacts;
}
