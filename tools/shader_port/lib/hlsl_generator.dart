import 'dart:convert';
import 'dart:io';

class UniformBinding {
  UniformBinding(this.type, this.name, this.semantic);
  final String type;
  final String name;
  final String semantic;
}

class TextureBinding {
  TextureBinding(this.type, this.name, this.slot, this.semantic);
  final String type;
  final String name;
  final int slot;
  final String semantic;
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
  final Set<String> uniformNames = <String>{};
  final Set<String> textureNames = <String>{};
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
        if (textureNames.add(name)) {
          textures.add(TextureBinding(type, name, slot, semantic));
          slot++;
        }
      } else {
        if (uniformNames.add(name)) {
          uniforms.add(UniformBinding(type, name, semantic));
        }
      }
    }
  }

  final List<dynamic> coreExpressions = ir['coreScriptExpressions'] as List<dynamic>? ?? [];
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
  buffer.writeln('  float4 color : COLOR0;');
  buffer.writeln('  float4 color1 : COLOR1;');
  for (int i = 0; i < 8; i++) {
    buffer.writeln('  float4 texCoord$i : TEXCOORD$i;');
  }
  buffer.writeln('  float clipDistance : TEXCOORD8;');
  buffer.writeln('};');
  buffer.writeln();

  buffer.writeln('float4 GeneratedMain(GeneratedInput input) : SV_Target');
  buffer.writeln('{');
  buffer.writeln('  float4 result = input.color;');

  final List<String> translatedCore = translateCoreScript(coreExpressions);
  if (translatedCore.isNotEmpty) {
    for (final String line in translatedCore) {
      buffer.writeln('  $line');
    }
  } else {
    if (textures.isNotEmpty) {
      final TextureBinding texture = textures.first;
      final String lower = texture.type.toLowerCase();
      if (lower.contains('3d') || lower.contains('cube')) {
        buffer.writeln('  // Texture sampling not implemented for ${texture.type}; keeping input color');
      } else {
        buffer.writeln('  result = ${texture.name}.Sample(${texture.name}Sampler, input.texCoord0.xy);');
      }
    }
    for (final UniformBinding uniform in uniforms) {
      final String lower = uniform.type.toLowerCase();
      if (lower == 'float4') {
        buffer.writeln('  result *= ${uniform.name};');
        break;
      }
    }
  }

  buffer.writeln('  return result;');
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
    case 'half4':
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

List<String> translateCoreScript(List<dynamic> coreExpressions) {
  if (coreExpressions.isEmpty) {
    return const [];
  }
  final List<String> lines = [];
  for (final dynamic entry in coreExpressions) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    final String type = entry['type'] as String? ?? 'raw';
    if (type == 'comment') {
      final String value = entry['value'] as String? ?? '';
      lines.add('// $value');
      continue;
    }
    final String rawLine = entry['raw'] as String? ?? '';
    if (rawLine.isEmpty) {
      continue;
    }
    String line = rawLine;
    line = _rewriteOutputs(line);
    line = _rewriteInputs(line);
    line = _rewriteTextureCalls(line);
    lines.add(line);
  }
  return lines;
}

String _rewriteOutputs(String line) {
  return line.replaceAll('OUT.Color', 'result');
}

String _rewriteInputs(String line) {
  String updated = line;
  updated = updated.replaceAll('IN.Color1', 'input.color1');
  updated = updated.replaceAll('IN.Color', 'input.color');
  updated = updated.replaceAll('IN.clipDistance', 'input.clipDistance');
  for (int i = 0; i < 8; i++) {
    updated = updated.replaceAll('IN.Tex$i', 'input.texCoord$i');
  }
  return updated;
}

String _rewriteTextureCalls(String line) {
  String updated = line;
  final RegExp tex2DPattern = RegExp(r'tex2D\s*\(\s*(\w+)\s*,\s*([^\)]+)\)');
  updated = updated.replaceAllMapped(tex2DPattern, (Match match) {
    final String sampler = match.group(1) ?? '';
    final String coords = match.group(2) ?? '';
    if (sampler.isEmpty) {
      return match.group(0) ?? '';
    }
    return '$sampler.Sample(${sampler}Sampler, $coords)';
  });
  final RegExp texCubePattern = RegExp(r'texCUBE\s*\(\s*(\w+)\s*,\s*([^\)]+)\)');
  updated = updated.replaceAllMapped(texCubePattern, (Match match) {
    final String sampler = match.group(1) ?? '';
    final String coords = match.group(2) ?? '';
    if (sampler.isEmpty) {
      return match.group(0) ?? '';
    }
    return '$sampler.Sample(${sampler}Sampler, $coords)';
  });
  return updated;
}
