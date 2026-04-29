import 'dart:io';

import 'compiler_backend.dart';

class ShaderSource {
  ShaderSource(this.content, {this.artifacts});

  final String content;
  final CompilerArtifacts? artifacts;
}

abstract class ShaderSourceResolver {
  const ShaderSourceResolver();

  ShaderSource resolve(File file, String relativePath);
}

class FileShaderSourceResolver extends ShaderSourceResolver {
  const FileShaderSourceResolver();

  @override
  ShaderSource resolve(File file, String relativePath) {
    final String data = file.readAsStringSync();
    return ShaderSource(data);
  }
}

class CompilerShaderSourceResolver extends ShaderSourceResolver {
  const CompilerShaderSourceResolver(this.backend);

  final CompilerBackend backend;

  @override
  ShaderSource resolve(File file, String relativePath) {
    final CompilerArtifacts artifacts = backend.compile(file, relativePath);
    return ShaderSource(artifacts.source, artifacts: artifacts);
  }
}
