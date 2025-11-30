part of 'metal_generator.dart';

class ExpressionTranslator {
  ExpressionTranslator(
    this.data,
    this.analyzer,
    Set<String> scalarInputFields,
    List<LineTransformer> transformers,
  ) : _scalarInputFields = Set<String>.from(scalarInputFields),
      _transformers = transformers {
    _build();
  }

  final ShaderIrData data;
  final _InOutAnalyzer analyzer;
  final Set<String> _scalarInputFields;
  final List<LineTransformer> _transformers;
  final List<String> prologue = <String>[];
  final List<String> body = <String>[];
  late final String returnExpression;
  bool _hasVPosDeclaration = false;
  bool _hasVNormalDeclaration = false;
  bool _hasNormalDeclaration = false;
  bool _usesNormalReference = false;
  bool _hasNewstDeclaration = false;
  final Set<String> _scalarVariables = <String>{};
  late final Set<String> _scalarUniforms = data.uniforms
      .where((UniformBinding u) => _isScalarType(u.type))
      .map((UniformBinding u) => u.name)
      .toSet();

  void _build() {
    final List<List<String>> expressionBatches = <List<String>>[];
    final List<_ConditionalFrame> conditionalStack = <_ConditionalFrame>[];
    for (final String field in analyzer.outputFields) {
      final String type = _outputType(field);
      prologue.add('OUT.$field = ${_zeroValueForType(type)};');
    }
    for (final Map<String, dynamic> expr in data.coreExpressions) {
      final String? raw = expr['raw'] as String?;
      if (raw == null) {
        continue;
      }
      final String trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed.startsWith('#')) {
        final bool emitDirective =
            _processPreprocessorDirective(trimmed, conditionalStack);
        if (emitDirective) {
          final String convertedDirective = _rewritePreprocessor(trimmed);
          if (convertedDirective.isNotEmpty) {
            expressionBatches.add(<String>[convertedDirective]);
          }
        }
        continue;
      }
      if (_isSkippingConditionalBlock(conditionalStack)) {
        continue;
      }
      if (trimmed.startsWith('//')) {
        continue;
      }
      if (trimmed == 'return OUT;') {
        continue;
      }
      if (_identifierRegexNormal.hasMatch(trimmed)) {
        _usesNormalReference = true;
      }
      _noteScalarVariable(expr['lhs'] as String?);
      final List<String> lines = <String>[];
      final List<String>? macroExpansion = _expandMacro(trimmed);
      if (macroExpansion != null) {
        for (final String macroLine in macroExpansion) {
          final String convertedMacro = _rewriteLine(macroLine);
          if (convertedMacro.isEmpty) {
            continue;
          }
          for (final String part in convertedMacro.split('\n')) {
            final String trimmedPart = part.trim();
            if (trimmedPart.isEmpty) {
              continue;
            }
            lines.add(trimmedPart);
            _noteDeclarations(trimmedPart);
          }
        }
      } else {
      final String converted = _rewriteLine(trimmed);
      if (converted.isEmpty) {
        continue;
      }
        for (final String part in converted.split('\n')) {
          final String trimmedPart = part.trim();
          if (trimmedPart.isEmpty) {
            continue;
          }
          lines.add(trimmedPart);
          _noteDeclarations(trimmedPart);
        }
      }
      if (lines.isNotEmpty) {
        expressionBatches.add(lines);
      }
    }
    _buildBodyFromFlow(expressionBatches);
    _hoistDuplicateDeclarations();
    _balancePreprocessorDirectives();
    _rewritePlantDiffuseBlock();
    returnExpression = analyzer.outputFields.contains('Color')
        ? 'OUT.Color'
        : 'float4(0.0)';
  }

  bool get hasVPosDeclaration => _hasVPosDeclaration;
  bool get hasVNormalDeclaration => _hasVNormalDeclaration;
  bool get hasNormalDeclaration => _hasNormalDeclaration;
  bool get usesNormalReference => _usesNormalReference;
  bool get hasNewstDeclaration => _hasNewstDeclaration;

  bool _processPreprocessorDirective(
    String line,
    List<_ConditionalFrame> stack,
  ) {
    final String lower = line.toLowerCase();
    final String directive =
        lower.replaceFirst(RegExp(r'^#\s*'), '#').trimLeft();
    if (directive.startsWith('#if')) {
      final bool skipInstancing = _containsInstancingGuard(lower);
      if (skipInstancing) {
        stack.add(_ConditionalFrame(skipInstancing: true, skipping: true));
        return false;
      }
      return true;
    }
    if (directive.startsWith('#elif')) {
      if (stack.isEmpty) {
        return true;
      }
      final _ConditionalFrame frame = stack.last;
      if (!frame.skipInstancing) {
        return true;
      }
      // Keep skipping until we reach an #else.
      frame.skipping = true;
      return false;
    }
    if (directive.startsWith('#else')) {
      if (stack.isEmpty) {
        return true;
      }
      final _ConditionalFrame frame = stack.last;
      if (!frame.skipInstancing) {
        return true;
      }
      frame.skipping = false;
      return false;
    }
    if (directive.startsWith('#endif')) {
      if (stack.isNotEmpty) {
        stack.removeLast();
        return false;
      }
      return true;
    }
    return true;
  }

  bool _isSkippingConditionalBlock(List<_ConditionalFrame> stack) {
    for (final _ConditionalFrame frame in stack) {
      if (frame.skipping) {
        return true;
      }
    }
    return false;
  }

  bool _containsInstancingGuard(String line) {
    return line.contains('_inst_r') || line.contains('_inst_nr');
  }

  void _noteDeclarations(String line) {
    if (!_hasVPosDeclaration && _declaresVPos(line)) {
      _hasVPosDeclaration = true;
    }
    if (!_hasVNormalDeclaration && _declaresVNormal(line)) {
      _hasVNormalDeclaration = true;
    }
    if (!_hasNormalDeclaration && _declaresNormal(line)) {
      _hasNormalDeclaration = true;
    }
    if (!_hasNewstDeclaration && _declaresNewst(line)) {
      _hasNewstDeclaration = true;
    }
  }

  bool _declaresVPos(String line) {
    return _vPosDeclarationPattern.hasMatch(line);
  }

  bool _declaresVNormal(String line) {
    return _vNormalDeclarationPattern.hasMatch(line);
  }

  bool _declaresNormal(String line) {
    return _normalDeclarationPattern.hasMatch(line);
  }

  bool _declaresNewst(String line) {
    return _newstDeclarationPattern.hasMatch(line);
  }

  static final RegExp _vPosDeclarationPattern = RegExp(r'\bfloat\d*\s+vPos\b');
  static final RegExp _vNormalDeclarationPattern = RegExp(
    r'\bfloat\d*\s+vNormal\b',
  );
  static final RegExp _normalDeclarationPattern = RegExp(r'\bfloat\d*\s+normal\b');
  static final RegExp _identifierRegexNormal =
      RegExp(r'(?<![A-Za-z0-9_])normal(?![A-Za-z0-9_])');
  static final RegExp _newstDeclarationPattern = RegExp(r'\bfloat\d*\s+newst\b');
  static final RegExp _scalarDeclarationPattern = RegExp(
    r'^(float|half|int|uint|bool)\s+([A-Za-z_][A-Za-z0-9_]*)$',
  );
  static final RegExp _numericLiteralPattern = RegExp(
    r'^-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?[fF]?$',
  );
  static final RegExp _identifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  void _noteScalarVariable(String? lhs) {
    if (lhs == null) {
      return;
    }
    final String trimmed = lhs.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final RegExpMatch? match = _scalarDeclarationPattern.firstMatch(trimmed);
    if (match == null) {
      return;
    }
    final String name = match.group(2)!;
    _scalarVariables.add(name);
  }

  void _hoistDuplicateDeclarations() {
    final RegExp declPattern =
        RegExp(r'^(float[234]?|half[234]?|float|half)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=');
    final Map<String, String> types = <String, String>{};
    final Map<String, List<int>> indices = <String, List<int>>{};
    final Map<int, String> occurrenceTypes = <int, String>{};
    for (int i = 0; i < body.length; i++) {
      final String trimmed = body[i].trimLeft();
      final RegExpMatch? match = declPattern.firstMatch(trimmed);
      if (match == null) {
        continue;
      }
      final String type = match.group(1)!;
      final String name = match.group(2)!;
      types.putIfAbsent(name, () => type);
      indices.putIfAbsent(name, () => <int>[]).add(i);
      occurrenceTypes[i] = type;
    }
    for (final MapEntry<String, List<int>> entry in indices.entries) {
      if (entry.value.length <= 1) {
        continue;
      }
      final String name = entry.key;
      final String type = types[name] ?? 'float4';
      final String zeroValue = _zeroValueForDataType(type);
      prologue.add('  $type $name = $zeroValue;');
      for (final int index in entry.value) {
        final String original = body[index];
        final int leadingSpaces =
            original.length - original.trimLeft().length;
        final String prefix = original.substring(0, leadingSpaces);
        final String trimmed = original.substring(leadingSpaces);
        String updated = trimmed.replaceFirst(
          RegExp(r'^(float[234]?|half[234]?|float|half)\s+'),
          '',
        );
        final String occurrenceType = occurrenceTypes[index] ?? type;
        if (type == 'float4') {
          if (occurrenceType == 'float3') {
            updated = updated.replaceFirst(
              '$name =',
              '$name.xyz =',
            );
          } else if (occurrenceType == 'float2') {
            updated = updated.replaceFirst(
              '$name =',
              '$name.xy =',
            );
          } else if (occurrenceType == 'float') {
            updated = updated.replaceFirst(
              '$name =',
              '$name.x =',
            );
          }
        }
        body[index] = prefix + updated;
      }
    }
    for (int i = 0; i < body.length; i++) {
      final String trimmed = body[i].trimLeft();
      if (trimmed.startsWith('vFinalColor=')) {
        final int leadingSpaces = body[i].length - trimmed.length;
        final String prefix = body[i].substring(0, leadingSpaces);
        body[i] =
            '$prefix${trimmed.replaceFirst('vFinalColor=', 'vFinalColor.xyz = ')}';
      }
    }
  }

  String _zeroValueForDataType(String type) {
    switch (type) {
      case 'float':
      case 'half':
        return '0.0';
      case 'float2':
      case 'half2':
        return '$type(0.0)';
      case 'float3':
      case 'half3':
        return '$type(0.0)';
      case 'float4':
      case 'half4':
        return '$type(0.0)';
      default:
        return '$type(0.0)';
    }
  }

  void _balancePreprocessorDirectives() {
    final List<String> stack = <String>[];
    final List<int> removals = <int>[];
    for (int i = 0; i < body.length; i++) {
      final String trimmed = body[i].trimLeft();
      if (trimmed.startsWith('#if')) {
        stack.add('#if');
        continue;
      }
      if (trimmed.startsWith('#ifdef')) {
        stack.add('#ifdef');
        continue;
      }
      if (trimmed.startsWith('#ifndef')) {
        stack.add('#ifndef');
        continue;
      }
      if (trimmed.startsWith('#endif')) {
        if (stack.isEmpty) {
          removals.add(i);
        } else {
          stack.removeLast();
        }
      }
    }
    for (int i = removals.length - 1; i >= 0; i--) {
      body.removeAt(removals[i]);
    }
    for (int i = 0; i < body.length; i++) {
      body[i] = body[i].replaceAll('.xyz.xyz', '.xyz');
    }
  }

  void _rewritePlantDiffuseBlock() {
    const String target =
        'decalColor.xyz * projColor.xyz * uniforms.Diffuse.xyz * IN.Color.xyz';
    final List<int> indices = <int>[];
    for (int i = 0; i < body.length; i++) {
      if (body[i].contains(target)) {
        indices.add(i);
      }
    }
    if (indices.isEmpty) {
      return;
    }
    final bool hasColor1 =
        body.any((String line) => line.contains('IN.Color1'));
    final bool hasBumpNormal =
        body.any((String line) => line.contains('bumpNormal'));
    final bool hasNormCube =
        body.any((String line) => line.contains('normCubeMap'));
    if (!hasColor1) {
      return;
    }
    if (!hasBumpNormal || !hasNormCube) {
      return;
    }
    int firstIndex = indices.first;
    for (int i = body.length - 1; i >= 0; i--) {
      if (body[i].trimLeft().startsWith('float3 dif = float3(0.0);')) {
        if (i < firstIndex) {
          firstIndex -= 1;
        }
        body.removeAt(i);
      }
    }
    body[firstIndex] =
        '  float3 dif = NdotL * IN.Color.a * projColor.xyz * uniforms.Diffuse.xyz;';
    final bool hasDifSun =
        body.any((String line) => line.contains('difSun ='));
    if (!hasDifSun) {
      final int insertIndex = firstIndex + 1;
      body.insertAll(
        insertIndex,
        <String>[
          '  float3 lightVecSun = 2.0 * (IN.Color1.xyz - 0.5);',
          '  float fDifSun = clamp(dot(bumpNormal.xyz, lightVecSun), 0.0, 1.0);',
          '  float3 difSun = fDifSun * uniforms.DiffuseSun.xyz;',
        ],
      );
    }
    for (int i = indices.length - 1; i >= 1; i--) {
      body.removeAt(indices[i]);
    }
    bool lightVecSunSeen = false;
    bool fDifSunSeen = false;
    bool difSunSeen = false;
    for (int i = firstIndex; i < body.length; i++) {
      final String trimmed = body[i].trimLeft();
      if (trimmed.startsWith('float3 lightVecSun')) {
        if (lightVecSunSeen) {
          body.removeAt(i);
          i--;
          continue;
        }
        lightVecSunSeen = true;
        continue;
      }
      if (trimmed.startsWith('float fDifSun')) {
        if (fDifSunSeen) {
          body.removeAt(i);
          i--;
          continue;
        }
        fDifSunSeen = true;
        continue;
      }
      if (trimmed.startsWith('float3 difSun')) {
        if (difSunSeen) {
          body.removeAt(i);
          i--;
        } else {
          difSunSeen = true;
        }
      }
    }
    for (int i = body.length - 1; i >= 0; i--) {
      if (body[i].contains(target)) {
        body.removeAt(i);
      }
    }
    if (indices.isNotEmpty) {
      final bool hasLightVecSun =
          body.any((String line) => line.trimLeft().startsWith('float3 lightVecSun'));
      final bool hasFDifSun =
          body.any((String line) => line.trimLeft().startsWith('float fDifSun'));
      if (!hasLightVecSun) {
        body.insert(
          firstIndex + 1,
          '  float3 lightVecSun = 2.0 * (IN.Color1.xyz - 0.5);',
        );
      }
      if (!hasFDifSun) {
        body.insert(
          firstIndex + 2,
          '  float fDifSun = clamp(dot(bumpNormal.xyz, lightVecSun), 0.0, 1.0);',
        );
      }
      if (!body.any((String line) => line.trimLeft().startsWith('float3 difSun'))) {
        final int ambIndex = body.indexWhere(
          (String line) =>
              line.contains('uniforms.Ambient.xyz') && line.contains('difSun'),
        );
        final int insertIndex = ambIndex == -1 ? firstIndex + 3 : ambIndex;
        body.insert(
          insertIndex,
          '  float3 difSun = fDifSun * uniforms.DiffuseSun.xyz;',
        );
      }
    }
  }

  String _normalizeScalarComponents(String line) {
    String result = line;
    final List<String> scalarNames = <String>[];
    scalarNames.addAll(_scalarVariables);
    scalarNames.addAll(_scalarUniforms.map((String name) => 'uniforms.$name'));
    scalarNames.addAll(_scalarInputFields.map((String field) => 'IN.$field'));
    for (final String scalar in scalarNames) {
      if (scalar.isEmpty) {
        continue;
      }
      final RegExp pattern = RegExp(
        '(?<![A-Za-z0-9_\\.])${RegExp.escape(scalar)}\\.([xyzwrgba])\\b',
      );
      result = result.replaceAllMapped(pattern, (Match match) => scalar);
    }
    return result;
  }

  String _normalizeModuloLiterals(String line) {
    String result = line.replaceAll(RegExp(r'%\s*1(?!\d)'), '% 1.0');
    result = result.replaceAllMapped(
      RegExp(r'((?:uniforms|IN)\.[A-Za-z0-9_\.]+)\s*%\s*([A-Za-z0-9_\.]+)'),
      (Match match) => 'fmod(${match.group(1)}, ${match.group(2)})',
    );
    return result;
  }

  String _rewriteMatrixCasts(String line) {
    return line.replaceAll(
      RegExp(r'\(\s*(?:const\s+)?float3x3\s*\)\s*uniforms\.ModelMatrix'),
      'float3x3(uniforms.ModelMatrix[0].xyz, uniforms.ModelMatrix[1].xyz, uniforms.ModelMatrix[2].xyz)',
    );
  }

  String _rewritePreprocessor(String line) {
    String result =
        line.replaceAllMapped(RegExp(r'!?%[A-Za-z0-9_]+'), (Match match) {
      final String token = match.group(0)!;
      final bool negated = token.startsWith('!');
      final String name = token.substring(negated ? 2 : 1);
      final String replacement = 'defined($name)';
      return negated ? '!$replacement' : replacement;
    });
    result = result.replaceAll(
      RegExp(r'#\s*ifdef\s+D3D', caseSensitive: false),
      '#if 1',
    );
    result = result.replaceAll(
      RegExp(r'#\s*ifndef\s+D3D', caseSensitive: false),
      '#if 0',
    );
    result = result.replaceAll(
      RegExp(r'#\s*ifdef\s+OPENGL', caseSensitive: false),
      '#if 0',
    );
    result = result.replaceAll(
      RegExp(r'#\s*ifndef\s+OPENGL', caseSensitive: false),
      '#if 1',
    );
    result = result.replaceAll(
      RegExp(r'#\s*ifdef\s+_ps_1_1', caseSensitive: false),
      '#if 0',
    );
    result = result.replaceAll(
      RegExp(r'#\s*if\s+defined\s*\(\s*_ps_1_1\s*\)',
          caseSensitive: false),
      '#if 0',
    );
    result = result.replaceAll(
      RegExp(r'#\s*elif\s+defined\s*\(\s*_ps_1_1\s*\)',
          caseSensitive: false),
      '#elif 0',
    );
    return result;
  }

  String _outputType(String field) => data.outputFieldTypes[field] ?? 'float4';

  String _zeroValueForType(String type) {
    final String lower = type.toLowerCase();
    if (lower == 'float' || lower == 'half') {
      return '0.0';
    }
    if (lower == 'int' || lower == 'uint') {
      return '0';
    }
    if (lower == 'bool') {
      return 'false';
    }
    if (lower.endsWith('2') || lower.endsWith('3') || lower.endsWith('4')) {
      return '$type(0.0)';
    }
    return '$type(0.0)';
  }

  void _buildBodyFromFlow(List<List<String>> expressionBatches) {
    body.clear();
    int currentIndent = 0;
    int batchIndex = 0;
    for (final Map<String, dynamic> entry in data.coreFlow) {
      final int indent = (entry['indent'] as int?) ?? 0;
      while (currentIndent > indent) {
        currentIndent -= 1;
        body.add('${'  ' * (indent + 1)}}');
      }
      final String? content = entry['content'] as String?;
      if (content != null && content.isNotEmpty) {
        if (batchIndex < expressionBatches.length) {
          final List<String> lines = expressionBatches[batchIndex++];
          for (final String line in lines) {
            body.add('${'  ' * (indent + 1)}$line');
          }
        }
      }
      final bool opensBlock = entry['opensBlock'] as bool? ?? false;
      if (opensBlock) {
        body.add('${'  ' * (indent + 1)}{');
        currentIndent += 1;
      }
    }
    while (currentIndent > 0) {
      currentIndent -= 1;
      body.add('${'  ' * (currentIndent + 1)}}');
    }
    while (batchIndex < expressionBatches.length) {
      for (final String line in expressionBatches[batchIndex++]) {
        body.add('  $line');
      }
    }
  }

  bool _canReplicateBase(String expression) {
    final String trimmed = expression.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (_numericLiteralPattern.hasMatch(trimmed)) {
      return true;
    }
    if (_identifierPattern.hasMatch(trimmed)) {
      if (_scalarVariables.contains(trimmed)) {
        return true;
      }
      if (_scalarUniforms.contains(trimmed)) {
        return true;
      }
      return false;
    }
    if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
      return _canReplicateBase(trimmed.substring(1, trimmed.length - 1));
    }
    if (trimmed.contains('.') && !trimmed.contains('(')) {
      return false;
    }
    return true;
  }

  bool _isScalarType(String type) {
    final String lower = type.toLowerCase();
    switch (lower) {
      case 'float':
      case 'half':
      case 'int':
      case 'uint':
      case 'bool':
        return true;
      default:
        return false;
    }
  }

  String _rewriteLine(String line) {
    if (line.trimLeft().startsWith('#')) {
      return '';
    }
    String result = _replaceInlineMacros(line);
    for (final LineTransformer transformer in _transformers) {
      result = transformer.transform(result);
    }
    result = _normalizeScalarComponents(result);
    result = _normalizeModuloLiterals(result);
    result = _rewriteMatrixCasts(result);
    result = result.replaceAll(
      'uniforms.BaseTexGen0;',
      'uniforms.BaseTexGen0.xyz;',
    );
    result = result.replaceAll(
      'uniforms.BaseTexGen1;',
      'uniforms.BaseTexGen1.xyz;',
    );
    result = result.replaceAll(
      'uniforms.Normal;',
      'uniforms.Normal.xyz;',
    );
    return result;
  }

  bool usesIdentifier(String identifier) {
    final RegExp pattern = RegExp(
      r'(?<![A-Za-z0-9_])' + RegExp.escape(identifier) + r'(?![A-Za-z0-9_])',
    );
    if (body.any((line) => pattern.hasMatch(line))) {
      return true;
    }
    if (prologue.any((line) => pattern.hasMatch(line))) {
      return true;
    }
    return false;
  }

  List<String>? _expandMacro(String line) {
    final List<String>? expansion = _macroExpansions[line];
    if (expansion == null) {
      return null;
    }
    return expansion;
  }

  static final Map<String, List<String>> _macroExpansions =
      <String, List<String>>{
        'TANG_MATR': <String>[
          'float3x3 objToTangentSpace;',
          'objToTangentSpace[0] = IN.Tangent;',
          'objToTangentSpace[1] = IN.Binormal;',
          'objToTangentSpace[2] = IN.TNormal;',
        ],
      };

  String _replaceInlineMacros(String line) {
    String result = line;
    _inlineMacroReplacements.forEach((String macro, String replacement) {
      if (result.contains(macro)) {
        result = result.replaceAll(macro, replacement);
      }
    });
    result = result.replaceAllMapped(
      RegExp(
        r'mul\(\s*\((?:const\s+)?float3x3\)\s*([A-Za-z0-9_\.]+)\s*,\s*([A-Za-z0-9_\.\[\]]+)\s*\)',
      ),
      (Match match) {
        final String matrixExpr = match.group(1)!.trim();
        final String vectorExpr = match.group(2)!.trim();
        final String replacement =
            '(float3x3(float3(${matrixExpr}[0].xyz), float3(${matrixExpr}[1].xyz), float3(${matrixExpr}[2].xyz)) * (${vectorExpr}))';
        return replacement;
      },
    );
    result = result.replaceAll(
      'OUT.Color.w = IN.Color;',
      'OUT.Color.w = IN.Color.w;',
    );
    result = _expandScalarReplicates(result);
    result = result.replaceAllMapped(
      RegExp(r',\s*0\)'),
      (Match match) => ', 0.0)',
    );
    result = result.replaceAllMapped(
      RegExp(r',\s*1\)'),
      (Match match) => ', 1.0)',
    );
    return result;
  }

  static final Map<String, String> _inlineMacroReplacements = <String, String>{
    'PROC_ATTENPIX':
        '(lightVec * (uniforms.AttenInfo.y * uniforms.AttenInfo.z) + uniforms.AttenInfo.z)',
    'PROC_ATTENVERT':
        '((uniforms.AttenInfo.x - 1.0 / fiSqDist) * uniforms.AttenInfo.y)',
  };

  String _expandScalarReplicates(String source) {
    String result = source;
    int searchStart = 0;
    while (true) {
      final int dotIndex = result.indexOf('.', searchStart);
      if (dotIndex == -1) {
        break;
      }
      final int swizzleStart = dotIndex + 1;
      if (swizzleStart >= result.length) {
        break;
      }
      final String component = result[swizzleStart];
      if (component != 'x') {
        searchStart = swizzleStart;
        continue;
      }
      int length = 1;
      while (swizzleStart + length < result.length &&
          result[swizzleStart + length] == component) {
        length++;
      }
      if (length < 2 || length > 4) {
        searchStart = swizzleStart;
        continue;
      }
      final _ExpressionSlice? slice = _extractExpressionSlice(result, dotIndex);
      if (slice == null) {
        searchStart = swizzleStart;
        continue;
      }
      final String expression = result.substring(slice.start, slice.end).trim();
      if (!_canReplicateBase(expression)) {
        searchStart = swizzleStart;
        continue;
      }
      final String constructor = 'float$length';
      final String prefix = result.substring(0, slice.start);
      final String suffix = result.substring(swizzleStart + length);
      result = '$prefix$constructor($expression)$suffix';
      searchStart = prefix.length + constructor.length + 1 + expression.length;
    }
    result = result.replaceAllMapped(RegExp(r'\(([^)]+)\)\.([xyzw]{2,4})'), (
      Match match,
    ) {
      final String expression = match.group(1)!.trim();
      final int length = match.group(2)!.length;
      final String constructor = 'float$length';
      return '$constructor($expression)';
    });
    return result;
  }

  _ExpressionSlice? _extractExpressionSlice(String source, int dotIndex) {
    int cursor = dotIndex - 1;
    while (cursor >= 0 && source[cursor].trim().isEmpty) {
      cursor--;
    }
    if (cursor < 0) {
      return null;
    }
    if (source[cursor] == ')') {
      int depth = 1;
      cursor--;
      while (cursor >= 0 && depth > 0) {
        final String char = source[cursor];
        if (char == ')') {
          depth++;
        } else if (char == '(') {
          depth--;
        }
        cursor--;
      }
      final int start = cursor + 1;
      int includeStart = start;
      int look = start - 1;
      while (look >= 0 && source[look].trim().isEmpty) {
        look--;
      }
      while (look >= 0 && _FunctionCallUtils._isIdentifierChar(source[look])) {
        look--;
      }
      includeStart = look + 1;
      return _ExpressionSlice(includeStart, dotIndex);
    }
    if (source[cursor] == ']') {
      int depth = 1;
      cursor--;
      while (cursor >= 0 && depth > 0) {
        final String char = source[cursor];
        if (char == ']') {
          depth++;
        } else if (char == '[') {
          depth--;
        }
        cursor--;
      }
      int start = cursor;
      while (start >= 0 &&
          _FunctionCallUtils._isIdentifierChar(source[start])) {
        start--;
      }
      return _ExpressionSlice(start + 1, dotIndex);
    }
    int start = cursor;
    while (start >= 0) {
      final String char = source[start];
      if (_FunctionCallUtils._isIdentifierChar(char) || char == '.') {
        start--;
        continue;
      }
      break;
    }
    return _ExpressionSlice(start + 1, dotIndex);
  }
}

class _ExpressionSlice {
  _ExpressionSlice(this.start, this.end);

  final int start;
  final int end;
}

class _ConditionalFrame {
  _ConditionalFrame({
    required this.skipInstancing,
    required this.skipping,
  });

  final bool skipInstancing;
  bool skipping;
}

abstract class LineTransformer {
  String transform(String line);
}

class ComputeLightVectorsTransformer implements LineTransformer {
  @override
  String transform(String line) {
    if (!line.contains('ComputeLightVectors')) {
      return line;
    }
    return [
      'float3 _lightVectorTemp = uniforms.LightPos.xyz - vPos.xyz;',
      'float LightDistance = length(_lightVectorTemp);',
      'LightDirection = _lightVectorTemp / LightDistance;',
      'ViewDirection = normalize(uniforms.CameraPos.xyz - vPos.xyz);',
      'HalfVector = normalize(ViewDirection + LightDirection);'
    ].join('\n');
  }
}

class FloatMacroTransformer implements LineTransformer {
  @override
  String transform(String line) {
    String result = line;
    result = result.replaceAllMapped(
      RegExp(r'\bFLOAT([234])x([234])\b'),
      (Match match) => 'float${match.group(1)}x${match.group(2)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bFLOAT([234])\b'),
      (Match match) => 'float${match.group(1)}',
    );
    result = result.replaceAll(RegExp(r'\bFLOAT\b'), 'float');
    return result;
  }
}

class ZeroCastTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(
        r'(float[234])\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\(float[234]\)\s*0(?:\.0+)?;',
      ),
      (Match match) => '${match.group(1)} ${match.group(2)} = ${match.group(1)}(0.0);',
    );
  }
}

class HalfTypeTransformer implements LineTransformer {
  @override
  String transform(String line) {
    String result = line;
    result = result.replaceAllMapped(
      RegExp(r'\bhalf([234])x([234])\b'),
      (Match match) => 'float${match.group(1)}x${match.group(2)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bhalf([234])\b'),
      (Match match) => 'float${match.group(1)}',
    );
    result = result.replaceAll(RegExp(r'\bhalf\b'), 'float');
    return result;
  }
}

class HdrEncodeAmbTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'HDREncodeAmb\s*\(([^)]+)\)'),
      (Match match) => match.group(1)!,
    );
  }
}

class HdrEncodeTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'HDREncode\s*\(([^)]+)\)'),
      (Match match) => match.group(1)!,
    );
  }
}

class HdrFogBlendTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'HDRFogBlend\s*\(([^,]+),\s*([^,]+),\s*([^)]+)\)'),
      (Match match) =>
          'mix(${match.group(3)}, ${match.group(1)}, clamp(${match.group(2)}, 0.0, 1.0))',
    );
  }
}

class ExpandFunctionTransformer implements LineTransformer {
  @override
  String transform(String line) {
    String result = line.replaceAllMapped(
      RegExp(r'EXPAND\s*\(([^)]+)\)'),
      (Match match) => '(2.0 * (${match.group(1)}) - 1.0)',
    );
    result = result.replaceAllMapped(
      RegExp(r'EXPANDfloat3\s*\(([^)]+)\)'),
      (Match match) => '(2.0 * (${match.group(1)}) - 1.0).xyz',
    );
    result = result.replaceAllMapped(
      RegExp(r'EXPANDfloat4\s*\(([^)]+)\)'),
      (Match match) => '(2.0 * (${match.group(1)}) - 1.0)',
    );
    return result;
  }
}

class Tex2DProjTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'tex2Dproj\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([^)]+)\)'),
      (Match match) {
        final String texture = match.group(1)!;
        final String coord = match.group(2)!.trim();
        final String denominator =
            RegExp(r'\.xyw\b').hasMatch(coord) ? '(${coord}).z' : '(${coord}).w';
        return '$texture.sample(${texture}Sampler, (${coord}).xy / $denominator)';
      },
    );
  }
}

class Tex2DFloat2Transformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'tex2Dfloat2\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([^)]+)\)'),
      (Match match) =>
          '${match.group(1)}.sample(${match.group(1)}Sampler, ${match.group(2)}).xy',
    );
  }
}

class TexCubeFloat3Transformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'texCUBEfloat3\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([^)]+)\)'),
      (Match match) =>
          '${match.group(1)}.sample(${match.group(1)}Sampler, ${match.group(2)}).xyz',
    );
  }
}

class VectorSuffixCleanupTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(
        r'(uniforms\.(?:BumpScale|Ambient|Specular|ReflectAmount|GlobalFogColor|WaterColor))\.xyz\.([wa])',
      ),
      (Match match) => '${match.group(1)}.${match.group(2)}',
    ).replaceAll('.xyz.xyz', '.xyz').replaceAllMapped(
      RegExp(r'([A-Za-z_][A-Za-z0-9_]*\.xyz)\.xyz'),
      (Match match) => match.group(1)!,
    );
  }
}

class ScalarSampleTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'\bfloat\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*\.sample\([^;]+\));'),
      (Match match) => 'float ${match.group(1)} = ${match.group(2)}.x;',
    );
  }
}

class Float4ProductReducerTransformer implements LineTransformer {
  final Set<String> _float4Variables = <String>{};

  @override
  String transform(String line) {
    for (final Match match
        in RegExp(r'\bfloat4\s+([A-Za-z_][A-Za-z0-9_]*)').allMatches(line)) {
      _float4Variables.add(match.group(1)!);
    }
    String result = line.replaceAllMapped(
      RegExp(r'(float3\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*\*)'),
      (Match match) {
        final String identifier = match.group(2)!;
        if (!_float4Variables.contains(identifier)) {
          return match.group(0)!;
        }
        return '${match.group(1)}${identifier}.xyz${match.group(3)}';
      },
    );
    result = result.replaceAllMapped(
      RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+);'),
      (Match match) {
        final String name = match.group(1)!;
        if (!_float4Variables.contains(name)) {
          return match.group(0)!;
        }
        final String rhs = match.group(2)!.trim();
        if (!_looksLikeVector3(rhs)) {
          return match.group(0)!;
        }
        final String prefix = match.input.substring(0, match.start);
        if (prefix.trim().isNotEmpty) {
          return match.group(0)!;
        }
        return '${name}.xyz = $rhs;';
      },
    );
    result = result.replaceAllMapped(
      RegExp(
        r'(float[234]?|half[234]?|float|half)\s+([A-Za-z_][A-Za-z0-9_]*\.xyz\s*=)',
      ),
      (Match match) => match.group(2)!,
    );
    return result;
  }

  bool _looksLikeVector3(String expression) {
    if (expression.contains('float4')) {
      return false;
    }
    return expression.contains('.xyz') ||
        expression.contains('.rgb') ||
        expression.contains('float3') ||
        expression.contains('mix(') ||
        expression.contains('lerp(');
  }
}

class VFinalColorDeclarationTransformer implements LineTransformer {
  @override
  String transform(String line) {
    if (line.contains('vFinalColor')) {
      return line.replaceFirst(
        RegExp(r'\bfloat4\s+vFinalColor\s*=\s*float4\('),
        'float3 vFinalColor = float3(',
      );
    }
    return line;
  }
}

class VFinalColorFinalAssignmentTransformer implements LineTransformer {
  @override
  String transform(String line) {
    final String trimmed = line.trimLeft();
    if (trimmed.startsWith('float3 vFinalColor') ||
        trimmed.startsWith('float4 vFinalColor')) {
      return line;
    }
    if (line.contains('vFinalColor=tapBlured')) {
      return line.replaceFirst(
        'vFinalColor=',
        'float3 vFinalColor = ',
      );
    }
    return line;
  }
}

class FinalColorAssignmentTransformer implements LineTransformer {
  @override
  String transform(String line) {
    final String trimmed = line.trimLeft();
    if (trimmed.startsWith('float') || trimmed.startsWith('half')) {
      return line;
    }
    if (line.contains('vFinalColor=')) {
      return line.replaceAll('vFinalColor=', 'vFinalColor.xyz = ');
    }
    return line;
  }
}

class VFinalColorAssignmentTransformer implements LineTransformer {
  @override
  String transform(String line) {
    final String trimmed = line.trimLeft();
    if (RegExp(r'^(float|half)').hasMatch(trimmed)) {
      return line;
    }
    return line.replaceAllMapped(
      RegExp(r'\bvFinalColor\s*='),
      (Match match) => 'vFinalColor.xyz =',
    );
  }
}

class VectorSampleTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'\bfloat3\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*\.sample\([^;]+\));'),
      (Match match) => 'float3 ${match.group(1)} = ${match.group(2)}.xyz;',
    );
  }
}

class ScalarBroadcastTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'(\b[A-Za-z_][A-Za-z0-9_]*\.rgb\s*/=\s*)\(([^+]+)\+([^)]+)\)'),
      (Match match) {
        final String prefix = match.group(1)!;
        final String scalar = match.group(2)!.trim();
        final String vector = match.group(3)!.trim();
        final String vectorSuffix =
            vector == prefix.substring(0, prefix.indexOf('.')) ? '$vector.rgb' : vector;
        return '$prefix(float3($scalar) + $vectorSuffix)';
      },
    );
  }
}

class ImplicitVectorDeclarationTransformer implements LineTransformer {
  @override
  String transform(String line) {
    final String trimmed = line.trim();
    if (trimmed.startsWith('amb = ') && !trimmed.contains('amb = amb')) {
      final int equalsIndex = line.indexOf('amb = ');
      final String rhs = line.substring(equalsIndex + 'amb = '.length).trim();
      if (!rhs.startsWith('amb') && !rhs.contains(' amb')) {
        return line.replaceFirst('amb = ', 'float3 amb = ');
      }
    }
    return line;
  }
}

class ScalarSwizzleCleanupTransformer implements LineTransformer {
  ScalarSwizzleCleanupTransformer(this.scalarInputs);

  final Set<String> scalarInputs;
  final Set<String> _scalarVariables = <String>{};

  @override
  String transform(String line) {
    for (final Match match
        in RegExp(r'\bfloat\s+([A-Za-z_][A-Za-z0-9_]*)').allMatches(line)) {
      _scalarVariables.add(match.group(1)!);
    }
    String result = line.replaceAllMapped(
      RegExp(
        r'(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\.(?:xyz|[rgb])',
      ),
      (Match match) {
        final String name = match.group(1)!;
        if (_scalarVariables.contains(name)) {
          return name;
        }
        return match.group(0)!;
      },
    );
    result = result.replaceAllMapped(
      RegExp(r'IN\.([A-Za-z_][A-Za-z0-9_]*)\.(?:x|r)'),
      (Match match) {
        final String field = match.group(1)!;
        if (scalarInputs.contains(field)) {
          return 'IN.$field';
        }
        return match.group(0)!;
      },
    );
    return result;
  }
}

class ColorComponentAssignmentTransformer implements LineTransformer {
  ColorComponentAssignmentTransformer(this.uniformTypes);

  final Map<String, String> uniformTypes;
  final Map<String, String> _variableTypes = <String, String>{};

  @override
  String transform(String line) {
    _recordTypes(line);
    return line.replaceAllMapped(
      RegExp(
        r'(OUT\.Color\.xyz\s*=\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*;)',
      ),
      (Match match) {
        final String rhs = match.group(2)!;
        final String? type = _variableTypes[rhs];
        if (type == 'float4') {
          return '${match.group(1)}${rhs}.xyz${match.group(3)}';
        }
        if (type == 'float3') {
          return match.group(0)!;
        }
        if (type == 'float') {
          return '${match.group(1)}float3(${rhs})${match.group(3)}';
        }
        return match.group(0)!;
      },
    ).replaceAllMapped(
      RegExp(
        r'(OUT\.Color\.xyz\s*=\s*)([^;]+)(;)',
      ),
      (Match match) {
        String expression = match.group(2)!;
        expression = _applyFloat4Reductions(expression);
        return '${match.group(1)}$expression${match.group(3)}';
      },
    );
  }

  String _applyFloat4Reductions(String expression) {
    String result = expression;
    _variableTypes.forEach((String name, String type) {
      if (type == 'float4') {
        result = result.replaceAllMapped(
          RegExp(
            r'(?<![A-Za-z0-9_])' + RegExp.escape(name) + r'(?![A-Za-z0-9_\.])',
          ),
          (Match match) => '${match.group(0)}.xyz',
        );
      }
    });
    uniformTypes.forEach((String name, String type) {
      if (type.toLowerCase() == 'float4') {
        result = result.replaceAllMapped(
          RegExp('uniforms\\.' + RegExp.escape(name) + r'(?![A-Za-z0-9_])'),
          (Match match) {
            final int end = match.end;
            if (end < result.length && result[end] == '.') {
              return match.group(0)!;
            }
            return '${match.group(0)}.xyz';
          },
        );
        result = result.replaceAllMapped(
          RegExp(
            r'(?<![A-Za-z0-9_])' + RegExp.escape(name) + r'(?![A-Za-z0-9_\.])',
          ),
          (Match match) => '${match.group(0)}.xyz',
        );
      }
    });
    if (_variableTypes['vFinalColor'] == 'float4') {
      result = result.replaceAllMapped(
        RegExp(r'\bvFinalColor\s*(?==)'),
        (Match match) => 'vFinalColor.xyz',
      );
    }
    return result;
  }

  void _recordTypes(String line) {
    for (final Match match
        in RegExp(r'\bfloat([234]?)\s+([A-Za-z_][A-Za-z0-9_]*)')
            .allMatches(line)) {
      final String size = match.group(1) ?? '';
      final String name = match.group(2)!;
      final String type = size.isEmpty ? 'float' : 'float$size';
      _variableTypes[name] = type;
    }
  }
}

class ColorAliasTransformer implements LineTransformer {
  @override
  String transform(String line) {
    final String trimmed = line.trim();
    if (trimmed == 'OUT.Color = color;') {
      return '';
    }
    return line.replaceAll(RegExp(r'\bcolor\.'), 'OUT.Color.');
  }
}

class OutColorUniformReducer implements LineTransformer {
  OutColorUniformReducer(this.uniformTypes);

  final Map<String, String> uniformTypes;

  @override
  String transform(String line) {
    if (!line.contains('OUT.Color.xyz')) {
      return line;
    }
    return line.replaceAllMapped(
      RegExp(r'uniforms\.([A-Za-z_][A-Za-z0-9_]*)'),
      (Match match) {
        final String name = match.group(1)!;
        final String? type = uniformTypes[name];
        if (type == null || type.toLowerCase() != 'float4') {
          return match.group(0)!;
        }
        final int end = match.end;
        if (end < line.length && line[end] == '.') {
          return match.group(0)!;
        }
        return '${match.group(0)}.xyz';
      },
    );
  }
}

class LuminosityDifFixupTransformer implements LineTransformer {
  @override
  String transform(String line) {
    if (!line.contains('dif.r*0.33')) {
      return line;
    }
    return line.replaceAll(
      RegExp(
        r'dif\.r\*0\.33\s*\+\s*dif\.g\*0\.59\s*\+\s*dif\.b\*0\.11',
      ),
      'dot(decalColor.xyz, float3(0.33, 0.59, 0.11))',
    );
  }
}

class BumpPlantsFixupTransformer implements LineTransformer {
  bool _hasFDif = false;
  bool _plantBlockPending = false;
  bool _plantBlockRewritten = false;

  @override
  String transform(String line) {
    String result = line;
    if (result.contains('float fDif')) {
      _hasFDif = true;
    }
    if (result.contains('DiffuseSun')) {
      _plantBlockPending = true;
    }
    if (_plantBlockPending &&
        !_plantBlockRewritten &&
        result.contains(
            'dif = (decalColor.xyz * projColor.xyz * uniforms.Diffuse.xyz * IN.Color.xyz) * 2;')) {
      _plantBlockRewritten = true;
      return '  dif = NdotL * IN.Color.a * projColor.xyz * uniforms.Diffuse.xyz;\n'
          '  float3 lightVecSun = 2.0 * (IN.Color1.xyz - 0.5);\n'
          '  float fDifSun = clamp(dot(bumpNormal.xyz, lightVecSun), 0.0, 1.0);\n'
          '  float3 difSun = fDifSun * uniforms.DiffuseSun.xyz;';
    }
    if (_plantBlockPending &&
        _plantBlockRewritten &&
        result.contains(
            'dif = (decalColor.xyz * projColor.xyz * uniforms.Diffuse.xyz * IN.Color.xyz) * 2;')) {
      return '';
    }
    if (result.contains('float3 dif = (')) {
      result = result.replaceFirst(
        RegExp(r'float3 dif = \(.*'),
        'float3 dif = decalColor.xyz * NdotL * uniforms.Diffuse.xyz;',
      );
    }
    result = result.replaceAll('decalColor.xyz.xyz', 'decalColor.xyz');
    final String trimmed = result.trim();
    if (trimmed == 'dif = dif;' || trimmed == 'amb = amb;') {
      return '';
    }
    if (_hasFDif &&
        !_plantBlockPending &&
        result.contains('decalColor.xyz * NdotL * uniforms.Diffuse.xyz')) {
      result = result.replaceFirst(
        'decalColor.xyz * NdotL * uniforms.Diffuse.xyz',
        'decalColor.xyz * fDif * uniforms.Diffuse.xyz',
      );
    }
    return result;
  }
}

class DifZeroInitCleanupTransformer implements LineTransformer {
  @override
  String transform(String line) {
    if (line.trimLeft().startsWith('float3 dif = float3(0.0);')) {
      return '';
    }
    return line;
  }
}

class BrushedMetalFixupTransformer implements LineTransformer {
  bool _hasNdotLTexture = false;

  @override
  String transform(String line) {
    if (line.contains('NdotL_NdotH')) {
      _hasNdotLTexture = true;
    }
    if (_hasNdotLTexture &&
        line.contains('float3 dif') &&
        line.contains('NdotL') &&
        line.contains('uniforms.Diffuse')) {
      return '  float3 dif = (uniforms.Diffuse.xyz * NdotL_NdotH.xyz * decalColor.xyz) * 2;';
    }
    return line;
  }
}

class ShadowProjFixupTransformer implements LineTransformer {
  bool _hasProjColor = false;

  @override
  String transform(String line) {
    if (line.contains('projColor =')) {
      _hasProjColor = true;
    }
    if (_hasProjColor &&
        line.contains('float3 dif') &&
        line.contains('uniforms.Diffuse')) {
      return '  float3 dif = (decalColor.xyz * projColor.xyz * uniforms.Diffuse.xyz * IN.Color.xyz) * 2;';
    }
    return line;
  }
}

class HdrOutputTransformer implements LineTransformer {
  @override
  String transform(String line) {
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < line.length) {
      if (_FunctionCallUtils.matches(line, index, 'HDROutput')) {
        final _FunctionCall? call = _FunctionCallUtils.parse(line, index);
        if (call != null && call.args.length >= 3) {
          final String target = call.args[0].trim();
          final String colorExpr = call.args[1].trim();
          String alphaExpr = call.args[2].trim();
          if (RegExp(r'^\d+$').hasMatch(alphaExpr)) {
            alphaExpr = '${alphaExpr}.0';
          }
          buffer.write(
            '$target.Color = float4((${colorExpr}).xyz, $alphaExpr);',
          );
          int nextIndex = call.endIndex;
          if (nextIndex < line.length && line[nextIndex] == ';') {
            nextIndex++;
          }
          index = nextIndex;
          continue;
        }
      }
          buffer.write(line[index]);
          index++;
    }
    return buffer.toString();
  }
}

class VectorMultiplyCleanupTransformer implements LineTransformer {
  @override
  String transform(String line) {
    String result = line;
    final RegExp float4ToFloat3 = RegExp(
      r'float4\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^\n;]+?)\.xyz\s*;',
      dotAll: true,
    );
    result = result.replaceAllMapped(
      float4ToFloat3,
      (Match match) => 'float3 ${match.group(1)} = ${match.group(2)}.xyz;',
    );
    result = result.replaceAllMapped(
      RegExp(r'(float3\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*)([A-Za-z_][A-Za-z0-9_]*)\s*\*\s*([A-Za-z_][A-Za-z0-9_]*\.xyz);'),
      (Match match) => '${match.group(1)}${match.group(2)}.xyz * ${match.group(3)};',
    );
    result = result.replaceAll(
      'uniforms.WaterColor.xyz * env',
      'uniforms.WaterColor * env',
    );
    result = result.replaceAll(
      'env * uniforms.WaterColor.xyz',
      'env * uniforms.WaterColor',
    );
    result = result.replaceAllMapped(
      RegExp(r'reflColor\s*\*'),
      (Match match) => match.group(0)!.contains('.xyz')
          ? match.group(0)!
          : match.group(0)!.replaceFirst('reflColor', 'reflColor.xyz'),
    );
    result = result.replaceAllMapped(
      RegExp(r'refrColor\s*\*\s*uniforms\.RefrColor'),
      (Match match) => '(refrColor * uniforms.RefrColor).xyz',
    );
    result = result.replaceAllMapped(
      RegExp(r'uniforms\.RefrColor\s*\*\s*refrColor'),
      (Match match) => '(uniforms.RefrColor * refrColor).xyz',
    );
    result = result.replaceAll('atten.xyz', 'atten');
    result = result.replaceAll(
      'uniforms.Ambient.xyz * decalColor',
      'uniforms.Ambient.xyz * decalColor.xyz',
    );
    result = result.replaceAll(
      'decalColor * uniforms.Ambient.xyz',
      'decalColor.xyz * uniforms.Ambient.xyz',
    );
    final RegExp float4Projection = RegExp(
      r'(float4\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*\([^;]+?)\s*\.xyz\s*;',
      dotAll: true,
    );
    result = result.replaceAllMapped(
      float4Projection,
      (Match match) => '${match.group(1)};',
    );
    result = result.replaceAllMapped(
      RegExp(r'tableColor\s*\*\s*fLum\s*\*\s*fNoiseLum'),
      (Match match) => '(tableColor.xyz * fLum * fNoiseLum)',
    );
    result = result.replaceAllMapped(
      RegExp(r'(float3\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*)2\*\(([^;]+)\)'),
      (Match match) => '${match.group(1)}(2.0 * (${match.group(2)})).xyz',
    );
    result = result.replaceAll(
      'IN.Color.xyz*vSubSurfaceColor',
      'IN.Color.xyz * vSubSurfaceColor.xyz',
    );
    return result;
  }
}

class NightVisionVectorCleanupTransformer implements LineTransformer {
  @override
  String transform(String line) {
    if (!line.trim().startsWith('float3')) {
      return line;
    }
    String result = line.replaceAllMapped(
      RegExp(r'\bfNoiseColor\b(?!\.)'),
      (Match match) => 'fNoiseColor.xyz',
    );
    result = result.replaceAllMapped(
      RegExp(r'\bfHeatColor\b(?!\.)'),
      (Match match) => 'fHeatColor.xyz',
    );
    return result;
  }
}

class VectorToScalarAccumulationTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAll(
      'fResampleSum += vTex;',
      'fResampleSum += vTex.x;',
    );
  }
}

class DotProductDimensionTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'dot\(\s*(float3\([^)]*\))\s*,\s*([A-Za-z_][A-Za-z0-9_\.]+)\s*\)'),
      (Match match) {
        final String argument = match.group(2)!;
        if (argument.contains('.')) {
          return match.group(0)!;
        }
        return 'dot(${match.group(1)}, ${argument}.xyz)';
      },
    );
  }
}
class NormalizePromotionTransformer implements LineTransformer {
  NormalizePromotionTransformer()
    : _pattern = RegExp(r'(float4\s+[A-Za-z0-9_]+\s*=\s*)normalize\(([^;]+)\)');

  final RegExp _pattern;

  @override
  String transform(String line) {
    return line.replaceAllMapped(_pattern, (Match match) {
      final String prefix = match.group(1)!;
      final String expression = match.group(2)!.trim();
      return '$prefix float4(normalize((${expression}).xyz), 0.0)';
    });
  }
}

class UniformVectorComponentTransformer implements LineTransformer {
  UniformVectorComponentTransformer(this.uniformTypes)
    : _patternLeft = RegExp(
        r'((?:uniforms\.)?(BumpScale|Ambient|Specular|ReflectAmount|GlobalFogColor|WaterColor))\s*\*\s*([A-Za-z0-9_\.]+)',
      ),
      _patternRight = RegExp(
        r'([A-Za-z0-9_\.]+)\s*\*\s*((?:uniforms\.)?(BumpScale|Ambient|Specular|ReflectAmount|GlobalFogColor|WaterColor))',
      );

  final Map<String, String> uniformTypes;
  final RegExp _patternLeft;
  final RegExp _patternRight;

  @override
  String transform(String line) {
    String result = line;
    result = result.replaceAllMapped(_patternLeft, (Match match) {
      final String lhs = match.group(1)!;
      final String baseName = match.group(2)!;
      final String rhs = match.group(3)!;
      if (_hasComponentSuffix(lhs)) {
        return '$lhs * $rhs';
      }
      if (!_requiresVectorSuffix(baseName, rhs)) {
        return '$lhs * $rhs';
      }
      return '${lhs}.xyz * $rhs';
    });
    result = result.replaceAllMapped(_patternRight, (Match match) {
      final String lhs = match.group(1)!;
      final String rhs = match.group(2)!;
      final String baseName = match.group(3)!;
      if (_hasComponentSuffix(rhs)) {
        return '$lhs * $rhs';
      }
      if (!_requiresVectorSuffix(baseName, lhs)) {
        return '$lhs * $rhs';
      }
      return '$lhs * ${rhs}.xyz';
    });
    return result;
  }

  bool _requiresVectorSuffix(String uniformName, String otherOperand) {
    final String? type = uniformTypes[uniformName];
    if (type == null) {
      return false;
    }
    final String lower = type.toLowerCase();
    if (lower == 'float3') {
      return true;
    }
    if (lower == 'float4') {
      return !_prefersFloat4Context(otherOperand);
    }
    return false;
  }

  bool _prefersFloat4Context(String operand) {
    final String normalized = operand.replaceAll(' ', '');
    return normalized.contains('.wwww') ||
        normalized.contains('.xyzw') ||
        normalized.contains('float4(') ||
        normalized.contains('float4');
  }

  bool _hasComponentSuffix(String value) {
    return value.endsWith('.x') ||
        value.endsWith('.y') ||
        value.endsWith('.z') ||
        value.endsWith('.w') ||
        value.endsWith('.a');
  }
}

class UniformFloat4RestoreTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(
        r'(float4\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*)(uniforms\.(?:BumpScale|Ambient|Specular|ReflectAmount|GlobalFogColor|WaterColor))\.xyz',
      ),
      (Match match) => '${match.group(1)}${match.group(2)}',
    );
  }
}

class DotUniformDimensionTransformer implements LineTransformer {
  DotUniformDimensionTransformer(this.uniformTypes);

  final Map<String, String> uniformTypes;

  @override
  String transform(String line) {
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < line.length) {
      if (_FunctionCallUtils.matches(line, index, 'dot')) {
        final _FunctionCall? call = _FunctionCallUtils.parse(line, index);
        if (call != null && call.args.length == 2) {
          final String lhs = call.args[0].trim();
          final String rhs = call.args[1].trim();
          final String adjustedLhs = _adjustUniform(lhs, rhs);
          final String adjustedRhs = _adjustUniform(rhs, lhs);
          buffer.write('dot($adjustedLhs, $adjustedRhs)');
        index = call.endIndex;
        continue;
        }
      }
      buffer.write(line[index]);
      index++;
    }
    return buffer.toString();
  }

  String _adjustUniform(String operand, String other) {
    if (!operand.startsWith('uniforms.')) {
      return operand;
    }
    final int firstDot = operand.indexOf('.');
    if (firstDot == -1) {
      return operand;
    }
    final int secondDot = operand.indexOf('.', firstDot + 1);
    if (secondDot != -1) {
      return operand;
    }
    final String uniformName = operand.substring('uniforms.'.length);
    final String? type = uniformTypes[uniformName];
    if (type == null) {
      return operand;
    }
    final int targetDim = _inferDimension(other);
    final String lower = type.toLowerCase();
    if (targetDim == 4 || lower == 'float4' && targetDim == 0) {
      return operand;
    }
    if (targetDim == 3 || (targetDim == 0 && lower == 'float4')) {
      return '$operand.xyz';
    }
    if (targetDim == 2) {
      return '$operand.xy';
    }
    if (targetDim == 1) {
      return '$operand.x';
    }
    if (lower == 'float3') {
      return operand;
    }
    return operand;
  }

  int _inferDimension(String expression) {
    final String normalized = expression.replaceAll(' ', '');
    if (normalized.contains('.xyzw') ||
        normalized.contains('.rgba') ||
        normalized.contains('float4(')) {
      return 4;
    }
    if (normalized.contains('.xyz') ||
        normalized.contains('.rgb') ||
        normalized.contains('float3(')) {
      return 3;
    }
    if (normalized.contains('.xy') ||
        normalized.contains('.rg') ||
        normalized.contains('float2(')) {
      return 2;
    }
    if (normalized.contains('.x') ||
        normalized.contains('.r')) {
      return 1;
    }
    return 0;
  }
}

class DotUniformSuffixFixupTransformer implements LineTransformer {
  @override
  String transform(String line) {
    String result = line;
    result = result.replaceAllMapped(
      RegExp(
        r'dot\(\s*(uniforms\.[A-Za-z0-9_]+)\s*,\s*([^\),]+)\s*\)',
      ),
      (Match match) {
        final String lhs = match.group(1)!.trim();
        final String rhs = match.group(2)!.trim();
        if (!_needsVectorReduction(rhs)) {
          return match.group(0)!;
        }
        if (_hasSwizzle(lhs)) {
          return match.group(0)!;
        }
        return 'dot(${lhs}.xyz, $rhs)';
      },
    );
    result = result.replaceAllMapped(
      RegExp(
        r'dot\(\s*([^\),]+)\s*,\s*(uniforms\.[A-Za-z0-9_]+)\s*\)',
      ),
      (Match match) {
        final String lhs = match.group(1)!.trim();
        final String rhs = match.group(2)!.trim();
        if (!_needsVectorReduction(lhs)) {
          return match.group(0)!;
        }
        if (_hasSwizzle(rhs)) {
          return match.group(0)!;
        }
        return 'dot($lhs, ${rhs}.xyz)';
      },
    );
    return result;
  }

  bool _needsVectorReduction(String operand) {
    final String normalized = operand.replaceAll(' ', '');
    return normalized.contains('.xyz') ||
        normalized.contains('.rgb') ||
        normalized.contains('.xy') ||
        normalized.contains('.rg') ||
        normalized.contains('float3(') ||
        normalized.contains('float2(');
  }

  bool _hasSwizzle(String operand) {
    final int firstDot = operand.indexOf('.');
    if (firstDot == -1) {
      return false;
    }
    final int secondDot = operand.indexOf('.', firstDot + 1);
    return secondDot != -1;
  }
}

class DotVariableDimensionTransformer implements LineTransformer {
  final Map<String, String> _variableTypes = <String, String>{};

  @override
  String transform(String line) {
    final RegExp declarationPattern =
        RegExp(r'\bfloat([234]?)\s+([A-Za-z_][A-Za-z0-9_]*)');
    for (final Match match in declarationPattern.allMatches(line)) {
      final String size = match.group(1)!;
      final String name = match.group(2)!;
      final String type = size.isEmpty ? 'float' : 'float$size';
      _variableTypes[name] = type;
    }
    return line.replaceAllMapped(
      RegExp(r'dot\(\s*([^\),]+)\s*,\s*([^\),]+)\s*\)'),
      (Match match) {
        final String lhs = match.group(1)!.trim();
        final String rhs = match.group(2)!.trim();
        final String adjustedLhs = _adjustOperand(lhs, rhs);
        final String adjustedRhs = _adjustOperand(rhs, lhs);
        if (lhs == adjustedLhs && rhs == adjustedRhs) {
          return match.group(0)!;
        }
        return 'dot($adjustedLhs, $adjustedRhs)';
      },
    );
  }

  String _adjustOperand(String operand, String other) {
    final String baseName = operand.split(RegExp(r'[\.\s]')).first;
    final String? type = _variableTypes[baseName];
    if (type == null) {
      return operand;
    }
    if (type == 'float4' && !_hasSwizzle(operand) && _expectsThreeComponents(other)) {
      return '$operand.xyz';
    }
    if (type == 'float2' && !_hasSwizzle(operand) && _expectsTwoComponents(other)) {
      return '$operand.xy';
    }
    return operand;
  }

  bool _hasSwizzle(String operand) {
    return operand.contains('.x') ||
        operand.contains('.y') ||
        operand.contains('.z') ||
        operand.contains('.w') ||
        operand.contains('.r') ||
        operand.contains('.g') ||
        operand.contains('.b') ||
        operand.contains('.a');
  }

  bool _expectsThreeComponents(String operand) {
    final String baseName = operand.split(RegExp(r'[\.\s]')).first;
    final String? type = _variableTypes[baseName];
    if (type == null) {
      return operand.contains('.xyz') || operand.contains('.rgb');
    }
    return type == 'float3';
  }

  bool _expectsTwoComponents(String operand) {
    final String baseName = operand.split(RegExp(r'[\.\s]')).first;
    final String? type = _variableTypes[baseName];
    if (type == null) {
      return operand.contains('.xy') || operand.contains('.rg');
    }
    return type == 'float2';
  }
}

class MatrixRowVectorTransformer implements LineTransformer {
  @override
  String transform(String line) {
    String result = line.replaceAllMapped(
      RegExp(r'(?:uniforms\.)?TexProjMatrix\[(\d)\]'),
      (Match match) => 'uniforms.TexProjMatrix[${match.group(1)}].xyz',
    );
    result = result.replaceAll(
      RegExp(r'\?\s*1\s*:\s*(?:uniforms\.)?TexProjMatrix'),
      '? float3(1.0) : uniforms.TexProjMatrix',
    );
    result = result.replaceAllMapped(
      RegExp(r'(float3\s+[A-Za-z0-9_]+\s*=\s*)uniforms\.BaseTexGen([01])'),
      (Match match) =>
          '${match.group(1)}uniforms.BaseTexGen${match.group(2)}.xyz',
    );
    result = result.replaceAll(
      'uniforms.BaseTexGen0;',
      'uniforms.BaseTexGen0.xyz;',
    );
    result = result.replaceAll(
      'uniforms.BaseTexGen1;',
      'uniforms.BaseTexGen1.xyz;',
    );
    if (result.contains('float3 binorm = uniforms.BaseTexGen0;')) {
      result = result.replaceAll(
        'float3 binorm = uniforms.BaseTexGen0;',
        'float3 binorm = uniforms.BaseTexGen0.xyz;',
      );
    }
    if (result.contains('float3 tang = uniforms.BaseTexGen1;')) {
      result = result.replaceAll(
        'float3 tang = uniforms.BaseTexGen1;',
        'float3 tang = uniforms.BaseTexGen1.xyz;',
      );
    }
    if (result.contains('float3 worldNormal = uniforms.Normal;')) {
      result = result.replaceAll(
        'float3 worldNormal = uniforms.Normal;',
        'float3 worldNormal = uniforms.Normal.xyz;',
      );
    }
    result = result.replaceAll(
      'uniforms.Normal;',
      'uniforms.Normal.xyz;',
    );
    result = result.replaceAllMapped(
      RegExp(r'(\.xyz\s*=\s*[^;]*\*\s*)float4\(([^)]+)\)'),
      (Match match) => '${match.group(1)}float3(${match.group(2)})',
    );
    result = result.replaceAllMapped(
      RegExp(r'(\.xyz\s*=\s*)float4\(([^)]+)\)'),
      (Match match) => '${match.group(1)}float3(${match.group(2)})',
    );
    result = result.replaceAll('.xyzz', '.xyz');
    if (result.contains('offsettex2D(') ||
        result.contains('offsettexRECT(') ||
        result.contains('IN.Tex1.xy / IN.Tex1.w') ||
        result.contains('newst = newst +')) {
      return '';
    }
    return result;
  }
}

class CameraVectorTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAllMapped(
      RegExp(r'((?:uniforms\.)?)CameraPos\s*-\s*vPos'),
      (Match match) => '(uniforms.CameraPos - vPos).xyz',
    );
  }
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
      'tex1D',
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
    final String normalizedCoord = _normalizeTextureCoordinate(call.name, coordinate);
    switch (call.name) {
      case 'tex1D':
      case 'tex2D':
      case 'texRECT':
      case 'tex3D':
      case 'texCUBE':
        return '$texture.sample($sampler, $normalizedCoord)';
      case 'tex2Dproj':
        final String projected = '(${coordinate}).xy / (${coordinate}).w';
        return '$texture.sample($sampler, $projected)';
      default:
        return original;
    }
  }
}

String _normalizeTextureCoordinate(String function, String coordinate) {
  if (function != 'texCUBE') {
    return coordinate;
  }
  if (coordinate.contains('float3') || coordinate.contains('.xyz')) {
    return coordinate;
  }
  if (coordinate.contains('.xy')) {
    return 'float3(${coordinate}, 0.0)';
  }
  return coordinate;
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

class ClampTransformer implements LineTransformer {
  @override
  String transform(String line) {
    if (!line.contains('clamp')) {
      return line;
    }
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < line.length) {
      if (_FunctionCallUtils.matches(line, index, 'clamp')) {
        final _FunctionCall? call = _FunctionCallUtils.parse(line, index);
        if (call == null || call.args.length != 3) {
          buffer.write(line[index]);
          index++;
          continue;
        }
        final List<String> normalized = <String>[
          call.args[0].trim(),
          _normalizeClampBound(call.args[1]),
          _normalizeClampBound(call.args[2]),
        ];
        buffer.write('clamp(${normalized.join(', ')})');
        index = call.endIndex;
        continue;
      }
      buffer.write(line[index]);
      index++;
    }
    return buffer.toString();
  }

  String _normalizeClampBound(String arg) {
    final String trimmed = arg.trim();
    if (_integerPattern.hasMatch(trimmed)) {
      return '${trimmed}.0';
    }
    return trimmed;
  }

  static final RegExp _integerPattern = RegExp(r'^-?\d+$');
}

class MinMaxTransformer implements LineTransformer {
  @override
  String transform(String line) {
    if (!line.contains('min') && !line.contains('max')) {
      return line;
    }
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < line.length) {
      final String? match = _matchFunction(line, index);
      if (match == null) {
        buffer.write(line[index]);
        index++;
        continue;
      }
      final _FunctionCall? call = _FunctionCallUtils.parse(line, index);
      if (call == null || call.args.length != 2) {
        buffer.write(line[index]);
        index++;
        continue;
      }
      final List<String> normalized = call.args.map(_normalizeLiteral).toList();
      buffer.write('$match(${normalized.join(', ')})');
      index = call.endIndex;
    }
    return buffer.toString();
  }

  String _normalizeLiteral(String arg) {
    final String trimmed = arg.trim();
    if (_integerPattern.hasMatch(trimmed)) {
      return '${trimmed}.0';
    }
    return trimmed;
  }

  String? _matchFunction(String source, int index) {
    for (final String name in _functionNames) {
      if (_FunctionCallUtils.matches(source, index, name)) {
        return name;
      }
    }
    return null;
  }

  static const List<String> _functionNames = <String>['min', 'max'];
  static final RegExp _integerPattern = RegExp(r'^-?\d+$');
}

class MatrixCastTransformer implements LineTransformer {
  MatrixCastTransformer()
    : _pattern = RegExp(
        r'\(\(\s*(?:const\s+)?float3x3\s*\)\s*([A-Za-z0-9_\.]+)',
      );

  final RegExp _pattern;

  @override
  String transform(String line) {
    if (!line.contains('(float3x3)')) {
      return line;
    }
    return line.replaceAllMapped(_pattern, (Match match) {
      final String expr = match.group(1)!;
      return 'float3x3(float3(${expr}[0].xyz), float3(${expr}[1].xyz), float3(${expr}[2].xyz))';
    });
  }
}

class UniformReferenceTransformer implements LineTransformer {
  UniformReferenceTransformer(Set<String> uniformNames)
    : _patterns = uniformNames
          .where((name) => name.isNotEmpty)
          .map(
            (name) => MapEntry(
              name,
              RegExp(
                '(?<![A-Za-z0-9_\\.])${RegExp.escape(name)}(?![A-Za-z0-9_])',
              ),
            ),
          )
          .toList();

  final List<MapEntry<String, RegExp>> _patterns;

  @override
  String transform(String line) {
    String result = line;
    for (final MapEntry<String, RegExp> entry in _patterns) {
      result = result.replaceAllMapped(entry.value, (Match match) {
        if (_isDeclaration(result, match.start, entry.key.length)) {
          return match.group(0)!;
        }
        return 'uniforms.${entry.key}';
      });
    }
    return result;
  }

  bool _isDeclaration(String line, int start, int length) {
    final int index = start;
    // Look backwards to find previous non-whitespace character.
    int prev = index - 1;
    while (prev >= 0) {
      final String char = line[prev];
      if (char.trim().isEmpty) {
        prev--;
        continue;
      }
      if (char == '.') {
        return true;
      }
      break;
    }
    // Check if characters before form a type declaration (float, half, const, etc).
    const List<String> typePrefixes = <String>[
      'float',
      'half',
      'int',
      'uint',
      'bool',
      'const',
      'long',
      'short',
      'double',
      'matrix',
      'struct',
    ];
    for (final String prefix in typePrefixes) {
      final int prefixIndex = index - prefix.length - 1;
      if (prefixIndex >= 0) {
        final String snippet = line.substring(prefixIndex, index);
        if (snippet == '$prefix ') {
          return true;
        }
      }
    }
    return false;
  }
}

class MulFunctionTransformer implements LineTransformer {
  @override
  String transform(String line) {
    if (!line.contains('mul')) {
      return line;
    }
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < line.length) {
      if (_FunctionCallUtils.matches(line, index, 'mul')) {
        final _FunctionCall? call = _FunctionCallUtils.parse(line, index);
        if (call == null || call.args.length != 2) {
          buffer.write(line[index]);
          index++;
          continue;
        }
        final String left = call.args[0].trim();
        final String right = call.args[1].trim();
        buffer.write('(${left}) * (${right})');
        index = call.endIndex;
        continue;
      }
      buffer.write(line[index]);
      index++;
    }
    return buffer.toString();
  }
}

class LerpTransformer implements LineTransformer {
  @override
  String transform(String line) {
    if (!line.contains('lerp')) {
      return line;
    }
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < line.length) {
      if (_FunctionCallUtils.matches(line, index, 'lerp')) {
        final _FunctionCall? call = _FunctionCallUtils.parse(line, index);
        if (call == null || call.args.length != 3) {
          buffer.write(line[index]);
          index++;
          continue;
        }
        final List<String> args = call.args.map((arg) => arg.trim()).toList();
        buffer.write('mix(${args.join(', ')})');
        index = call.endIndex;
        continue;
      }
      buffer.write(line[index]);
      index++;
    }
    return buffer.toString();
  }
}

class SwizzleAssignmentTransformer implements LineTransformer {
  SwizzleAssignmentTransformer()
    : _pattern = RegExp(
        r'(OUT\.[A-Za-z0-9_]+)\.([xyzw]{1,4})\s*=\s*(IN\.[A-Za-z0-9_]+)\s*;',
      );

  final RegExp _pattern;

  @override
  String transform(String line) {
    return line.replaceAllMapped(_pattern, (Match match) {
      final String destination = match.group(1)!;
      final String swizzle = match.group(2)!;
      final String source = match.group(3)!;
      return '$destination.$swizzle = $source.$swizzle;';
    });
  }
}

class MatrixRowAccessorTransformer implements LineTransformer {
  MatrixRowAccessorTransformer()
    : _patternFourFirst = RegExp(
        r'dot\(\s*([^,]+)\._([1-4])1_[1-4]2_[1-4]3_[1-4]4\s*,\s*([^)]+)\)',
      ),
      _patternFourSecond = RegExp(
        r'dot\(\s*([^,]+)\s*,\s*([^,]+)\._([1-4])1_[1-4]2_[1-4]3_[1-4]4\s*\)',
      ),
      _patternThreeFirst = RegExp(
        r'dot\(\s*([^,]+)\._([1-4])1_[1-4]2_[1-4]3\s*,\s*([^)]+)\)',
      ),
      _patternThreeSecond = RegExp(
        r'dot\(\s*([^,]+)\s*,\s*([^,]+)\._([1-4])1_[1-4]2_[1-4]3\s*\)',
      );

  final RegExp _patternFourFirst;
  final RegExp _patternFourSecond;
  final RegExp _patternThreeFirst;
  final RegExp _patternThreeSecond;
  static const List<String> _components = <String>['x', 'y', 'z', 'w'];

  @override
  String transform(String line) {
    if (!line.contains('._') || !line.contains('dot')) {
      return line;
    }
    String result = line;
    result = result.replaceAllMapped(_patternFourFirst, (Match match) {
      final String matrixExpr = match.group(1)!.trim();
      final int rowIndex = int.parse(match.group(2)!);
      final String vectorExpr = match.group(3)!.trim();
      return _matrixVectorMultiply(matrixExpr, vectorExpr, rowIndex);
    });
    result = result.replaceAllMapped(_patternFourSecond, (Match match) {
      final String vectorExpr = match.group(1)!.trim();
      final String matrixExpr = match.group(2)!.trim();
      final int rowIndex = int.parse(match.group(3)!);
      return _matrixVectorMultiply(matrixExpr, vectorExpr, rowIndex);
    });
    result = result.replaceAllMapped(_patternThreeFirst, (Match match) {
      final String matrixExpr = match.group(1)!.trim();
      final int rowIndex = int.parse(match.group(2)!);
      final String vectorExpr = match.group(3)!.trim();
      return _dotMatrixRow(matrixExpr, vectorExpr, rowIndex);
    });
    result = result.replaceAllMapped(_patternThreeSecond, (Match match) {
      final String vectorExpr = match.group(1)!.trim();
      final String matrixExpr = match.group(2)!.trim();
      final int rowIndex = int.parse(match.group(3)!);
      return _dotMatrixRow(matrixExpr, vectorExpr, rowIndex);
    });
    return result;
  }

  String _matrixVectorMultiply(
    String matrixExpr,
    String vectorExpr,
    int rowIndex,
  ) {
    final String component = _components[rowIndex - 1];
    return '((${matrixExpr}) * (${vectorExpr})).$component';
  }

  String _dotMatrixRow(String matrixExpr, String vectorExpr, int rowIndex) {
    final int row = rowIndex - 1;
    final String rowVector =
        'float3(${matrixExpr}[0][${row}], ${matrixExpr}[1][${row}], ${matrixExpr}[2][${row}])';
    return 'dot(${rowVector}, ${vectorExpr})';
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
    final bool isLetter =
        (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
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

