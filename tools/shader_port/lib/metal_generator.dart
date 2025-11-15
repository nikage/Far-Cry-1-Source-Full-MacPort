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

class ShaderIrParseResult {
  ShaderIrParseResult({
    required this.data,
    required this.directives,
    required this.vertexAttributes,
  });

  final ShaderIrData data;
  final List<dynamic> directives;
  final List<dynamic> vertexAttributes;
}

class ShaderIrParser {
  ShaderIrParseResult parse(Map<String, dynamic> ir, String relative) {
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
    final List<dynamic> directives = ir['directives'] as List<dynamic>? ?? [];
    final String shaderName = (ir['name'] as String? ?? '').isEmpty ? relative : ir['name'] as String;
    final String normalized = normalizeName(shaderName);
    final ShaderIrData data = ShaderIrData(
      shaderName: shaderName,
      normalizedName: normalized,
      fragmentName: 'generated_${normalized}_fragment',
      uniformStruct: '${normalized}_uniforms',
      uniforms: uniforms,
      textures: textures,
      coreExpressions: _castMapList(ir['coreScriptExpressions'] as List<dynamic>?),
      coreFlow: _castMapList(ir['coreScriptFlow'] as List<dynamic>?),
      passStates: _castMapList(ir['passStates'] as List<dynamic>?),
      maskReferences: _castStringList(ir['maskReferences'] as List<dynamic>?),
    );
    final List<dynamic> vertexAttributes = ir['vertexAttributes'] as List<dynamic>? ?? [];
    return ShaderIrParseResult(
      data: data,
      directives: directives,
      vertexAttributes: vertexAttributes,
    );
  }
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
  final ShaderIrParser parser = ShaderIrParser();
  for (final FileSystemEntity entity in irDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.json')) continue;
    final dynamic parsed = jsonDecode(entity.readAsStringSync(encoding: utf8));
    if (parsed is! Map<String, dynamic>) continue;
    final Map<String, dynamic> ir = parsed;
    final String extension = (ir['extension'] as String? ?? '').toLowerCase();
    if (extension != 'cryps' && extension != 'crycg') continue;
    final String relative = entity.path.substring(irDir.path.length + 1).replaceAll(RegExp(r'[\\/]'), '/');
    final ShaderIrParseResult result = parser.parse(ir, relative);
    final ShaderIrData data = result.data;
    final String metalFileName = '${relative.replaceAll('/', '_')}.metal';
    final File targetFile = File(outDir.path + sep + metalFileName);
    targetFile.parent.createSync(recursive: true);
    targetFile.writeAsStringSync(buildMetal(data));
    final Map<String, dynamic> pipeline =
        derivePipelineMetadata(data.shaderName, result.directives, data.passStates);
    manifestEntries.add({
      'source': relative,
      'metal': metalFileName,
      'shader': data.shaderName,
      'normalized': data.normalizedName,
      'fragment': data.fragmentName,
      'uniformStruct': data.uniformStruct,
      'uniformCount': data.uniforms.length,
      'textureCount': data.textures.length,
      'vertexAttributes': result.vertexAttributes,
      'directives': result.directives,
      'maskReferences': data.maskReferences,
      'uniforms': data.uniforms
          .map((u) => {
                'name': u.name,
                'type': u.type,
                'semantic': u.semantic,
              })
          .toList(),
      'textures': data.textures
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

String buildMetal(ShaderIrData data) {
  return MetalFragmentBuilder(data).build();
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

class MetalFragmentBuilder {
  MetalFragmentBuilder(this.data)
      : _analyzer = _InOutAnalyzer(data.coreExpressions, data.coreFlow);

  final ShaderIrData data;
  final _InOutAnalyzer _analyzer;
  late final ExpressionTranslator _translator = ExpressionTranslator(
    data,
    _analyzer,
    <LineTransformer>[
      TextureFunctionTransformer(),
      SaturateTransformer(),
    ],
  );
  late final String _inputStructName = '${data.normalizedName}_input';
  late final String _outputStructName = '${data.normalizedName}_output';

  String build() {
    final StringBuffer buffer = StringBuffer();
    _writePreamble(buffer);
    _writeUniformStruct(buffer);
    _writeInputStruct(buffer);
    _writeOutputStruct(buffer);
    _writeFragmentFunction(buffer);
    return buffer.toString();
  }

  void _writePreamble(StringBuffer buffer) {
    buffer.writeln('#include <metal_stdlib>');
    buffer.writeln('using namespace metal;');
    buffer.writeln();
  }

  void _writeUniformStruct(StringBuffer buffer) {
    if (data.uniforms.isEmpty) {
      return;
    }
    buffer.writeln('struct ${data.uniformStruct} {');
    for (final UniformBinding uniform in data.uniforms) {
      buffer.writeln('  ${translateType(uniform.type)} ${uniform.name};');
    }
    buffer.writeln('};');
    buffer.writeln();
  }

  void _writeInputStruct(StringBuffer buffer) {
    buffer.writeln('struct $_inputStructName {');
    buffer.writeln('  float4 position [[position]];');
    for (final String field in _analyzer.inputFields) {
      buffer.writeln('  float4 $field;');
    }
    buffer.writeln('};');
    buffer.writeln();
  }

  void _writeOutputStruct(StringBuffer buffer) {
    buffer.writeln('struct $_outputStructName {');
    for (final String field in _analyzer.outputFields) {
      buffer.writeln('  float4 $field;');
    }
    buffer.writeln('};');
    buffer.writeln();
  }

  void _writeFragmentFunction(StringBuffer buffer) {
    buffer.writeln('fragment float4 ${data.fragmentName}(${_buildParameters().join(', ')})');
    buffer.writeln('{');
    buffer.writeln('  $_outputStructName OUT = $_outputStructName();');
    for (final String line in _translator.prologue) {
      buffer.writeln('  $line');
    }
    for (final String line in _translator.body) {
      buffer.writeln('  $line');
    }
    buffer.writeln('  return ${_translator.returnExpression};');
    buffer.writeln('}');
  }

  List<String> _buildParameters() {
    final List<String> params = <String>['$_inputStructName IN [[stage_in]]'];
    if (data.uniforms.isNotEmpty) {
      params.add('constant ${data.uniformStruct}& uniforms [[buffer(0)]]');
    }
    for (final TextureBinding texture in data.textures) {
      params.add('${translateTextureType(texture.type)} ${texture.name} [[texture(${texture.slot})]]');
      params.add('sampler ${texture.name}Sampler [[sampler(${texture.slot})]]');
    }
    return params;
  }
}

class ExpressionTranslator {
  ExpressionTranslator(this.data, this.analyzer, List<LineTransformer> transformers)
      : _transformers = transformers {
    _build();
  }

  final ShaderIrData data;
  final _InOutAnalyzer analyzer;
  final List<LineTransformer> _transformers;
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
    for (final LineTransformer transformer in _transformers) {
      result = transformer.transform(result);
    }
    return result;
  }
}

abstract class LineTransformer {
  String transform(String line);
}

class TextureFunctionTransformer implements LineTransformer {
  @override
  String transform(String line) {
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < line.length) {
      final String? functionName = _detectTextureFunction(line, index);
      if (functionName != null) {
        final _FunctionCall? call = _FunctionCallUtils.parse(line, index);
        if (call == null) {
          buffer.write(line[index]);
          index++;
          continue;
        }
        final String original = line.substring(index, call.endIndex);
        buffer.write(_translateTextureCall(original, call));
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
      if (_FunctionCallUtils.matches(source, index, candidate)) {
        return candidate;
      }
    }
    return null;
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
}

class SaturateTransformer implements LineTransformer {
  @override
  String transform(String line) {
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < line.length) {
      if (_FunctionCallUtils.matches(line, index, 'saturate')) {
        final _FunctionCall? call = _FunctionCallUtils.parse(line, index);
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
}

class _FunctionCallUtils {
  static bool matches(String source, int index, String name) {
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

  static _FunctionCall? parse(String source, int start) {
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

  static bool _isIdentifierChar(String char) {
    if (char.isEmpty) {
      return false;
    }
    final int code = char.codeUnitAt(0);
    final bool isLetter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    final bool isDigit = code >= 48 && code <= 57;
    return isLetter || isDigit || char == '_';
  }

  static int _skipString(String source, int index, String delimiter) {
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

Map<String, dynamic> derivePipelineMetadata(
    String shaderName, List<dynamic> directivesRaw, List<Map<String, dynamic>> passStates) {
  final String lowerName = shaderName.toLowerCase();
  final Set<String> directives = directivesRaw
      .whereType<String>()
      .map((d) => d.toLowerCase())
      .toSet();

  final Map<String, dynamic>? summary = _extractPrimaryPassSummary(passStates);

  bool blendEnabled = _summaryBlendEnabled(summary) ?? true;
  String blendMode = _summaryBlendMode(summary) ?? 'alpha';
  bool depthWrite = summary?['depthWrite'] as bool? ?? false;
  bool depthTest = summary?['depthTest'] as bool? ?? true;
  String depthCompare = _mapDepthFunc(summary?['depthFunc'] as String?) ?? 'lessEqual';
  String cullMode =
      _mapCullMode(summary?['cullMode'] as String?) ?? (directives.contains('twosided') ? 'none' : 'back');
  final Map<String, dynamic> blendFactors = _summaryBlendFactors(summary);
  final Map<String, dynamic>? colorMask = _summaryColorMask(summary);

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

  final Map<String, dynamic> result = <String, dynamic>{
    'blendEnabled': blendEnabled,
    'blendMode': blendMode,
    'depthWrite': depthWrite,
    'depthTest': depthTest,
    'depthCompare': depthCompare,
    'cullMode': cullMode,
  };
  if (blendFactors.isNotEmpty) {
    result['blendFactors'] = blendFactors;
  }
  if (colorMask != null && colorMask.isNotEmpty) {
    result['colorMask'] = colorMask;
  }
  if (summary != null) {
    if (summary.containsKey('alphaFunc')) {
      result['alphaFunc'] = (summary['alphaFunc'] as String).toLowerCase();
    }
    if (summary.containsKey('alphaRef')) {
      result['alphaRef'] = summary['alphaRef'];
    }
  }
  return result;
}

Map<String, dynamic>? _extractPrimaryPassSummary(List<Map<String, dynamic>> passStates) {
  for (final Map<String, dynamic> pass in passStates) {
    final dynamic summary = pass['stateSummary'];
    if (summary is Map<String, dynamic> && summary.isNotEmpty) {
      return summary;
    }
  }
  return null;
}

bool? _summaryBlendEnabled(Map<String, dynamic>? summary) {
  final dynamic blend = summary?['blend'];
  if (blend is Map<String, dynamic>) {
    final dynamic enabled = blend['enabled'];
    if (enabled is bool) {
      return enabled;
    }
  }
  return null;
}

String? _summaryBlendMode(Map<String, dynamic>? summary) {
  final dynamic blend = summary?['blend'];
  if (blend is Map<String, dynamic>) {
    final dynamic mode = blend['mode'];
    if (mode is String && mode.isNotEmpty) {
      return mode.toLowerCase();
    }
    final String? src = _asUpper(blend['src']);
    final String? dst = _asUpper(blend['dst']);
    if (src != null && dst != null) {
      if (src == 'ONE' && dst == 'ONE') {
        return 'add';
      }
      if (src == 'SRCALPHA' && (dst == 'INVSRCALPHA' || dst == 'ONE_MINUS_SRC_ALPHA')) {
        return 'alpha';
      }
      if (src == 'ONE' && dst == 'INVSRCALPHA') {
        return 'premultiplied';
      }
    }
  }
  return null;
}

Map<String, dynamic> _summaryBlendFactors(Map<String, dynamic>? summary) {
  final Map<String, dynamic> factors = <String, dynamic>{};
  final dynamic blend = summary?['blend'];
  if (blend is Map<String, dynamic>) {
    final String? src = _asUpper(blend['src']);
    final String? dst = _asUpper(blend['dst']);
    final String? srcAlpha = _asUpper(blend['srcAlpha']);
    final String? dstAlpha = _asUpper(blend['dstAlpha']);
    final String? op = _asUpper(blend['op']);
    final String? opAlpha = _asUpper(blend['opAlpha']);
    if (src != null) factors['src'] = src;
    if (dst != null) factors['dst'] = dst;
    if (srcAlpha != null) factors['srcAlpha'] = srcAlpha;
    if (dstAlpha != null) factors['dstAlpha'] = dstAlpha;
    if (op != null) factors['op'] = op;
    if (opAlpha != null) factors['opAlpha'] = opAlpha;
  }
  return factors;
}

Map<String, dynamic>? _summaryColorMask(Map<String, dynamic>? summary) {
  Map<String, dynamic>? mask = summary?['colorMask'] as Map<String, dynamic>?;
  if (mask == null || mask.isEmpty) {
    mask = summary?['colourmask'] as Map<String, dynamic>?;
  }
  return mask?.map((String key, dynamic value) => MapEntry<String, dynamic>(key, value));
}

String? _mapDepthFunc(String? func) {
  if (func == null || func.isEmpty) {
    return null;
  }
  final String lower = func.toLowerCase();
  switch (lower) {
    case 'less':
      return 'less';
    case 'lessequal':
    case 'less_equal':
    case 'lequal':
      return 'lessEqual';
    case 'greater':
      return 'greater';
    case 'greaterequal':
    case 'greater_equal':
    case 'gequal':
      return 'greaterEqual';
    case 'equal':
      return 'equal';
    case 'always':
      return 'always';
    case 'never':
      return 'never';
    default:
      return null;
  }
}

String? _mapCullMode(String? mode) {
  if (mode == null || mode.isEmpty) {
    return null;
  }
  final String lower = mode.toLowerCase();
  switch (lower) {
    case 'none':
    case 'disable':
    case 'disabled':
    case 'off':
      return 'none';
    case 'front':
      return 'front';
    case 'back':
      return 'back';
    default:
      return null;
  }
}

String? _asUpper(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return value.toUpperCase();
  }
  return null;
}
