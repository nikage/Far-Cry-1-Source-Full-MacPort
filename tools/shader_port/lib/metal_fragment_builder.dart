part of 'metal_generator.dart';

class MetalFragmentBuilder {
  MetalFragmentBuilder(
    this.data, {
    required bool isVertexStage,
    Map<String, int>? pairedVertexOutputs,
    Map<String, int>? vsOutputRequirements,
  }) : _isVertexStage = isVertexStage,
       _pairedVertexOutputs = pairedVertexOutputs,
       _vsOutputRequirements = vsOutputRequirements,
       _stageStrategy =
           isVertexStage ? const VertexEmissionStrategy() : const FragmentEmissionStrategy(),
       _vertexAttributeMetadata = data.vertexAttributeMetadata,
       _orderedVertexAttributes = orderVertexAttributes(data.vertexAttributeMetadata),
       _analyzer = _InOutAnalyzer(data.coreExpressions, data.coreFlow),
       _positionScripts = data.positionScripts
           .map((String script) => script.toLowerCase())
           .toSet(),
       _positionScriptBlocks = data.positionScriptBlocks {
    _resolvedOutputComponents =
        _resolveOutputComponentCounts(data, _analyzer);
    if (isVertexStage && vsOutputRequirements != null) {
      vsOutputRequirements.forEach((String field, int req) {
        _resolvedOutputComponents[field] =
            math.max(_resolvedOutputComponents[field] ?? 0, req);
      });
    }
    for (final String field in _analyzer.inputFields) {
      final String? override = _inputFieldTypeOverrides[field];
      final int components = _attributeComponentCount(field);
      if (override == 'float' || components == 1) {
        _scalarInputFields.add(field);
      }
    }
  }

  final ShaderIrData data;
  final bool _isVertexStage;
  final Map<String, int>? _pairedVertexOutputs;
  final Map<String, int>? _vsOutputRequirements;
  final StageEmissionStrategy _stageStrategy;
  final _InOutAnalyzer _analyzer;
  final Set<String> _positionScripts;
  final List<Map<String, String>> _positionScriptBlocks;
  final List<Map<String, dynamic>> _vertexAttributeMetadata;
  final List<Map<String, dynamic>> _orderedVertexAttributes;
  late final Map<String, int> _resolvedOutputComponents;
  final Set<String> _scalarInputFields = <String>{};
  bool _declaredDefaultVNormal = false;
  bool _wroteHPosition = false;
  late final Map<String, String> _uniformTypes = {
    for (final UniformBinding uniform in data.uniforms)
      uniform.name: uniform.type,
  };
  final Map<String, String> _syntheticUniforms = <String, String>{};
  late final ExpressionTranslator _translator = ExpressionTranslator(
    data,
    _analyzer,
    _scalarInputFields,
    <LineTransformer>[
      ComputeLightVectorsTransformer(),
      FloatMacroTransformer(),
      ZeroCastTransformer(),
      HalfTypeTransformer(),
      HdrEncodeAmbTransformer(),
      HdrEncodeTransformer(),
      HdrFogBlendTransformer(),
      ExpandFunctionTransformer(),
      Tex2DProjTransformer(),
      Tex2DFloat2Transformer(),
      TexCubeFloat3Transformer(),
      NormalizePromotionTransformer(),
      UniformVectorComponentTransformer(_uniformTypes),
      UniformFloat4RestoreTransformer(),
      DotUniformDimensionTransformer(_uniformTypes),
      DotVariableDimensionTransformer(),
      MatrixRowVectorTransformer(),
      CameraVectorTransformer(),
      OffsetTextureTransformer(),
      CubeReflectTransformer(),
      TextureFunctionTransformer(),
      ScalarSampleTransformer(),
      VectorSampleTransformer(),
      Float3DecalColorTransformer(),
      GetNormalMapTransformer(),
      ImplicitSampleDeclarationTransformer(),
      ScalarSwizzleCleanupTransformer(_scalarInputFields),
      Float4ProductReducerTransformer(),
      VFinalColorDeclarationTransformer(),
      VFinalColorFinalAssignmentTransformer(),
      VFinalColorAssignmentTransformer(),
      FinalColorAssignmentTransformer(),
      SaturateTransformer(),
      ClampTransformer(),
      MinMaxTransformer(),
      MatrixCastTransformer(),
      MulFunctionTransformer(),
      LerpTransformer(),
      MatrixRowAccessorTransformer(),
      UniformReferenceTransformer(
        {
          ...data.uniforms.map((UniformBinding u) => u.name),
          ..._macroUniformTypes.keys,
        },
      ),
      DotUniformSuffixFixupTransformer(),
      ColorComponentAssignmentTransformer(_uniformTypes),
      TangentSpaceAssignmentTransformer(),
      VectorSuffixCleanupTransformer(),
      ScalarBroadcastTransformer(),
      ImplicitVectorDeclarationTransformer(),
      ColorAliasTransformer(),
      OutColorUniformReducer(_uniformTypes),
      FracFunctionTransformer(),
      LuminosityDifFixupTransformer(),
      BumpPlantsFixupTransformer(),
      DifZeroInitCleanupTransformer(),
      DifRedeclareTransformer(),
      BrushedMetalFixupTransformer(),
      ShadowProjFixupTransformer(),
      HdrOutputTransformer(),
      VectorMultiplyCleanupTransformer(),
      NightVisionVectorCleanupTransformer(),
      VectorToScalarAccumulationTransformer(),
      DotProductDimensionTransformer(),
      SwizzleAssignmentTransformer(),
    ],
    forcedReturnExpression: _isVertexStage ? 'OUT' : null,
    resolvedOutputComponents: _isVertexStage ? _resolvedOutputComponents : null,
  );
  late final String _inputStructName = '${data.normalizedName}_input';
  late final String _outputStructName = '${data.normalizedName}_output';
  late final String _positionFieldName = _resolvePositionFieldName();

  /// Returns the minimum component-width each FS input field requires,
  /// applying the same [_macroComponentHints] and body-analysis logic
  /// that [_typeForInputField] uses — but WITHOUT any pairedVertexOutputs
  /// bias. This is used by [collectVsRequiredOutputs] so the VS output
  /// struct is widened to match the FS stage_in declaration exactly.
  static Map<String, int> computeInputRequirements(ShaderIrData data) {
    final _InOutAnalyzer analyzer =
        _InOutAnalyzer(data.coreExpressions, data.coreFlow);
    final List<Map<String, dynamic>> metadata = data.vertexAttributeMetadata;

    int metaComponents(String token) {
      for (final Map<String, dynamic> entry in metadata) {
        if ((entry['token'] as String?) == token) {
          final int? c = entry['components'] as int?;
          if (c != null && c > 0) return c;
          break;
        }
      }
      return 4;
    }

    // Seed from vertexAttributeMetadata first so fields that appear only in
    // the metadata (no body reference) are still included.
    final Map<String, int> result = <String, int>{};
    for (final Map<String, dynamic> entry in metadata) {
      final String? token = entry['token'] as String?;
      final int? c = entry['components'] as int?;
      if (token != null && c != null && c > 0) {
        result[token] = c;
      }
    }
    // Apply analyzer usage (macro hints + explicit swizzle widths).
    analyzer.inputComponentUsage.forEach((String token, int required) {
      final int current = result[token] ?? 0;
      if (required > current) result[token] = required;
    });
    return result;
  }

  String build() {
    final StringBuffer buffer = StringBuffer();
    _computeSyntheticUniforms();
    _writePreamble(buffer);
    _writeUniformStruct(buffer);
    _writeInputStruct(buffer);
    _writeOutputStruct(buffer);
    _writeHelperFunctions(buffer);
    _writeStageFunction(buffer);
    return buffer.toString();
  }

  void _writePreamble(StringBuffer buffer) {
    buffer.writeln('#include <metal_stdlib>');
    buffer.writeln('using namespace metal;');
    buffer.writeln();
    buffer.writeln('constant bool fog_enabled    [[function_constant(0)]];');
    buffer.writeln('constant bool hdr_enabled    [[function_constant(1)]];');
    buffer.writeln('constant bool gloss_alpha    [[function_constant(2)]];');
    buffer.writeln('constant bool env_light      [[function_constant(3)]];');
    buffer.writeln('constant bool atten_enabled  [[function_constant(4)]];');
    buffer.writeln('constant bool proj_light     [[function_constant(5)]];');
    buffer.writeln('constant bool plants_bending [[function_constant(6)]];');
    buffer.writeln('constant bool alpha_glow     [[function_constant(7)]];');
    buffer.writeln('constant bool multiple_lights [[function_constant(8)]];');
    buffer.writeln('constant bool high_precision [[function_constant(9)]];');
    buffer.writeln();
  }

  void _writeVertexInputStruct(StringBuffer buffer) {
    buffer.writeln('struct $_inputStructName {');
    final List<Map<String, dynamic>> attributes = _orderedVertexAttributes;
    if (attributes.isEmpty) {
      buffer.writeln('  float3 position [[attribute(0)]];');
    } else {
      for (final Map<String, dynamic> entry in attributes) {
        final int attributeSlot =
            entry['slot'] is int ? entry['slot'] as int : 0;
        final String name =
            (entry['token'] as String?) ?? 'attr$attributeSlot';
        final String type = _vertexAttributeType(entry);
        buffer.writeln('  $type $name [[attribute($attributeSlot)]];');
      }
    }
    buffer.writeln('};');
    buffer.writeln();
  }

  void _writeUniformStruct(StringBuffer buffer) {
    final List<UniformBinding> uniforms = <UniformBinding>[
      ...data.uniforms,
      ..._syntheticUniforms.entries
          .map(
            (MapEntry<String, String> entry) =>
                UniformBinding(entry.value, entry.key, ''),
          )
          .toList(),
    ];
    if (uniforms.isEmpty) {
      return;
    }
    buffer.writeln('struct ${data.uniformStruct} {');
    for (final UniformBinding uniform in uniforms) {
      final String type = translateType(uniform.type);
      if (uniform.arraySize != null) {
        buffer.writeln('  $type ${uniform.name}[${uniform.arraySize}];');
      } else {
        buffer.writeln('  $type ${uniform.name};');
      }
    }
    buffer.writeln('};');
    buffer.writeln();
  }

  void _writeInputStruct(StringBuffer buffer) {
    if (_isVertexStage) {
      _writeVertexInputStruct(buffer);
      return;
    }
    buffer.writeln('struct $_inputStructName {');
  buffer.writeln('  float4 position [[position]];');
    final List<String> fields = List<String>.from(_analyzer.inputFields);
    final bool needsColor = _translator.usesIdentifier('IN.Color');
    if (needsColor && !fields.contains('Color')) {
      fields.insert(0, 'Color');
    }
    for (final String field in fields) {
      final String type = _typeForInputField(field);
      if (type == 'float') {
        _scalarInputFields.add(field);
      }
      buffer.writeln('  $type $field [[user($field)]];');
    }
    buffer.writeln('};');
    buffer.writeln();
  }

  void _writeOutputStruct(StringBuffer buffer) {
    buffer.writeln('struct $_outputStructName {');
    final Set<String> outputFields = <String>{
      ..._analyzer.outputFields,
      ...data.outputFieldTypes.keys,
    };
    if (_isVertexStage) {
      outputFields.add('HPosition');
      _vsOutputRequirements?.keys.forEach(outputFields.add);
    }
    final List<String> sorted = outputFields.toList()..sort();
    for (final String field in sorted) {
      final String type = _outputType(field);
      if (_isVertexStage && field == 'HPosition') {
        buffer.writeln('  $type HPosition [[position]];');
        continue;
      }
      if (_isVertexStage) {
        buffer.writeln('  $type $field [[user($field)]];');
      } else {
        buffer.writeln('  $type $field;');
      }
    }
    buffer.writeln('};');
    buffer.writeln();
  }

  void _writeHelperFunctions(StringBuffer buffer) {
    bool wroteHelper = false;
    void writeHelper(String code) {
      if (!wroteHelper) {
        wroteHelper = true;
      }
      buffer.writeln(code);
      buffer.writeln();
    }

    if (_translator.usesIdentifier('RGBToCMKY')) {
      writeHelper(
        '''
float4 RGBToCMKY(float3 vColor) {
  float4 vCMYK;
  vCMYK.xyz = clamp(1.0 - vColor, 0.0, 1.0);
  vCMYK.w = min(vCMYK.x, min(vCMYK.y, vCMYK.z));
  vCMYK.xyz = clamp(vCMYK.xyz - vCMYK.www, 0.0, 1.0);
  return vCMYK;
}
'''.trim(),
      );
    }

    if (_translator.usesIdentifier('CMKYToRGB')) {
      writeHelper(
        '''
float3 CMKYToRGB(float4 vColor) {
  return clamp(1.0 - (vColor.xyz + vColor.www), 0.0, 1.0);
}
'''.trim(),
      );
    }
  }

  String _rewriteFloat3DecalColor(String line) {
    if (!line.contains('decalColor')) {
      return line;
    }
    final String trimmed = line.trimLeft();
    if (!trimmed.startsWith('float3 ')) {
      return line;
    }
    if (line.contains('decalColor.')) {
      return line;
    }
    return line.replaceAll(RegExp(r'\bdecalColor\b(?!\.)'), 'decalColor.xyz');
  }

  void _writeStageFunction(StringBuffer buffer) {
    _stageStrategy.writeStageFunction(this, _buildParameters(), buffer);
  }

  void _writeFunctionBody(StringBuffer buffer) {
    buffer.writeln('  $_outputStructName OUT = $_outputStructName();');
    for (final String line in _translator.prologue) {
      buffer.writeln('  $line');
    }
    final bool hasWaterDeformScript =
        _hasPositionScript('PosWaterDeform') ||
            _hasPositionScript('PosWaterDeform_TNorm');
    final bool hasBendingScript =
        _hasPositionScript('PosBending') ||
            _positionScriptBlocks.any(
              (Map<String, String> script) =>
                  (script['name'] ?? '').toLowerCase() == 'posbending',
            );
    final bool needsVPos = _translator.usesIdentifier('vPos') ||
        hasWaterDeformScript ||
        _hasPositionScript('PosBeam') ||
        hasBendingScript;
    if (needsVPos && !_translator.hasVPosDeclaration) {
      buffer.writeln(
        '  float4 vPos = float4(${_positionAccessor('.xyz')}, 1.0);',
      );
    }
    _declaredDefaultVNormal = false;
    if (_translator.usesIdentifier('vNormal') &&
        !_translator.hasVNormalDeclaration) {
      final String? normalSource = _defaultNormalSource();
      if (normalSource != null) {
        buffer.writeln('  float3 vNormal = normalize($normalSource);');
        _declaredDefaultVNormal = true;
      }
    }
    if (_translator.usesIdentifier('newst') &&
        !_translator.hasNewstDeclaration) {
      buffer.writeln('  float2 newst = IN.Tex1.xy / IN.Tex1.w;');
    }
    if ((_translator.usesIdentifier('normal') ||
            _translator.usesNormalReference) &&
        !_translator.hasNormalDeclaration) {
      final String? normalSource = _defaultNormalSource();
      if (normalSource != null) {
        buffer.writeln('  float3 normal = normalize($normalSource);');
      }
    }
    _writePositionScriptAdjustments(buffer);
    if (_translator.needsSharedDif) {
      final String difType = _translator.sharedDifType;
      final String difZero = _translator.sharedDifZeroValue;
      buffer.writeln('  $difType dif = $difZero;');
    }
    for (final String line in _translator.body) {
      final String trimmed = line.trimLeft();
      if (_translator.needsSharedDif &&
          (trimmed.startsWith('float3 dif = float3(0.0);') ||
              trimmed.startsWith('dif = float3(0.0);'))) {
        continue;
      }
      buffer.writeln(_rewriteFloat3DecalColor(line));
    }
    final Set<String> analyzerOutputs = Set<String>.from(_analyzer.outputFields);
    data.outputFieldTypes.forEach((String field, String _) {
      if (field == 'Color' || field == 'HPosition') {
        return;
      }
      if (analyzerOutputs.contains(field)) {
        return;
      }
      final String type = _outputType(field);
      buffer.writeln('  OUT.$field = ${_zeroValueForType(type)};');
    });
    final bool translatorAssignedHPosition = _translator.body
        .any((String line) => line.contains('OUT.HPosition'));
    if (_isVertexStage &&
        data.outputFieldTypes.containsKey('HPosition') &&
        !_wroteHPosition &&
        !translatorAssignedHPosition) {
      buffer.writeln(
        '  OUT.HPosition = (uniforms.ModelViewProj) * float4(${_positionAccessor('.xyz')}, 1.0);',
      );
    }
    if (_isVertexStage && _vsOutputRequirements != null) {
      final Set<String> bodyWritten = <String>{
        ..._analyzer.outputFields,
        ...data.outputFieldTypes.keys,
      };
      final Map<String, String> inputAttrTypes = <String, String>{
        for (final Map<String, dynamic> a in _orderedVertexAttributes)
          if (a['token'] is String) a['token'] as String: _vertexAttributeType(a),
      };
      final List<String> sortedFields = _vsOutputRequirements!.keys.toList()..sort();
      for (final String field in sortedFields) {
        if (field == 'HPosition' || bodyWritten.contains(field)) continue;
        final String outType = _outputType(field);
        final String? inType = inputAttrTypes[field];
        if (inType != null) {
          buffer.writeln('  OUT.$field = ${_coerceValue('IN.$field', inType, outType)};');
        } else {
          buffer.writeln('  OUT.$field = ${_zeroValueForType(outType)};');
        }
      }
    }
  }

  List<String> _buildParameters() {
    final List<String> params = <String>['$_inputStructName IN [[stage_in]]'];
    if (data.uniforms.isNotEmpty || _syntheticUniforms.isNotEmpty) {
      // Slot assignments must not collide with global engine bindings:
      //   Vertex:   [[buffer(0)]] = vertex stream, [[buffer(2)]] = global Uniforms,
      //             [[buffer(5)]] = per-shader generated uniforms
      //   Fragment: [[buffer(0)]] = global Uniforms, [[buffer(1)]] = MaterialUniforms,
      //             [[buffer(2)]] = per-shader generated uniforms
      final int slot = data.stage == 'vertex' ? 5 : 2;
      params.add('constant ${data.uniformStruct}& uniforms [[buffer($slot)]]');
    }
  for (final TextureBinding texture in data.textures) {
      params.add(
        '${translateTextureType(texture.type)} ${texture.name} [[texture(${texture.slot})]]',
      );
    params.add('sampler ${texture.name}Sampler [[sampler(${texture.slot})]]');
    }
    return params;
  }

  String _typeForInputField(String field) {
    final String? override = _inputFieldTypeOverrides[field];
    if (override != null) {
      return override;
    }
    final int? pairedComponents = _pairedVertexOutputs?[field];
    if (pairedComponents != null) {
      // Use the vertex output count as the base (PSO stage interface must
      // match), but never go below what the fragment body actually accesses.
      final int required = _requiredComponentCount(field);
      return _attributeTypeForComponents(
        pairedComponents > required ? pairedComponents : required,
      );
    }
    int components = _attributeComponentCount(field);
    final int required = _requiredComponentCount(field);
    if (required > components) {
      components = required;
    }
    return _attributeTypeForComponents(components);
  }

  String _attributeTypeForComponents(int components) {
    switch (components) {
      case 1:
        return 'float';
      case 2:
        return 'float2';
      case 3:
        return 'float3';
      case 4:
        return 'float4';
      default:
        stderr.writeln(
          'WARN: unexpected attribute component count $components in _attributeTypeForComponents — using float4',
        );
        return 'float4';
    }
  }

  String _zeroValueForType(String type) {
    final String lower = type.toLowerCase();
    if (lower.contains('float4')) {
      return 'float4(0.0)';
    }
    if (lower.contains('float3')) {
      return 'float3(0.0)';
    }
    if (lower.contains('float2')) {
      return 'float2(0.0)';
    }
    if (lower.contains('float')) {
      return '0.0';
    }
    return '$type(0.0)';
  }

  String _coerceValue(String expr, String fromType, String toType) {
    if (fromType == toType) return expr;
    final int from = _componentCountFromTypeName(fromType);
    final int to = _componentCountFromTypeName(toType);
    if (from == to) return expr;
    if (to > from) {
      final List<String> zeros = List<String>.filled(to - from, '0.0');
      return '$toType($expr, ${zeros.join(', ')})';
    }
    const List<String> swizzles = <String>['x', 'xy', 'xyz', 'xyzw'];
    final String swizzle = to >= 1 && to <= 4 ? swizzles[to - 1] : 'xyzw';
    return '$expr.$swizzle';
  }

  int _componentCountFromTypeName(String type) {
    final String lower = type.toLowerCase();
    if (lower == 'float' || lower == 'float1') return 1;
    if (lower == 'float2') return 2;
    if (lower == 'float3') return 3;
    if (lower == 'float4') return 4;
    return 4;
  }

  String _vertexAttributeType(Map<String, dynamic> entry) {
    final String category =
        (entry['category'] as String? ?? '').toLowerCase();
    if (category == 'color') {
      return 'float4';
    }
    final int components =
        entry['components'] is int ? entry['components'] as int : 4;
    return _attributeTypeForComponents(components);
  }

  static const Map<String, String> _inputFieldTypeOverrides = <String, String>{
    'Tangent': 'float3',
    'Binormal': 'float3',
    'TNormal': 'float3',
    'Normal': 'float3',
  };

  String _resolvePositionFieldName() {
    if (!_isVertexStage) {
      return 'position';
    }
    for (final Map<String, dynamic> entry in _orderedVertexAttributes) {
      final String? token = entry['token'] as String?;
      if (token != null && token.toLowerCase() == 'position') {
        return token;
      }
    }
    return 'position';
  }

  String _positionAccessor(String suffix) {
    return 'IN.${_positionFieldName}$suffix';
  }

  static const Map<String, String> _macroUniformTypes = <String, String>{
    'ModelViewProj': 'float4x4',
    'Ambient': 'float4',
    'Diffuse': 'float4',
    'DiffuseSun': 'float4',
    'RealAmbient': 'float4',
    'Specular': 'float4',
    'RefrColor': 'float4',
    'TexShiftRipple': 'float4',
    'TexGenRipple0': 'float4',
    'TexGenRipple1': 'float4',
    'TexGenRipple2': 'float4',
    'TexGenRipple3': 'float4',
    'vParams01': 'float4',
    'vParams02': 'float4',
    'vCMYKParams': 'float4',
    'StartColor': 'float4',
    'EndColor': 'float4',
  };

  bool _hasPositionScript(String name) =>
      _positionScripts.contains(name.toLowerCase());

  String _outputType(String field) {
    if (!_isVertexStage) {
      return resolveFragmentOutputFieldType(
        field,
        data.outputFieldTypes,
        _analyzer.outputComponentUsage,
      );
    }
    final String? declared = data.outputFieldTypes[field];
    final int? resolved = _resolvedOutputComponents[field];
    if (resolved != null) {
      return _attributeTypeForComponents(resolved);
    }
    if (declared != null) {
      return declared;
    }
    final int? usage = _analyzer.outputComponentUsage[field];
    if (usage != null && usage > 0) {
      int width = usage;
      if (width < 2) {
        width = 2;
      } else if (width > 4) {
        width = 4;
      }
      return _attributeTypeForComponents(width);
    }
    stderr.writeln(
      'WARN: could not determine output type for vertex field "$field" — using float4',
    );
    return 'float4';
  }

  void _computeSyntheticUniforms() {
    for (final MapEntry<String, String> entry in _macroUniformTypes.entries) {
      final String name = entry.key;
      if (_uniformTypes.containsKey(name)) {
        continue;
      }
      if (_translator.usesIdentifier(name)) {
        _syntheticUniforms[name] = entry.value;
        _uniformTypes[name] = entry.value;
      }
    }
    _ensureModelViewProjForHPosition();
  }

  void _ensureModelViewProjForHPosition() {
    if (!_isVertexStage) return;
    if (!data.outputFieldTypes.containsKey('HPosition')) return;
    if (_uniformTypes.containsKey('ModelViewProj')) return;
    final bool translatorAssignedHPosition =
        _translator.body.any((String line) => line.contains('OUT.HPosition'));
    if (!translatorAssignedHPosition) {
      _syntheticUniforms['ModelViewProj'] = 'float4x4';
      _uniformTypes['ModelViewProj'] = 'float4x4';
    }
  }

  String? _defaultNormalSource() {
    if (_analyzer.inputFields.contains('TNormal')) {
      return 'IN.TNormal.xyz';
    }
    if (_analyzer.inputFields.contains('Normal')) {
      return 'IN.Normal.xyz';
    }
    if (_analyzer.inputFields.contains('Tangent') &&
        _analyzer.inputFields.contains('Binormal')) {
      return 'cross(IN.Tangent, IN.Binormal)';
    }
    return 'float3(0.0, 0.0, 1.0)';
  }

  void _writePositionScriptAdjustments(StringBuffer buffer) {
    final Set<String> emitted = <String>{};
    final bool hasWaterDeform =
        _hasPositionScript('PosWaterDeform') ||
            _hasPositionScript('PosWaterDeform_TNorm');
    if (hasWaterDeform) {
      emitted.add('poswaterdeform');
      _writePosWaterDeform(buffer);
    }
    if (_hasPositionScript('PosBeam')) {
      emitted.add('posbeam');
      _writePosBeam(buffer);
    }
    if (_hasPositionScript('PosBending')) {
      emitted.add('posbending');
      _writePosBending(buffer);
    }
    for (final Map<String, String> script in _positionScriptBlocks) {
      final String nameLower = (script['name'] ?? '').toLowerCase();
      final String content = script['content'] ?? '';
      if (nameLower == 'posbending' && !emitted.contains('posbending')) {
        emitted.add('posbending');
        _writePosBending(buffer);
        continue;
      }
      if (nameLower.isEmpty &&
          !emitted.contains('heatvision_source') &&
          content.contains('fFactor') &&
          content.contains('Source0')) {
        emitted.add('heatvision_source');
        _writeHeatVisionSource(buffer);
      }
    }
  }

  void _writePosWaterDeform(StringBuffer buffer) {
    final int pgSize = _uniformArraySize('pg', 66);
    buffer.writeln('  const uint kPgPermutationSize = ${pgSize}u;');
    buffer.writeln(
      '  float2 _noiseCoord = float2(${_positionAccessor('.x')}, ${_positionAccessor('.y')}) + uniforms.NoisePos.xy;',
    );
    buffer.writeln('  float2 _noiseIndex = fract(_noiseCoord * 0.03125);');
    buffer.writeln('  float2 _noiseIdxScaled = _noiseIndex * 32.0;');
    buffer.writeln('  float2 _noiseFrac = fract(_noiseCoord);');
    buffer.writeln(
      '  uint _idx0 = uint(_noiseIdxScaled.x) % kPgPermutationSize;',
    );
    buffer.writeln('  uint _idx0p1 = (_idx0 + 1u) % kPgPermutationSize;');
    buffer.writeln('  float _permBase0 = uniforms.pg[_idx0].w;');
    buffer.writeln('  float _permBase1 = uniforms.pg[_idx0p1].w;');
    buffer.writeln('  float2 _perm;');
    buffer.writeln('  _perm.x = _permBase0 + _noiseIdxScaled.y;');
    buffer.writeln('  _perm.y = _permBase1 + _noiseIdxScaled.y;');
    buffer.writeln('  uint _perm0 = uint(_perm.x) % kPgPermutationSize;');
    buffer.writeln('  uint _perm1 = uint(_perm.y) % kPgPermutationSize;');
    buffer.writeln('  uint _perm0p1 = (_perm0 + 1u) % kPgPermutationSize;');
    buffer.writeln('  uint _perm1p1 = (_perm1 + 1u) % kPgPermutationSize;');
    buffer.writeln('  float2 _grad0 = uniforms.pg[_perm0].xy;');
    buffer.writeln('  float2 _grad1 = uniforms.pg[_perm1].xy;');
    buffer.writeln('  float2 _grad2 = uniforms.pg[_perm0p1].xy;');
    buffer.writeln('  float2 _grad3 = uniforms.pg[_perm1p1].xy;');
    buffer.writeln('  float dot00 = dot(_grad0, _noiseFrac);');
    buffer.writeln(
      '  float dot10 = dot(_grad1, _noiseFrac - float2(1.0, 0.0));',
    );
    buffer.writeln(
      '  float dot01 = dot(_grad2, _noiseFrac - float2(0.0, 1.0));',
    );
    buffer.writeln(
      '  float dot11 = dot(_grad3, _noiseFrac - float2(1.0, 1.0));',
    );
    buffer.writeln(
      '  float2 _fade = _noiseFrac * _noiseFrac * (float2(3.0) - float2(2.0) * _noiseFrac);',
    );
    buffer.writeln('  float lerpY0 = mix(dot00, dot01, _fade.y);');
    buffer.writeln('  float lerpY1 = mix(dot10, dot11, _fade.y);');
    buffer.writeln('  float fNoise = mix(lerpY0, lerpY1, _fade.x);');
    buffer.writeln('  vPos.z += fNoise * uniforms.NoisePos.w;');
  }

  void _writePosBeam(StringBuffer buffer) {
    buffer.writeln('  float fiOrigLength = 1.0 / uniforms.GeomConstants.x;');
    buffer.writeln('  float fLerp = vPos.x * fiOrigLength;');
    buffer.writeln('  vPos.x = fLerp * uniforms.CameraPos.w;');
    buffer.writeln(
      '  float fCurRadius = mix(uniforms.GeomConstants.z, uniforms.GeomConstants.w, fLerp);',
    );
    buffer.writeln('  float fiOrigWidth = 1.0 / uniforms.GeomConstants.y;');
    buffer.writeln('  vPos.yz = vPos.yz * fiOrigWidth * fCurRadius;');
  }

  void _writePosBending(StringBuffer buffer) {
    final bool hasTexCoord3 =
        _analyzer.inputFields.contains('TexCoord3');
    final bool hasTexCoord6 =
        _analyzer.inputFields.contains('TexCoord6');
    if (hasTexCoord6) {
      buffer.writeln(
        '  float4 vBend = ${_expandedInputAttribute('TexCoord6', 4)};',
      );
    } else if (hasTexCoord3) {
      buffer.writeln(
        '  float4 vBend = ${_expandedInputAttribute('TexCoord3', 4)};',
      );
    } else {
      buffer.writeln('  float4 vBend = uniforms.Bend;');
    }
    buffer.writeln(
      '  float fBF = max(vPos.z, 0.0) * vBend.z + vBend.w;',
    );
    buffer.writeln('  fBF = fBF * fBF;');
    buffer.writeln('  fBF = fBF * fBF - vBend.w;');
    buffer.writeln('  float2 vP = vBend.xy * fBF;');
    buffer.writeln('  float fLength = length(vPos.xyz);');
    buffer.writeln('  vPos.xy += vP;');
    buffer.writeln('  float3 vDirect = normalize(vPos.xyz);');
    buffer.writeln('  vPos.xyz = vDirect * fLength;');
  }

  String _expandedInputAttribute(String token, int targetComponents) {
    final int available = _attributeComponentCount(token);
    if (available >= targetComponents) {
      return 'IN.$token';
    }
    final List<String> swizzles = <String>['x', 'y', 'z', 'w'];
    final List<String> parts = <String>[];
    for (int i = 0; i < available; i++) {
      parts.add('IN.$token.${swizzles[i]}');
    }
    for (int i = available; i < targetComponents; i++) {
      parts.add(i == 3 ? '1.0' : '0.0');
    }
    return 'float$targetComponents(${parts.join(', ')})';
  }

  int _attributeComponentCount(String token) {
    for (final Map<String, dynamic> entry in _vertexAttributeMetadata) {
      if ((entry['token'] as String?) == token) {
        final int? components = entry['components'] as int?;
        if (components != null && components > 0) {
          return components;
        }
        break;
      }
    }
    return 4;
  }

  int _requiredComponentCount(String token) {
    final int? usage = _analyzer.inputComponentUsage[token];
    if (usage == null || usage <= 0) {
      return 0;
    }
    return usage;
  }

  bool _isTexcoordToken(String token) {
    for (final Map<String, dynamic> entry in _vertexAttributeMetadata) {
      if ((entry['token'] as String?) == token) {
        final String category =
            (entry['category'] as String? ?? '').toLowerCase();
        return category == 'texcoord';
      }
    }
    final String lower = token.toLowerCase();
    return lower.startsWith('tex');
  }

  void _writeHeatVisionSource(StringBuffer buffer) {
    if (_translator.hasVNormalDeclaration || _declaredDefaultVNormal) {
      buffer.writeln('  vNormal = normalize(IN.Normal.xyz);');
    } else {
      buffer.writeln('  float3 vNormal = normalize(IN.Normal.xyz);');
    }
    buffer.writeln(
      '  float fFactor = length(vPos.xyz - uniforms.Source0.xyz) * uniforms.Dist.x;',
    );
    buffer.writeln('  fFactor = (1.0 / max(fFactor, 1e-4)) / 8.0;');
    buffer.writeln(
      '  vPos.xyz = ${_positionAccessor('.xyz')} + vNormal.xyz * uniforms.Constants.x * clamp(fFactor, 0.0, 2.0);',
    );
    buffer.writeln('  vPos.w = ${_positionAccessor('.w')};');
    if (_analyzer.outputFields.contains('HPosition')) {
      buffer.writeln('  OUT.HPosition = (uniforms.ModelViewProj) * (vPos);');
      _wroteHPosition = true;
    }
  }

  int _uniformArraySize(String name, int defaultValue) {
    final UniformBinding? binding = _findUniform(name);
    if (binding == null || binding.arraySize == null) {
      return defaultValue;
    }
    return binding.arraySize!;
  }

  UniformBinding? _findUniform(String name) {
    for (final UniformBinding uniform in data.uniforms) {
      if (uniform.name == name) {
        return uniform;
      }
    }
    return null;
  }
}


class _InOutAnalyzer {
  _InOutAnalyzer(
    List<Map<String, dynamic>> expressions, [
    List<Map<String, dynamic>> flow = const [],
  ]) : _expressions = expressions,
        _flow = flow {
    _scan();
  }

  final List<Map<String, dynamic>> _expressions;
  final List<Map<String, dynamic>> _flow;
  final Set<String> _inputFields = <String>{};
  final Map<String, int> _inputComponentUsage = <String, int>{};
  final Set<String> _outputFields = <String>{};
  final Map<String, int> _outputComponentUsage = <String, int>{};

  List<String> get inputFields {
    final List<String> fields = _inputFields.toList();
    fields.sort();
    return fields;
  }

  Map<String, int> get inputComponentUsage => _inputComponentUsage;
  Map<String, int> get outputComponentUsage => _outputComponentUsage;

  List<String> get outputFields {
    final Set<String> fields = Set<String>.from(_outputFields);
    fields.add('Color');
    final List<String> sorted = fields.toList();
    sorted.sort();
    return sorted;
  }

  void _scan() {
    for (final Map<String, dynamic> expr in _expressions) {
      final Object? activeState = expr['active'];
      if (activeState is bool && activeState == false) {
        continue;
      }
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
        _trackComponentUsage(token, match.group(2));
      }
    }
    for (final RegExpMatch match in _outPattern.allMatches(content)) {
      final String? token = match.group(1);
      if (token != null && token.isNotEmpty) {
        _outputFields.add(token);
        _trackOutputComponentUsage(token, match.group(2));
      }
    }
    for (final MapEntry<String, List<String>> entry
        in _macroInputFields.entries) {
      if (content.contains(entry.key)) {
        _inputFields.addAll(entry.value);
      }
    }
    for (final MapEntry<String, Map<String, int>> hint
        in _macroComponentHints.entries) {
      if (content.contains(hint.key)) {
        hint.value.forEach((String token, int components) {
          _inputFields.add(token);
          final int current = _inputComponentUsage[token] ?? 0;
          if (components > current) {
            _inputComponentUsage[token] = components;
          }
        });
      }
    }
  }

  static final RegExp _inPattern =
      RegExp(r'IN\.([A-Za-z0-9_]+)(?:\.([A-Za-z0-9]+))?');
  static final RegExp _outPattern =
      RegExp(r'OUT\.([A-Za-z0-9_]+)(?:\.([A-Za-z0-9]+))?');

  static final Map<String, List<String>> _macroInputFields =
      <String, List<String>>{
        'TANG_MATR': <String>['Tangent', 'Binormal', 'TNormal'],
        'vNormal': <String>['Normal'],
      };

  static final Map<String, Map<String, int>> _macroComponentHints =
      <String, Map<String, int>>{
    'texCUBE': <String, int>{
      'Tex1': 3,
      'Tex2': 3,
      'Tex3': 3,
    },
  };

  void _trackComponentUsage(String token, String? swizzle) {
    if (swizzle == null || swizzle.isEmpty) {
      return;
    }
    final int required = _swizzleWidth(swizzle);
    if (required <= 0) {
      return;
    }
    final int current = _inputComponentUsage[token] ?? 0;
    if (required > current) {
      _inputComponentUsage[token] = required;
    }
  }

  void _trackOutputComponentUsage(String token, String? swizzle) {
    int required;
    if (swizzle == null || swizzle.isEmpty) {
      required = 4;
    } else {
      required = _swizzleWidth(swizzle);
    }
    if (required <= 0) {
      return;
    }
    final int current = _outputComponentUsage[token] ?? 0;
    if (required > current) {
      _outputComponentUsage[token] = required;
    }
  }

  static int _swizzleWidth(String swizzle) {
    int width = 0;
    for (int i = 0; i < swizzle.length; i++) {
      final int value = _componentIndex(swizzle[i]);
      if (value > width) {
        width = value;
        if (width >= 4) {
          return 4;
        }
      }
    }
    return width;
  }

  static int _componentIndex(String char) {
    switch (char) {
      case 'x':
      case 'X':
      case 'r':
      case 'R':
      case 's':
      case 'S':
        return 1;
      case 'y':
      case 'Y':
      case 'g':
      case 'G':
      case 't':
      case 'T':
        return 2;
      case 'z':
      case 'Z':
      case 'b':
      case 'B':
      case 'p':
      case 'P':
        return 3;
      case 'w':
      case 'W':
      case 'a':
      case 'A':
      case 'q':
      case 'Q':
        return 4;
      default:
        return 0;
    }
  }
}

String translateType(String type) {
  final String lower = type.toLowerCase();
  final RegExp matrixPattern = RegExp(r'float(\d)x(\d)');
  final Match? matrixMatch = matrixPattern.firstMatch(lower);
  if (matrixMatch != null) {
    final String rows = matrixMatch.group(1)!;
    final String cols = matrixMatch.group(2)!;
    return 'float${cols}x${rows}';
  }
  switch (lower) {
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
      stderr.writeln(
        'WARN: translateType: unknown HLSL type "$type" — using float4 fallback',
      );
      return 'float4';
  }
}

String translateTextureType(String type) {
  final String lower = type.toLowerCase();
  if (lower.contains('cube')) return 'texturecube<float>';
  if (lower.contains('1d')) return 'texture1d<float>';
  if (lower.contains('3d')) return 'texture3d<float>';
  if (lower.isEmpty || lower.contains('2d') || lower.startsWith('sampler')) {
    return 'texture2d<float>';
  }
  stderr.writeln(
    'WARN: translateTextureType: unknown texture type "$type" — using texture2d<float> fallback',
  );
  return 'texture2d<float>';
}

