import 'dart:convert';
import 'dart:io';

class UniformBinding {
  UniformBinding(this.type, this.name);
  final String type;
  final String name;
}

class TextureBinding {
  TextureBinding(this.type, this.name, this.slot);
  final String type;
  final String name;
  final int slot;
}

void main(List<String> args) {
  final Directory root = (args.isEmpty ? Directory.current : Directory(args.first)).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath = root.path.endsWith(sep) ? root.path : root.path + sep;
  final Directory irDir = Directory(rootPath + 'tools${sep}shader_port${sep}output${sep}ir');
  if (!irDir.existsSync()) {
    stderr.writeln('Missing IR directory: ${irDir.path}');
    exit(1);
  }
  final Directory outDir = Directory(rootPath + 'RenderDll${sep}XRenderMetal${sep}Generated');
  outDir.createSync(recursive: true);
  final File manifest = File(outDir.path + sep + 'generated_manifest.json');
  final List<Map<String, dynamic>> manifestEntries = [];
  int generated = 0;
  for (final FileSystemEntity entity in irDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.json')) continue;
    final dynamic parsed = jsonDecode(entity.readAsStringSync(encoding: utf8));
    if (parsed is! Map<String, dynamic>) continue;
    final Map<String, dynamic> ir = parsed;
    final String extension = (ir['extension'] as String? ?? '').toLowerCase();
    if (extension != 'cryps' && extension != 'crycg') continue;
    final String relative = entity.path.substring(irDir.path.length + 1).replaceAll(RegExp(r'[\\/]'), '/');
    final String shaderName = (ir['name'] as String? ?? '').isEmpty ? relative : ir['name'] as String;
    final List<dynamic> blocks = ir['blocks'] as List<dynamic>? ?? [];
    final Map<String, dynamic>? mainInputBlock = blocks.cast<Map<String, dynamic>?>().firstWhere(
        (block) => block != null && (block['name'] as String?)?.toLowerCase() == 'maininput',
        orElse: () => null);
    final List<UniformBinding> uniforms = [];
    final List<TextureBinding> textures = [];
    final Set<String> uniformNames = <String>{};
    final Set<String> textureNames = <String>{};
    if (mainInputBlock != null) {
      final String content = (mainInputBlock['content'] as String?) ?? '';
      final RegExp pattern = RegExp(r'uniform\s+(\w+)\s+(\w+)(?:\s*:\s*([^,]+))?', multiLine: true);
      int slot = 0;
      for (final Match match in pattern.allMatches(content)) {
        final String type = match.group(1) ?? '';
        final String name = match.group(2) ?? '';
        if (type.isEmpty || name.isEmpty) continue;
        if (type.toLowerCase().startsWith('sampler')) {
          if (textureNames.add(name)) {
            textures.add(TextureBinding(type, name, slot));
            slot++;
          }
        } else {
          if (uniformNames.add(name)) {
            uniforms.add(UniformBinding(type, name));
          }
        }
      }
    }
    final String normalized = normalizeName(shaderName);
    final String fragmentName = 'generated_${normalized}_fragment';
    final String uniformStruct = '${normalized}_uniforms';
    final String metalFileName = '${relative.replaceAll('/', '_')}.metal';
    final File targetFile = File(outDir.path + sep + metalFileName);
    targetFile.parent.createSync(recursive: true);
    targetFile.writeAsStringSync(buildMetal(uniformStruct, fragmentName, uniforms, textures));
    manifestEntries.add({
      'source': relative,
      'metal': metalFileName,
      'shader': shaderName,
      'normalized': normalized,
      'fragment': fragmentName,
      'uniformStruct': uniformStruct,
      'uniformCount': uniforms.length,
      'textureCount': textures.length
    });
    generated++;
  }
  manifest.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifestEntries));
  stdout.writeln('Generated $generated Metal shader fragments');
}

String normalizeName(String input) {
  final String lower = input.toLowerCase();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < lower.length; i++) {
    final int code = lower.codeUnitAt(i);
    if ((code >= 97 && code <= 122) || (code >= 48 && code <= 57)) {
      buffer.writeCharCode(code);
    } else {
      buffer.write('_');
    }
  }
  String normalized = buffer.toString().replaceAll(RegExp('_+'), '_');
  normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
  if (normalized.isEmpty) normalized = 'shader';
  return normalized;
}

String buildMetal(String uniformStruct, String fragmentName, List<UniformBinding> uniforms, List<TextureBinding> textures) {
  final StringBuffer buffer = StringBuffer();
  buffer.writeln('#include <metal_stdlib>');
  buffer.writeln('using namespace metal;');
  buffer.writeln();
  if (uniforms.isNotEmpty) {
    buffer.writeln('struct ${uniformStruct} {');
    for (final UniformBinding uniform in uniforms) {
      buffer.writeln('  ${translateType(uniform.type)} ${uniform.name};');
    }
    buffer.writeln('};');
    buffer.writeln();
  }
  buffer.writeln('struct GeneratedFragmentInput {');
  buffer.writeln('  float4 position [[position]];');
  buffer.writeln('  float4 color;');
  buffer.writeln('  float2 texCoord;');
  buffer.writeln('  float clipDistance;');
  buffer.writeln('};');
  buffer.writeln();
  final List<String> params = [];
  params.add('GeneratedFragmentInput inInput [[stage_in]]');
  if (uniforms.isNotEmpty) {
    params.add('constant ${uniformStruct}& uniforms [[buffer(0)]]');
  }
  for (final TextureBinding texture in textures) {
    params.add('${translateTextureType(texture.type)} ${texture.name} [[texture(${texture.slot})]]');
    params.add('sampler ${texture.name}Sampler [[sampler(${texture.slot})]]');
  }
  buffer.writeln('fragment float4 ${fragmentName}(${params.join(', ')})');
  buffer.writeln('{');
  buffer.writeln('  float4 color = inInput.color;');
  if (textures.isNotEmpty) {
    final TextureBinding texture = textures.first;
    final String lower = texture.type.toLowerCase();
    if (lower.contains('3d') || lower.contains('cube')) {
      buffer.writeln('  // Texture sampling not implemented for ${texture.type}; keeping input color');
    } else {
      buffer.writeln('  color = ${texture.name}.sample(${texture.name}Sampler, inInput.texCoord);');
    }
  }
  for (final UniformBinding uniform in uniforms) {
    final String lower = uniform.type.toLowerCase();
    if (lower == 'float4') {
      buffer.writeln('  color *= uniforms.${uniform.name};');
      break;
    }
  }
  buffer.writeln('  return color;');
  buffer.writeln('}');
  return buffer.toString();
}

String translateType(String type) {
  switch (type.toLowerCase()) {
    case 'float':
      return 'float';
    case 'float2':
      return 'float2';
    case 'float3':
      return 'float3';
    case 'float4':
      return 'float4';
    default:
      return 'float4';
  }
}

String translateTextureType(String type) {
  final String lower = type.toLowerCase();
  if (lower.contains('cube')) return 'texturecube<float>';
  if (lower.contains('3d')) return 'texture3d<float>';
  return 'texture2d<float>';
}
