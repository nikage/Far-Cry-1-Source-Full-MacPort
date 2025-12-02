part of 'metal_generator.dart';

class MetalFragmentBuilder {
  MetalFragmentBuilder(this.data)
    : _analyzer = _InOutAnalyzer(data.coreExpressions, data.coreFlow),
      _positionScripts = data.positionScripts
          .map((String script) => script.toLowerCase())
          .toSet(),
      _positionScriptBlocks = data.positionScriptBlocks {
    for (final String field in _analyzer.inputFields) {
      final String? override = _inputFieldTypeOverrides[field];
      if (override == 'float') {
        _scalarInputFields.add(field);
      }
    }
  }

  final ShaderIrData data;
  final _InOutAnalyzer _analyzer;
  final Set<String> _positionScripts;
  final List<Map<String, String>> _positionScriptBlocks;
  final Set<String> _scalarInputFields = <String>{};
  bool _declaredDefaultVNormal = false;
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
      Float3ColorTransformer(),
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
  );
  late final String _inputStructName = '${data.normalizedName}_input';
  late final String _outputStructName = '${data.normalizedName}_output';

  String build() {
    final StringBuffer buffer = StringBuffer();
    _computeSyntheticUniforms();
    _writePreamble(buffer);
    _writeUniformStruct(buffer);
    _writeInputStruct(buffer);
    _writeOutputStruct(buffer);
    _writeHelperFunctions(buffer);
    _writeFragmentFunction(buffer);
    return buffer.toString();
  }

  void _writePreamble(StringBuffer buffer) {
  buffer.writeln('#include <metal_stdlib>');
  buffer.writeln('using namespace metal;');
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
    buffer.writeln('struct $_inputStructName {');
  buffer.writeln('  float4 position [[position]];');
    final List<String> fields = List<String>.from(_analyzer.inputFields);
    if (!fields.contains('Color')) {
      fields.insert(0, 'Color');
    }
    for (final String field in fields) {
      final String type = _typeForInputField(field);
      if (type == 'float') {
        _scalarInputFields.add(field);
      }
      buffer.writeln('  $type $field;');
  }
  buffer.writeln('};');
  buffer.writeln();
  }

  void _writeOutputStruct(StringBuffer buffer) {
    buffer.writeln('struct $_outputStructName {');
    for (final String field in _analyzer.outputFields) {
      final String type = _outputType(field);
      buffer.writeln('  $type $field;');
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
  void _writeFragmentFunction(StringBuffer buffer) {
    buffer.writeln(
      'fragment float4 ${data.fragmentName}(${_buildParameters().join(', ')})',
    );
    buffer.writeln('{');
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
      buffer.writeln('  float4 vPos = float4(IN.position.xyz, 1.0);');
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
      buffer.writeln(line);
    }
    buffer.writeln('  return ${_translator.returnExpression};');
    buffer.writeln('}');
  }

  List<String> _buildParameters() {
    final List<String> params = <String>['$_inputStructName IN [[stage_in]]'];
  if (data.uniforms.isNotEmpty || _syntheticUniforms.isNotEmpty) {
    params.add('constant ${data.uniformStruct}& uniforms [[buffer(0)]]');
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
    return 'float4';
  }

  static const Map<String, String> _inputFieldTypeOverrides = <String, String>{
    'Tangent': 'float3',
    'Binormal': 'float3',
    'TNormal': 'float3',
    'Normal': 'float3',
    'HeightMap': 'float',
  };

  static const Map<String, String> _macroUniformTypes = <String, String>{
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

  String _outputType(String field) => data.outputFieldTypes[field] ?? 'float4';

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
      '  float2 _noiseCoord = float2(IN.position.x, IN.position.y) + uniforms.NoisePos.xy;',
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
      buffer.writeln('  float4 vBend = IN.TexCoord6;');
    } else if (hasTexCoord3) {
      buffer.writeln('  float4 vBend = IN.TexCoord3;');
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
      '  vPos.xyz = IN.position.xyz + vNormal.xyz * uniforms.Constants.x * clamp(fFactor, 0.0, 2.0);',
    );
    buffer.writeln('  vPos.w = IN.position.w;');
    if (_analyzer.outputFields.contains('HPosition')) {
      buffer.writeln('  OUT.HPosition = (uniforms.ModelViewProj) * (vPos);');
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
      }
    }
    for (final RegExpMatch match in _outPattern.allMatches(content)) {
      final String? token = match.group(1);
      if (token != null && token.isNotEmpty) {
        _outputFields.add(token);
      }
    }
    for (final MapEntry<String, List<String>> entry
        in _macroInputFields.entries) {
      if (content.contains(entry.key)) {
        _inputFields.addAll(entry.value);
      }
    }
  }

  static final RegExp _inPattern = RegExp(r'IN\.([A-Za-z0-9_]+)');
  static final RegExp _outPattern = RegExp(r'OUT\.([A-Za-z0-9_]+)');

  static final Map<String, List<String>> _macroInputFields =
      <String, List<String>>{
        'TANG_MATR': <String>['Tangent', 'Binormal', 'TNormal'],
        'vNormal': <String>['Normal'],
      };
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
      return 'float4';
  }
}

String translateTextureType(String type) {
  final String lower = type.toLowerCase();
  if (lower.contains('cube')) return 'texturecube<float>';
  if (lower.contains('1d')) return 'texture1d<float>';
  if (lower.contains('3d')) return 'texture3d<float>';
  return 'texture2d<float>';
}

