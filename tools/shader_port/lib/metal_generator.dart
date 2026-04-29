library metal_generator;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'reflection_adapter.dart';

part 'shader_ir_models.dart';
part 'shader_ir_parser.dart';
part 'expression_translator.dart';
part 'emission_strategies.dart';
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
    final bool isVertexStage = data.stage == 'vertex';
    final List<Map<String, dynamic>> manifestVertexMetadata = isVertexStage
        ? orderVertexAttributes(data.vertexAttributeMetadata)
        : data.vertexAttributeMetadata;
    final String entryPointName = isVertexStage
        ? 'generated_${data.normalizedName}_vertex'
        : data.fragmentName;
    final List<Map<String, dynamic>> vertexInputs = isVertexStage
        ? _summarizeVertexInputs(manifestVertexMetadata)
        : const [];
    final List<Map<String, dynamic>> vertexOutputs =
        isVertexStage ? summarizeVertexOutputs(data) : const [];
    manifestEntries.add({
      'source': relative,
      'metal': metalFileName,
      'shader': data.shaderName,
      'normalized': data.normalizedName,
      'fragment': entryPointName,
      'entryPoint': entryPointName,
      'stage': data.stage,
      'uniformStruct': data.uniformStruct,
      'uniformCount': data.uniforms.length,
      'textureCount': data.textures.length,
      'vertexAttributes': data.vertexAttributes,
      'vertexAttributeMetadata': manifestVertexMetadata,
      if (vertexInputs.isNotEmpty) 'vertexInputs': vertexInputs,
      if (vertexOutputs.isNotEmpty) 'vertexOutputs': vertexOutputs,
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
  return MetalFragmentBuilder(
    data,
    isVertexStage: data.stage == 'vertex',
  ).build();
}

const int _kMetalVertexStreamGeneral = 0;
const int _kMetalVertexStreamTangents = 1;

List<Map<String, dynamic>> orderVertexAttributes(
  List<Map<String, dynamic>> metadata,
) {
  if (metadata.isEmpty) {
    return const [];
  }
  final List<Map<String, dynamic>> positions = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> normals = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> colors = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> texCoords = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> others = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> tangents = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> binormals = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> tNormals = <Map<String, dynamic>>[];
  for (final Map<String, dynamic> original in metadata) {
    final Map<String, dynamic> entry = Map<String, dynamic>.from(original);
    final String category =
        (entry['category'] as String? ?? '').toLowerCase();
    final String token = (entry['token'] as String? ?? '').toLowerCase();
    if (category == 'position') {
      positions.add(entry);
      continue;
    }
    if (category == 'normal') {
      if (token.contains('tnormal')) {
        tNormals.add(entry);
      } else {
        normals.add(entry);
      }
      continue;
    }
    if (category == 'tangent') {
      tangents.add(entry);
      continue;
    }
    if (category == 'binormal') {
      binormals.add(entry);
      continue;
    }
    if (category == 'color') {
      colors.add(entry);
      continue;
    }
    if (category == 'texcoord') {
      texCoords.add(entry);
      continue;
    }
    if (token.contains('tangent') ||
        token.contains('binormal') ||
        token.contains('tnormal')) {
      tNormals.add(entry);
      continue;
    }
    others.add(entry);
  }
  final bool requiresTangentFrame =
      tangents.isNotEmpty || binormals.isNotEmpty || tNormals.isNotEmpty;
  if (requiresTangentFrame) {
    if (normals.isEmpty) {
      normals.add(<String, dynamic>{
        'token': 'Normal',
        'category': 'normal',
        'semantic': 'NORMAL',
        'components': 3,
        'source': 'synthetic',
      });
    }
    if (colors.isEmpty) {
      colors.add(<String, dynamic>{
        'token': 'Color',
        'category': 'color',
        'semantic': 'COLOR',
        'components': 4,
        'index': 0,
        'source': 'synthetic',
      });
    }
    if (texCoords.isEmpty) {
      texCoords.add(<String, dynamic>{
        'token': 'TexCoord0',
        'category': 'texcoord',
        'semantic': 'TEXCOORD0',
        'components': 2,
        'index': 0,
        'source': 'synthetic',
      });
    }
  }
  colors.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final int aIndex = a['index'] is int ? a['index'] as int : 0;
    final int bIndex = b['index'] is int ? b['index'] as int : 0;
    return aIndex.compareTo(bIndex);
  });
  texCoords.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final int aIndex = a['index'] is int ? a['index'] as int : 0;
    final int bIndex = b['index'] is int ? b['index'] as int : 0;
    return aIndex.compareTo(bIndex);
  });
  others.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final String tokenA = (a['token'] as String? ?? '');
    final String tokenB = (b['token'] as String? ?? '');
    return tokenA.compareTo(tokenB);
  });
  final List<Map<String, dynamic>> primaryOrder = <Map<String, dynamic>>[
    ...positions,
    ...normals,
    ...colors,
    ...texCoords,
    ...others,
  ];
  final List<Map<String, dynamic>> tangentOrder = <Map<String, dynamic>>[
    ...tangents,
    ...binormals,
    ...tNormals,
  ];
  final List<Map<String, dynamic>> ordered = <Map<String, dynamic>>[];
  int slot = 0;
  for (final Map<String, dynamic> entry in primaryOrder) {
    entry['slot'] = slot;
    entry['bufferIndex'] = _kMetalVertexStreamGeneral;
    ordered.add(entry);
    slot++;
  }
  for (final Map<String, dynamic> entry in tangentOrder) {
    entry['slot'] = slot;
    entry['bufferIndex'] = _kMetalVertexStreamTangents;
    ordered.add(entry);
    slot++;
  }
  if (ordered.isEmpty) {
    return metadata;
  }
  ordered.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final int slotA = a['slot'] is int ? a['slot'] as int : 0;
    final int slotB = b['slot'] is int ? b['slot'] as int : 0;
    return slotA.compareTo(slotB);
  });
  return ordered;
}

List<Map<String, dynamic>> _summarizeVertexInputs(
  List<Map<String, dynamic>> metadata,
) {
  final List<Map<String, dynamic>> ordered = orderVertexAttributes(metadata);
  if (ordered.isEmpty) {
    return const [];
  }
  final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
  for (final Map<String, dynamic> entry in ordered) {
    final int slot = entry['slot'] is int ? entry['slot'] as int : result.length;
    result.add({
      'name': entry['token'] ?? 'attr$slot',
      'index': slot,
      'slot': slot,
      'bufferIndex': entry['bufferIndex'] is int
          ? entry['bufferIndex'] as int
          : _kMetalVertexStreamGeneral,
      if (entry.containsKey('category')) 'category': entry['category'],
      if (entry.containsKey('semantic')) 'semantic': entry['semantic'],
      if (entry.containsKey('components')) 'components': entry['components'],
      if (entry.containsKey('label')) 'label': entry['label'],
    });
  }
  return result;
}

List<Map<String, dynamic>> summarizeVertexOutputs(ShaderIrData data) {
  if (data.stage != 'vertex') {
    return const [];
  }
  final _InOutAnalyzer analyzer = _InOutAnalyzer(
    data.coreExpressions,
    data.coreFlow,
  );
  final Map<String, int> resolved =
      _resolveOutputComponentCounts(data, analyzer);
  if (resolved.isEmpty) {
    return const [];
  }
  final List<Map<String, dynamic>> outputs = resolved.entries
      .where((MapEntry<String, int> entry) => entry.key != 'HPosition')
      .map(
        (MapEntry<String, int> entry) => <String, dynamic>{
          'name': entry.key,
          'components': entry.value,
        },
      )
      .toList()
    ..sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['name'] as String).compareTo(b['name'] as String),
    );
  return outputs;
}

int _componentCountFromType(String type) {
  final String lower = type.toLowerCase();
  if (lower.contains('float4')) {
    return 4;
  }
  if (lower.contains('float3')) {
    return 3;
  }
  if (lower.contains('float2')) {
    return 2;
  }
  return 1;
}

final RegExp _kTexVaryingPattern = RegExp(r'^tex\d+$', caseSensitive: false);

bool _isTexVaryingField(String field) => _kTexVaryingPattern.hasMatch(field);

bool _isColorField(String field) => field.toLowerCase().startsWith('color');

bool _isProjectiveTcField(String field) {
  final String lower = field.toLowerCase();
  if (lower.startsWith('texcoord')) {
    return false;
  }
  return lower.contains('tc');
}

Map<String, int> _resolveOutputComponentCounts(
  ShaderIrData data,
  _InOutAnalyzer analyzer,
) {
  final Map<String, int> declaredComponents = <String, int>{
    for (final MapEntry<String, String> entry in data.outputFieldTypes.entries)
      entry.key: _componentCountFromType(entry.value),
  };
  final Map<String, int> resolved = <String, int>{};
  final Map<String, int> attributeComponents = <String, int>{};

  for (final Map<String, dynamic> entry in data.vertexAttributeMetadata) {
    final String? token = (entry['token'] as String?)?.toLowerCase();
    final int? components = entry['components'] as int?;
    if (token == null || components == null) {
      continue;
    }
    if (token.startsWith('texcoord')) {
      final RegExpMatch? match = RegExp(r'^texcoord(\d+)$').firstMatch(token);
      if (match != null) {
        final String texName = 'Tex${match.group(1)}';
        attributeComponents[texName] =
            math.max(1, math.min(components, 4));
      }
    } else if (token == 'color') {
      attributeComponents['Color'] = 4;
    } else if (token.startsWith('color')) {
      final String suffix = token.substring('color'.length);
      if (suffix.isNotEmpty) {
        final String name =
            'Color${suffix[0].toUpperCase()}${suffix.substring(1)}';
        attributeComponents[name] = math.max(1, math.min(components, 4));
      }
    }
  }

  int _applyOutputComponentRules(
    String field,
    int components, {
    required bool enforceMinimum,
  }) {
    final int? attributeHint = attributeComponents[field];
    if (attributeHint != null) {
      components = math.max(components, attributeHint);
    }
    if (_isColorField(field) || field == 'HPosition') {
      return 4;
    }
    if (_isProjectiveTcField(field)) {
      components = math.max(components, 4);
    }
    if (components < 1) {
      components = 1;
    } else if (components > 4) {
      components = 4;
    }
    if (enforceMinimum && components < 2) {
      components = 2;
    }
    return components;
  }

  for (final String field in analyzer.outputFields) {
    final int? usage = analyzer.outputComponentUsage[field];
    int components = usage ?? 0;
    if (components == 0 && declaredComponents.containsKey(field)) {
      components = declaredComponents[field]!;
    } else if (components == 0) {
      components = 4;
    }
    resolved[field] = _applyOutputComponentRules(
      field,
      components,
      enforceMinimum: true,
    );
  }

  declaredComponents.forEach((String field, int components) {
    if (resolved.containsKey(field)) {
      return;
    }
    resolved[field] = _applyOutputComponentRules(
      field,
      components,
      enforceMinimum: false,
    );
  });

  if (resolved.containsKey('HPosition')) {
    resolved['HPosition'] = 4;
  }

  return resolved;
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
