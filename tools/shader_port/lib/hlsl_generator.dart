import 'dart:convert';
import 'dart:io';

class UniformBinding {
  UniformBinding(this.type, this.name, this.semantic);
  final String type;
  final String name;
  final String semantic;
}

class TextureBinding {
  TextureBinding(this.type, this.name, this.semantic, this.slot);
  final String type;
  final String name;
  final String semantic;
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
  final Directory outDir = Directory(rootPath + 'tools${sep}shader_port${sep}output${sep}hlsl');
  outDir.createSync(recursive: true);
  int generated = 0;
  for (final FileSystemEntity entity in irDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.json')) continue;
    final dynamic parsed = jsonDecode(entity.readAsStringSync(encoding: utf8));
    if (parsed is! Map<String, dynamic>) continue;
    final Map<String, dynamic> ir = parsed;
    final String extension = (ir['extension'] as String? ?? '').toLowerCase();
    if (extension != 'cryps' && extension != 'crycg') continue;
    final String relativeJson = entity.path.substring(irDir.path.length + 1).replaceAll(RegExp(r'[\\/]'), '/');
    final String relativeHlsl = relativeJson.replaceAll('.json', '.hlsl');
    final File targetFile = File(outDir.path + sep + relativeHlsl);
    targetFile.parent.createSync(recursive: true);
    final String hlsl = buildHlsl(ir);
    targetFile.writeAsStringSync(hlsl);
    generated++;
  }
  final File manifest = File(outDir.path + sep + 'index.json');
  manifest.writeAsStringSync(jsonEncode({'count': generated}));
  stdout.writeln('Generated $generated HLSL shaders');
}

String buildHlsl(Map<String, dynamic> ir) {
  final List<dynamic> blocks = ir['blocks'] as List<dynamic>? ?? [];
  final Map<String, dynamic>? mainInputBlock = blocks.cast<Map<String, dynamic>?>().firstWhere(
      (block) => block != null && (block['name'] as String?)?.toLowerCase() == 'maininput',
      orElse: () => null);
  final List<UniformBinding> uniforms = [];
  final List<TextureBinding> textures = [];
  if (mainInputBlock != null) {
    final String content = (mainInputBlock['content'] as String?) ?? '';
    final RegExp pattern = RegExp(r'uniform\s+(\w+)\s+(\w+)(?:\s*:\s*([^,]+))?', multiLine: true);
    int slot = 0;
    for (final Match match in pattern.allMatches(content)) {
      final String type = match.group(1) ?? '';
      final String name = match.group(2) ?? '';
      final String semantic = (match.group(3) ?? '').trim();
      if (type.isEmpty || name.isEmpty) continue;
      if (type.toLowerCase().startsWith('sampler')) {
        textures.add(TextureBinding(type, name, semantic, slot));
        slot++;
      } else {
        uniforms.add(UniformBinding(type, name, semantic));
      }
    }
  }
  final StringBuffer buffer = StringBuffer();
  if (uniforms.isNotEmpty) {
    buffer.writeln('cbuffer GeneratedUniforms : register(b0) {');
    for (final UniformBinding uniform in uniforms) {
      buffer.writeln('  ${translateType(uniform.type)} ${uniform.name};');
    }
    buffer.writeln('}');
    buffer.writeln();
  }
  for (final TextureBinding texture in textures) {
    buffer.writeln('${translateTextureType(texture.type)} ${texture.name} : register(t${texture.slot});');
    buffer.writeln('SamplerState ${texture.name}Sampler : register(s${texture.slot});');
  }
  if (textures.isNotEmpty) buffer.writeln();
  buffer.writeln('struct GeneratedInput {');
  buffer.writeln('  float4 position : SV_POSITION;');
  buffer.writeln('  float2 texCoord0 : TEXCOORD0;');
  buffer.writeln('};');
  buffer.writeln();
  buffer.writeln('float4 GeneratedMain(GeneratedInput input) : SV_Target');
  buffer.writeln('{');
  buffer.writeln('  float4 color = float4(0.0, 0.0, 0.0, 1.0);');
  if (textures.isNotEmpty) {
    buffer.writeln('  color = ${textures.first.name}.Sample(${textures.first.name}Sampler, input.texCoord0);');
    if (uniforms.isNotEmpty) {
      final UniformBinding firstUniform = uniforms.first;
      buffer.writeln('  color *= ${firstUniform.name};');
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
  if (lower.contains('cube')) return 'TextureCube';
  if (lower.contains('3d')) return 'Texture3D';
  return 'Texture2D';
}
