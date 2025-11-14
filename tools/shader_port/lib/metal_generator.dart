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

class ShaderIrData {
  ShaderIrData({
    required this.shaderName,
    required this.normalizedName,
    required this.fragmentName,
    required this.uniformStruct,
    required this.uniforms,
    required this.textures,
    required this.coreExpressions,
    required this.coreFlow,
    required this.passStates,
    required this.maskReferences,
  });

  final String shaderName;
  final String normalizedName;
  final String fragmentName;
  final String uniformStruct;
  final List<UniformBinding> uniforms;
  final List<TextureBinding> textures;
  final List<Map<String, dynamic>> coreExpressions;
  final List<Map<String, dynamic>> coreFlow;
  final List<Map<String, dynamic>> passStates;
  final List<String> maskReferences;
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
    final List<dynamic> directivesRaw = ir['directives'] as List<dynamic>? ?? [];
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
          final String semantic = (match.group(3) ?? '').trim();
          textures.add(TextureBinding(type, name, slot, semantic));
            slot++;
          }
        } else {
          if (uniformNames.add(name)) {
          final String semantic = (match.group(3) ?? '').trim();
          uniforms.add(UniformBinding(type, name, semantic));
          }
        }
      }
    }
    final String normalized = normalizeName(shaderName);
    final String fragmentName = 'generated_${normalized}_fragment';
    final String uniformStruct = '${normalized}_uniforms';
    final List<Map<String, dynamic>> coreExpressions =
        _castMapList(ir['coreScriptExpressions'] as List<dynamic>?);
    final List<Map<String, dynamic>> coreFlow =
        _castMapList(ir['coreScriptFlow'] as List<dynamic>?);
    final List<Map<String, dynamic>> passStates =
        _castMapList(ir['passStates'] as List<dynamic>?);
    final List<String> maskReferences =
        _castStringList(ir['maskReferences'] as List<dynamic>?);
    final ShaderIrData data = ShaderIrData(
      shaderName: shaderName,
      normalizedName: normalized,
      fragmentName: fragmentName,
      uniformStruct: uniformStruct,
      uniforms: uniforms,
      textures: textures,
      coreExpressions: coreExpressions,
      coreFlow: coreFlow,
      passStates: passStates,
      maskReferences: maskReferences,
    );
    final String metalFileName = '${relative.replaceAll('/', '_')}.metal';
    final File targetFile = File(outDir.path + sep + metalFileName);
    targetFile.parent.createSync(recursive: true);
    targetFile.writeAsStringSync(buildMetal(data));
    final List<dynamic> vertexAttributes = ir['vertexAttributes'] as List<dynamic>? ?? [];
    final Map<String, dynamic> pipeline = derivePipelineMetadata(shaderName, directivesRaw);
    manifestEntries.add({
      'source': relative,
      'metal': metalFileName,
      'shader': shaderName,
      'normalized': normalized,
      'fragment': fragmentName,
      'uniformStruct': uniformStruct,
      'uniformCount': uniforms.length,
      'textureCount': textures.length,
      'vertexAttributes': vertexAttributes,
      'directives': directivesRaw,
      'maskReferences': data.maskReferences,
      'uniforms': uniforms
          .map((u) => {
                'name': u.name,
                'type': u.type,
                'semantic': u.semantic,
              })
          .toList(),
      'textures': textures
          .map((t) => {
                'name': t.name,
                'type': t.type,
                'semantic': t.semantic,
                'slot': t.slot,
              })
          .toList(),
      'pipeline': pipeline,
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

String buildMetal(ShaderIrData data) {
  final StringBuffer buffer = StringBuffer();
  buffer.writeln('#include <metal_stdlib>');
  buffer.writeln('using namespace metal;');
  buffer.writeln();
  if (data.uniforms.isNotEmpty) {
    buffer.writeln('struct ${data.uniformStruct} {');
    for (final UniformBinding uniform in data.uniforms) {
      buffer.writeln('  ${translateType(uniform.type)} ${uniform.name};');
    }
    buffer.writeln('};');
    buffer.writeln();
  }

  final _InOutAnalyzer analyzer = _InOutAnalyzer(data.coreExpressions, data.coreFlow);
  final String inputStructName = '${data.normalizedName}_input';
  final String outputStructName = '${data.normalizedName}_output';

  buffer.writeln('struct $inputStructName {');
  buffer.writeln('  float4 position [[position]];');
  for (final String field in analyzer.inputFields) {
    buffer.writeln('  float4 $field;');
  }
  buffer.writeln('};');
  buffer.writeln();
  buffer.writeln('struct $outputStructName {');
  for (final String field in analyzer.outputFields) {
    buffer.writeln('  float4 $field;');
  }
  buffer.writeln('};');
  buffer.writeln();

  final List<String> params = [];
  params.add('$inputStructName IN [[stage_in]]');
  if (data.uniforms.isNotEmpty) {
    params.add('constant ${data.uniformStruct}& uniforms [[buffer(0)]]');
  }
  for (final TextureBinding texture in data.textures) {
    params.add('${translateTextureType(texture.type)} ${texture.name} [[texture(${texture.slot})]]');
    params.add('sampler ${texture.name}Sampler [[sampler(${texture.slot})]]');
  }

  buffer.writeln('fragment float4 ${data.fragmentName}(${params.join(', ')})');
  buffer.writeln('{');
  buffer.writeln('  $outputStructName OUT = $outputStructName();');

  final ExpressionTranslator translator = ExpressionTranslator(data, analyzer);
  for (final String line in translator.prologue) {
    buffer.writeln('  $line');
  }
  for (final String line in translator.body) {
    buffer.writeln('  $line');
  }

  buffer.writeln('  return ${translator.returnExpression};');
  buffer.writeln('}');
  return buffer.toString();
}

class ExpressionTranslator {
  ExpressionTranslator(this.data, this.analyzer) {
    _build();
  }

  final ShaderIrData data;
  final _InOutAnalyzer analyzer;
  final List<String> prologue = <String>[];
  final List<String> body = <String>[];
  late final String returnExpression;

  void _build() {
    for (final String field in analyzer.outputFields) {
      prologue.add('OUT.$field = float4(0.0);');
    }
    for (final Map<String, dynamic> expr in data.coreExpressions) {
      final String? raw = expr['raw'] as String?;
      if (raw == null) {
        continue;
      }
      final String trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed.startsWith('//')) {
        continue;
      }
      final String converted = _rewriteLine(trimmed);
      if (converted.isEmpty) {
        continue;
      }
      body.add(converted);
    }
    returnExpression = analyzer.outputFields.contains('Color') ? 'OUT.Color' : 'float4(0.0)';
  }

  String _rewriteLine(String line) {
    String result = line;
    result = _rewriteTextureFunctions(result);
    result = _rewriteSaturate(result);
    return result;
  }

  String _rewriteTextureFunctions(String line) {
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < line.length) {
      final String? functionName = _detectTextureFunction(line, index);
      if (functionName != null) {
        final _FunctionCall? call = _parseFunctionCall(line, index);
        if (call == null) {
          buffer.write(line[index]);
          index++;
          continue;
        }
        final String original = line.substring(index, call.endIndex);
        final String replacement = _translateTextureCall(original, call);
        buffer.write(replacement);
        index = call.endIndex;
        continue;
      }
      buffer.write(line[index]);
      index++;
    }
    return buffer.toString();
  }

  String _rewriteSaturate(String line) {
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < line.length) {
      if (_matchesFunction(line, index, 'saturate')) {
        final _FunctionCall? call = _parseFunctionCall(line, index);
        if (call == null || call.args.isEmpty) {
          buffer.write(line[index]);
          index++;
          continue;
        }
        final String argument = call.args.first.trim();
        buffer.write('clamp($argument, 0.0, 1.0)');
        index = call.endIndex;
        continue;
      }
      buffer.write(line[index]);
      index++;
    }
    return buffer.toString();
  }

  String? _detectTextureFunction(String source, int index) {
    const List<String> candidates = <String>[
      'tex2Dproj',
      'tex2D',
      'texRECT',
      'tex3D',
      'texCUBE',
    ];
    for (final String candidate in candidates) {
      if (_matchesFunction(source, index, candidate)) {
        return candidate;
      }
    }
    return null;
  }

  bool _matchesFunction(String source, int index, String name) {
    if (!source.startsWith(name, index)) {
      return false;
    }
    if (index > 0) {
      final String previous = source[index - 1];
      if (_isIdentifierChar(previous)) {
        return false;
      }
    }
    final int end = index + name.length;
    if (end < source.length) {
      final String next = source[end];
      if (_isIdentifierChar(next)) {
        return false;
      }
    }
    return true;
  }

  _FunctionCall? _parseFunctionCall(String source, int start) {
    int nameEnd = start;
    while (nameEnd < source.length && _isIdentifierChar(source[nameEnd])) {
      nameEnd++;
    }
    final String name = source.substring(start, nameEnd);
    int index = nameEnd;
    while (index < source.length && source[index].trim().isEmpty) {
      index++;
    }
    if (index >= source.length || source[index] != '(') {
      return null;
    }
    index++;
    final List<String> args = <String>[];
    final StringBuffer current = StringBuffer();
    int depth = 0;
    while (index < source.length) {
      final String char = source[index];
      if (char == '(') {
        depth++;
        current.write(char);
        index++;
        continue;
      }
      if (char == ')') {
        if (depth == 0) {
          final String captured = current.toString().trim();
          if (captured.isNotEmpty) {
            args.add(captured);
          }
          index++;
          break;
        } else {
          depth--;
          current.write(char);
          index++;
          continue;
        }
      }
      if (char == ',' && depth == 0) {
        final String captured = current.toString().trim();
        if (captured.isNotEmpty) {
          args.add(captured);
        }
        current.clear();
        index++;
        continue;
      }
      if (char == '"' || char == "'") {
        final int endOfString = _skipString(source, index, char);
        current.write(source.substring(index, endOfString));
        index = endOfString;
        continue;
      }
      current.write(char);
      index++;
    }
    return _FunctionCall(name, args, index);
  }

  String _translateTextureCall(String original, _FunctionCall call) {
    if (call.args.length < 2) {
      return original;
    }
    final String texture = call.args[0].trim();
    final String coordinate = call.args[1].trim();
    final String sampler = '${texture}Sampler';
    switch (call.name) {
      case 'tex2D':
      case 'texRECT':
      case 'tex3D':
      case 'texCUBE':
        return '$texture.sample($sampler, $coordinate)';
      case 'tex2Dproj':
        final String projected = '(${coordinate}).xy / (${coordinate}).w';
        return '$texture.sample($sampler, $projected)';
      default:
        return original;
    }
  }

  bool _isIdentifierChar(String char) {
    if (char.isEmpty) {
      return false;
    }
    final int code = char.codeUnitAt(0);
    final bool isLetter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    final bool isDigit = code >= 48 && code <= 57;
    return isLetter || isDigit || char == '_';
  }

  int _skipString(String source, int index, String delimiter) {
    int current = index + 1;
    while (current < source.length) {
      final String char = source[current];
      if (char == '\\' && current + 1 < source.length) {
        current += 2;
        continue;
      }
      if (char == delimiter) {
        return current + 1;
      }
      current++;
    }
    return source.length;
  }
}

class _FunctionCall {
  _FunctionCall(this.name, this.args, this.endIndex);

  final String name;
  final List<String> args;
  final int endIndex;
}

class _InOutAnalyzer {
  _InOutAnalyzer(List<Map<String, dynamic>> expressions, [List<Map<String, dynamic>> flow = const []])
      : _expressions = expressions,
        _flow = flow {
    _scan();
  }

  final List<Map<String, dynamic>> _expressions;
  final List<Map<String, dynamic>> _flow;
  final Set<String> _inputFields = <String>{};
  final Set<String> _outputFields = <String>{};

  List<String> get inputFields {
    final List<String> fields = _inputFields.toList();
    fields.sort();
    return fields;
  }

  List<String> get outputFields {
    final Set<String> fields = Set<String>.from(_outputFields);
    fields.add('Color');
    final List<String> sorted = fields.toList();
    sorted.sort();
    return sorted;
  }

  void _scan() {
    for (final Map<String, dynamic> expr in _expressions) {
      _collect(expr['lhs']);
      _collect(expr['rhs']);
      _collect(expr['raw']);
    }
    for (final Map<String, dynamic> entry in _flow) {
      _collect(entry['content']);
    }
  }

  void _collect(dynamic value) {
    if (value is! String) {
      return;
    }
    final String content = value;
    for (final RegExpMatch match in _inPattern.allMatches(content)) {
      final String? token = match.group(1);
      if (token != null && token.isNotEmpty) {
        _inputFields.add(token);
      }
    }
    for (final RegExpMatch match in _outPattern.allMatches(content)) {
      final String? token = match.group(1);
      if (token != null && token.isNotEmpty) {
        _outputFields.add(token);
      }
    }
  }

  static final RegExp _inPattern = RegExp(r'IN\.([A-Za-z0-9_]+)');
  static final RegExp _outPattern = RegExp(r'OUT\.([A-Za-z0-9_]+)');
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
    case 'float2x2':
      return 'float2x2';
    case 'float3x3':
      return 'float3x3';
    case 'float4x4':
      return 'float4x4';
    case 'float2x3':
      return 'float2x3';
    case 'float3x2':
      return 'float3x2';
    case 'float2x4':
      return 'float2x4';
    case 'float4x2':
      return 'float4x2';
    case 'float3x4':
      return 'float3x4';
    case 'float4x3':
      return 'float4x3';
    case 'int':
      return 'int';
    case 'int2':
      return 'int2';
    case 'int3':
      return 'int3';
    case 'int4':
      return 'int4';
    case 'bool':
      return 'bool';
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

List<Map<String, dynamic>> _castMapList(List<dynamic>? source) {
  if (source == null) {
    return const [];
  }
  final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
  for (final dynamic entry in source) {
    if (entry is Map<String, dynamic>) {
      result.add(Map<String, dynamic>.from(entry));
    }
  }
  return result;
}

List<String> _castStringList(List<dynamic>? source) {
  if (source == null) {
    return const [];
  }
  final List<String> result = <String>[];
  for (final dynamic entry in source) {
    if (entry is String) {
      result.add(entry);
    }
  }
  return result;
}

Map<String, dynamic> derivePipelineMetadata(String shaderName, List<dynamic> directivesRaw) {
  final String lowerName = shaderName.toLowerCase();
  final Set<String> directives = directivesRaw
      .whereType<String>()
      .map((d) => d.toLowerCase())
      .toSet();

  bool blendEnabled = true;
  String blendMode = 'alpha';
  bool depthWrite = false;
  bool depthTest = true;
  String depthCompare = 'lessEqual';
  String cullMode = directives.contains('twosided') ? 'none' : 'back';

  if (lowerName.contains('shadow') ||
      lowerName.contains('depth') ||
      lowerName.contains('zpass') ||
      lowerName.contains('zonly')) {
    blendEnabled = false;
    depthWrite = true;
    depthTest = true;
    depthCompare = 'lessEqual';
  }

  if (lowerName.contains('opaque') ||
      lowerName.contains('solid') ||
      lowerName.contains('terrain')) {
    blendEnabled = false;
    depthWrite = true;
  }

  if (lowerName.contains('add') ||
      lowerName.contains('glow') ||
      lowerName.contains('flare') ||
      lowerName.contains('lightadd')) {
    blendMode = 'add';
    blendEnabled = true;
    depthWrite = false;
  }

  if (lowerName.contains('alpha') ||
      lowerName.contains('trans') ||
      lowerName.contains('hud') ||
      lowerName.contains('particle')) {
    blendMode = 'alpha';
    blendEnabled = true;
    depthWrite = false;
  }

  if (lowerName.contains('sky') ||
      lowerName.contains('post') ||
      lowerName.contains('screen')) {
    blendMode = 'alpha';
    blendEnabled = true;
    depthWrite = false;
    depthTest = true;
  }

  if (directives.contains('projected')) {
    depthWrite = false;
    depthTest = true;
  }

  if (directives.contains('twosided') || lowerName.contains('twoside')) {
    cullMode = 'none';
  }

  if (!blendEnabled) {
    blendMode = 'none';
  }

  return {
    'blendEnabled': blendEnabled,
    'blendMode': blendMode,
    'depthWrite': depthWrite,
    'depthTest': depthTest,
    'depthCompare': depthCompare,
    'cullMode': cullMode,
  };
}
