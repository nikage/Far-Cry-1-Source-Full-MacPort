import 'dart:io';

import 'package:shader_port/source_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('ShaderSourceResolver', () {
    test('reads file contents using FileShaderSourceResolver', () {
      final Directory tmpDir = Directory.systemTemp.createTempSync('shader_port');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final File shaderFile = File('${tmpDir.path}/test.crycg');
      shaderFile.writeAsStringSync('MainInput { uniform float4 Test; }');
      final ShaderSourceResolver resolver = const FileShaderSourceResolver();
      final ShaderSource result = resolver.resolve(shaderFile, 'Testing/test.crycg');
      expect(result.content, contains('MainInput'));
    });
  });
}
