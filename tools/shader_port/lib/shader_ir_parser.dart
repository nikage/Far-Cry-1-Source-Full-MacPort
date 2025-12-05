part of 'metal_generator.dart';

class ShaderIrParser {
  ShaderIrParseResult parse(Map<String, dynamic> ir, String relative) {
    final List<dynamic> blocks = ir['blocks'] as List<dynamic>? ?? [];
    final Map<String, dynamic>? mainInputBlock = blocks
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (block) =>
              block != null &&
              (block['name'] as String?)?.toLowerCase() == 'maininput',
          orElse: () => null,
        );
    final List<UniformBinding> uniforms = [];
    final List<TextureBinding> textures = [];
    final Set<String> uniformNames = <String>{};
    final Set<String> textureNames = <String>{};
    if (mainInputBlock != null) {
      final String content = (mainInputBlock['content'] as String?) ?? '';
      final RegExp pattern = RegExp(
        r'uniform\s+([A-Za-z0-9_]+)\s+([A-Za-z0-9_]+)(?:\s*\[\s*(\d+)\s*\])?(?:\s*:\s*([^,]+))?',
        multiLine: true,
      );
      int slot = 0;
      for (final Match match in pattern.allMatches(content)) {
        final String type = match.group(1) ?? '';
        final String name = match.group(2) ?? '';
        if (type.isEmpty || name.isEmpty) continue;
        final String? arraySizeRaw = match.group(3);
        final int? arraySize = arraySizeRaw == null
            ? null
            : int.tryParse(arraySizeRaw);
        if (type.toLowerCase().startsWith('sampler')) {
          if (textureNames.add(name)) {
            final String semantic = (match.group(4) ?? '').trim();
            textures.add(TextureBinding(type, name, slot, semantic));
            slot++;
          }
        } else {
          if (uniformNames.add(name)) {
            final String semantic = (match.group(4) ?? '').trim();
            uniforms.add(
              UniformBinding(type, name, semantic, arraySize: arraySize),
            );
          }
        }
      }
    }
    if (mainInputBlock != null) {
      final Map<String, UniformBinding> macroUniforms = _extractMacroUniforms(
        mainInputBlock['content'] as String? ?? '',
      );
      for (final UniformBinding binding in macroUniforms.values) {
        if (uniformNames.add(binding.name)) {
          uniforms.add(
            UniformBinding(
              binding.type,
              binding.name,
              binding.semantic,
              arraySize: binding.arraySize,
            ),
          );
        }
      }
    }
    final List<String> positionScripts =
        _castStringList(ir['positionScripts'] as List<dynamic>?);
    final List<Map<String, String>> positionScriptBlocks =
        _castPositionScriptBlocks(
          ir['positionScriptBlocks'] as List<dynamic>?,
        );
    if (!uniformNames.contains('LightPos') &&
        _irReferencesIdentifier(ir, 'LightPos')) {
      uniforms.add(UniformBinding('float4', 'LightPos', ''));
      uniformNames.add('LightPos');
    }
    if (!uniformNames.contains('Layer2TexGen0') &&
        _irReferencesIdentifier(ir, 'Layer2TexGen0')) {
      uniforms.add(UniformBinding('float4', 'Layer2TexGen0', ''));
      uniformNames.add('Layer2TexGen0');
    }
    if (!uniformNames.contains('Layer2TexGen1') &&
        _irReferencesIdentifier(ir, 'Layer2TexGen1')) {
      uniforms.add(UniformBinding('float4', 'Layer2TexGen1', ''));
      uniformNames.add('Layer2TexGen1');
    }
    if (!uniformNames.contains('AlphaGlowTexGen0') &&
        _irReferencesIdentifier(ir, 'AlphaGlowTexGen0')) {
      uniforms.add(UniformBinding('float4', 'AlphaGlowTexGen0', ''));
      uniformNames.add('AlphaGlowTexGen0');
    }
    if (!uniformNames.contains('AlphaGlowTexGen1') &&
        _irReferencesIdentifier(ir, 'AlphaGlowTexGen1')) {
      uniforms.add(UniformBinding('float4', 'AlphaGlowTexGen1', ''));
      uniformNames.add('AlphaGlowTexGen1');
    }
    if (!uniformNames.contains('Fog') &&
        _irReferencesIdentifier(ir, 'Fog')) {
      uniforms.add(UniformBinding('float4', 'Fog', ''));
      uniformNames.add('Fog');
    }
    if (!uniformNames.contains('g_VSCONST_0_025_05_1') &&
        _irReferencesIdentifier(ir, 'g_VSCONST_0_025_05_1')) {
      uniforms.add(
        UniformBinding('float4', 'g_VSCONST_0_025_05_1', ''),
      );
      uniformNames.add('g_VSCONST_0_025_05_1');
    }
    if (!uniformNames.contains('GlobalFogColor') &&
        _irReferencesIdentifier(ir, 'GlobalFogColor')) {
      uniforms.add(UniformBinding('float4', 'GlobalFogColor', ''));
      uniformNames.add('GlobalFogColor');
    }
    if (positionScripts.contains('PosBeam') &&
        !uniformNames.contains('GeomConstants')) {
      uniforms.add(UniformBinding('float4', 'GeomConstants', ''));
      uniformNames.add('GeomConstants');
    }
    final List<dynamic> directives = ir['directives'] as List<dynamic>? ?? [];
    final String shaderName = (ir['name'] as String? ?? '').isEmpty
        ? relative
        : ir['name'] as String;
    final String normalized = normalizeName(shaderName);
    final List<dynamic> vertexAttributes =
        ir['vertexAttributes'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> vertexAttributeMetadata =
        _castMapList(ir['vertexAttributeMetadata'] as List<dynamic>?);
    final ShaderIrData data = ShaderIrData(
      shaderName: shaderName,
      normalizedName: normalized,
      fragmentName: 'generated_${normalized}_fragment',
      uniformStruct: '${normalized}_uniforms',
      uniforms: uniforms,
      textures: textures,
      coreExpressions: _castMapList(
        ir['coreScriptExpressions'] as List<dynamic>?,
      ),
      coreMacros: _castMacroList(ir['coreMacros'] as List<dynamic>?),
      coreFlow: _castMapList(ir['coreScriptFlow'] as List<dynamic>?),
      passStates: _castMapList(ir['passStates'] as List<dynamic>?),
      positionScripts: positionScripts,
      positionScriptBlocks: positionScriptBlocks,
      outputFieldTypes: _castStringMap(
        ir['outputFieldTypes'] as Map<String, dynamic>?,
      ),
      maskReferences: _castStringList(ir['maskReferences'] as List<dynamic>?),
      stage: _inferStage(relative, shaderName),
      vertexAttributes: vertexAttributes,
      vertexAttributeMetadata: vertexAttributeMetadata,
    );
    return ShaderIrParseResult(
      data: data,
      directives: directives,
      vertexAttributes: vertexAttributes,
      vertexAttributeMetadata: vertexAttributeMetadata,
    );
  }

  Map<String, UniformBinding> _extractMacroUniforms(String content) {
    final Map<String, UniformBinding> result = <String, UniformBinding>{};
    for (final MapEntry<String, UniformBinding> entry
        in _macroUniformMap.entries) {
      if (content.contains(entry.key)) {
        result.putIfAbsent(entry.value.name, () => entry.value);
      }
    }
    return result;
  }

  static final Map<String, UniformBinding> _macroUniformMap =
      <String, UniformBinding>{
        'VIEWPROJ_MATRIX': UniformBinding('float4x4', 'ModelViewProj', ''),
        'PROJ_MATRIX': UniformBinding('float4x4', 'ProjMatrix', ''),
        'LIGHT_POS': UniformBinding('float4', 'LightPos', ''),
        'CAMERA_POS': UniformBinding('float4', 'CameraPos', ''),
        'ATTEN': UniformBinding('float4', 'AttenInfo', ''),
        'BEND': UniformBinding('float4', 'Bend', ''),
        'TEX_MATRIX2x4': UniformBinding('float2x4', 'TexMatrix', ''),
        'LIGHT_MATRIX': UniformBinding('float4x4', 'LightMatrix', ''),
        'CLIPPLANE': UniformBinding('float4', 'ClipPlane', ''),
      };

  bool _irReferencesIdentifier(Map<String, dynamic> ir, String identifier) {
    final RegExp pattern = RegExp(r'\b' + RegExp.escape(identifier) + r'\b');
    final List<dynamic>? expressions =
        ir['coreScriptExpressions'] as List<dynamic>?;
    if (expressions != null) {
      for (final dynamic entry in expressions) {
        if (entry is Map<String, dynamic>) {
          final String? raw = entry['raw'] as String?;
          if (raw != null && pattern.hasMatch(raw)) {
            return true;
          }
        }
      }
    }
    final List<dynamic>? blocks = ir['blocks'] as List<dynamic>?;
    if (blocks != null) {
      for (final dynamic block in blocks) {
        if (block is Map<String, dynamic>) {
          final String? content = block['content'] as String?;
          if (content != null && pattern.hasMatch(content)) {
            return true;
          }
        }
      }
    }
    return false;
  }
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

List<MacroDefinition> _castMacroList(List<dynamic>? source) {
  if (source == null) {
    return const [];
  }
  final List<MacroDefinition> result = <MacroDefinition>[];
  for (final dynamic entry in source) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    final String? name = entry['name'] as String?;
    if (name == null || name.isEmpty) {
      continue;
    }
    final String value = (entry['value'] as String?) ?? '';
    final List<Map<String, dynamic>> guards =
        _castGuardList(entry['guards'] as List<dynamic>?);
    final bool? active =
        entry['active'] is bool ? entry['active'] as bool : null;
    final String raw = (entry['raw'] as String?) ?? '';
    result.add(
      MacroDefinition(
        name: name,
        value: value,
        guards: guards,
        active: active,
        raw: raw,
      ),
    );
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

List<Map<String, dynamic>> _castGuardList(List<dynamic>? source) {
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

Map<String, String> _castStringMap(Map<String, dynamic>? source) {
  if (source == null) {
    return const {};
  }
  final Map<String, String> result = <String, String>{};
  source.forEach((Object? key, Object? value) {
    if (key is String && value is String) {
      result[key] = value;
    }
  });
  return result;
}

List<Map<String, String>> _castPositionScriptBlocks(List<dynamic>? source) {
  if (source == null) {
    return const [];
  }
  final List<Map<String, String>> result = <Map<String, String>>[];
  for (final dynamic entry in source) {
    if (entry is Map) {
      final Object? name = entry['name'];
      final Object? content = entry['content'];
      result.add({
        'name': name is String ? name : '',
        'content': content is String ? content : '',
      });
    }
  }
  return result;
}

String _inferStage(String relativePath, String shaderName) {
  final String relLower = relativePath.toLowerCase();
  final String nameLower = shaderName.toLowerCase();
  if (relLower.contains('/cgvshaders/') || nameLower.startsWith('cgv')) {
    return 'vertex';
  }
  return 'fragment';
}

