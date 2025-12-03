library metal_generator;

import 'dart:convert';
import 'dart:io';

part 'shader_ir_models.dart';
part 'shader_ir_parser.dart';
part 'expression_translator.dart';
part 'metal_fragment_builder.dart';
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
    final String relative =
        entity.path.substring(irDir.path.length + 1).replaceAll(RegExp(r'[\\/]'), '/');
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
      'vertexAttributeMetadata': result.vertexAttributeMetadata,
      'directives': result.directives,
      'maskReferences': data.maskReferences,
      'uniforms': data.uniforms
          .map((u) => {
                'name': u.name,
                'type': u.type,
                'semantic': u.semantic,
                if (u.arraySize != null) 'arraySize': u.arraySize,
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

Map<String, dynamic> derivePipelineMetadata(
  String shaderName,
  List<dynamic> directivesRaw,
  List<Map<String, dynamic>> passStates,
) {
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
  String depthCompare =
      _mapDepthFunc(summary?['depthFunc'] as String?) ?? 'lessEqual';
  String cullMode =
      _mapCullMode(summary?['cullMode'] as String?) ??
      (directives.contains('twosided') ? 'none' : 'back');
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

Map<String, dynamic>? _extractPrimaryPassSummary(
  List<Map<String, dynamic>> passStates,
) {
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
      if (src == 'SRCALPHA' &&
          (dst == 'INVSRCALPHA' || dst == 'ONE_MINUS_SRC_ALPHA')) {
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
  return mask?.map(
    (String key, dynamic value) => MapEntry<String, dynamic>(key, value),
  );
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
