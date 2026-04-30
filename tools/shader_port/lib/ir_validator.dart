import 'parser.dart';

class IrValidationError {
  const IrValidationError(this.rule, this.shader, this.message);
  final String rule;
  final String shader;
  final String message;

  @override
  String toString() => '[$rule] $shader: $message';
}

class IrValidationResult {
  const IrValidationResult({required this.errors, required this.shader});
  final String shader;
  final List<IrValidationError> errors;
  bool get passed => errors.isEmpty;
}

class IrValidator {
  static const Set<String> _allowedUniformTypes = <String>{
    'float',
    'float2',
    'float3',
    'float4',
    'float2x4',
    'float3x3',
    'float3x4',
    'float4x4',
    'half4',
    'FLOAT4',
    'int',
    'int2',
    'int3',
    'int4',
    'sampler1D',
    'sampler2D',
    'sampler3D',
    'samplerCUBE',
    'samplerRECT',
  };

  IrValidationResult validateParseResult(ParseResult result) {
    final String shader = result.name.isNotEmpty ? result.name : result.relativePath;
    final List<IrValidationError> errors = <IrValidationError>[];

    final bool hasCoreScript = result.blocks.any(
      (Block b) => b.name.toLowerCase() == 'corescript',
    );
    final bool hasPositionScripts = result.positionScripts.isNotEmpty;
    final bool hasPositionScriptBlocks = result.positionScriptBlocks.isNotEmpty;

    _checkEmpty(
      shader: shader,
      hasCoreScript: hasCoreScript,
      hasPositionScripts: hasPositionScripts,
      hasPositionScriptBlocks: hasPositionScriptBlocks,
      maskReferences: const <String>[],
      errors: errors,
    );

    if (hasCoreScript) {
      _checkDeadCoreScript(
        shader: shader,
        expressions: result.coreScriptExpressions,
        errors: errors,
      );
    }

    final String mainInputContent = result.blocks
        .where((Block b) => b.name.toLowerCase() == 'maininput')
        .map((Block b) => b.content)
        .firstOrNull ?? '';

    _checkDuplicatesAndTypes(
      shader: shader,
      mainInputContent: mainInputContent,
      errors: errors,
    );

    return IrValidationResult(shader: shader, errors: errors);
  }

  IrValidationResult validateIr(Map<String, dynamic> ir, String relative) {
    final String shader = _nonEmpty(ir['name'] as String?, relative);
    final List<IrValidationError> errors = <IrValidationError>[];

    final List<dynamic> blocks = ir['blocks'] as List<dynamic>? ?? const [];

    final bool hasCoreScript = blocks.any(
      (dynamic b) =>
          b is Map<String, dynamic> &&
          (b['name'] as String?)?.toLowerCase() == 'corescript',
    );
    final List<dynamic> positionScripts =
        ir['positionScripts'] as List<dynamic>? ?? const [];
    final List<dynamic> positionScriptBlocks =
        ir['positionScriptBlocks'] as List<dynamic>? ?? const [];

    final List<String> maskReferences = (ir['maskReferences'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];

    _checkEmpty(
      shader: shader,
      hasCoreScript: hasCoreScript,
      hasPositionScripts: positionScripts.isNotEmpty,
      hasPositionScriptBlocks: positionScriptBlocks.isNotEmpty,
      maskReferences: maskReferences,
      errors: errors,
    );

    if (hasCoreScript) {
      final List<dynamic> expressions =
          ir['coreScriptExpressions'] as List<dynamic>? ?? const [];
      final List<Map<String, dynamic>> typedExpressions = expressions
          .whereType<Map<String, dynamic>>()
          .toList();
      _checkDeadCoreScript(
        shader: shader,
        expressions: typedExpressions,
        errors: errors,
      );
    }

    final String mainInputContent = blocks
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> b) =>
            (b['name'] as String?)?.toLowerCase() == 'maininput')
        .map((Map<String, dynamic> b) => b['content'] as String? ?? '')
        .firstOrNull ?? '';

    _checkDuplicatesAndTypes(
      shader: shader,
      mainInputContent: mainInputContent,
      errors: errors,
    );

    return IrValidationResult(shader: shader, errors: errors);
  }

  // Backends that are NOT Metal. A shader masked exclusively to these is
  // intentionally empty for the Metal pipeline.
  static const Set<String> _nonMetalBackends = <String>{
    'D3D', 'DX', 'OPENGL', 'GL', 'DIRECTX', 'DX8', 'DX9', 'D3D8', 'D3D9',
  };

  void _checkEmpty({
    required String shader,
    required bool hasCoreScript,
    required bool hasPositionScripts,
    required bool hasPositionScriptBlocks,
    required List<String> maskReferences,
    required List<IrValidationError> errors,
  }) {
    if (hasCoreScript || hasPositionScripts || hasPositionScriptBlocks) return;

    // Exempt shaders that are explicitly limited to non-Metal backends.
    if (maskReferences.isNotEmpty &&
        maskReferences.every(
          (String m) => _nonMetalBackends.contains(m.toUpperCase()),
        )) {
      return;
    }

    errors.add(IrValidationError(
      'IR-1',
      shader,
      'shader has no CoreScript block, no positionScripts, and no positionScriptBlocks — '
      'it is completely empty and will produce a no-op Metal function',
    ));
  }

  void _checkDeadCoreScript({
    required String shader,
    required List<Map<String, dynamic>> expressions,
    required List<IrValidationError> errors,
  }) {
    final bool hasActiveExpression = expressions.any(
      (Map<String, dynamic> e) {
        final Object? active = e['active'];
        if (active is bool) return active;
        if (active == null) return true;
        return true;
      },
    );
    if (!hasActiveExpression) {
      errors.add(IrValidationError(
        'IR-2',
        shader,
        'CoreScript block is present but contains zero active expressions — '
        'the generated shader body will be empty (black pixel / no-op vertex)',
      ));
    }
  }

  void _checkDuplicatesAndTypes({
    required String shader,
    required String mainInputContent,
    required List<IrValidationError> errors,
  }) {
    if (mainInputContent.isEmpty) return;

    // Process line-by-line to respect preprocessor branches.
    // Two declarations with the same name in different branches of the same
    // conditional block (or in separate independent #ifdef blocks) are NOT
    // duplicates — they are mutually exclusive at runtime.
    // A true duplicate is the same name appearing *twice in the same branch*.
    //
    // Branch path: each #if/ifdef push a unique block ID + branch index.
    // #elif/#else increment the branch index of the current block.
    // Independent sibling #ifdef blocks get different block IDs.
    int _blockCounter = 0;
    // Stack of (blockId, branchIndex) pairs
    final List<(int, int)> branchStack = <(int, int)>[];
    // Key format: "<(blockId,branch)...>:<u|t>:<name>"
    final Set<String> seenBranchKeys = <String>{};
    // Separate set for type-error deduplication (report type error only once per name)
    final Set<String> typeErrorNames = <String>{};

    final RegExp ifRe = RegExp(r'^\s*#\s*if(?:n?def)?\b');
    final RegExp elifRe = RegExp(r'^\s*#\s*elif\b');
    final RegExp elseRe = RegExp(r'^\s*#\s*else\b');
    final RegExp endifRe = RegExp(r'^\s*#\s*endif\b');
    final RegExp uniformRe = RegExp(
      r'uniform\s+([A-Za-z0-9_]+)\s+([A-Za-z0-9_]+)',
    );

    for (final String line
        in mainInputContent.split(RegExp(r'\r?\n'))) {
      if (ifRe.hasMatch(line)) {
        branchStack.add((_blockCounter++, 0));
      } else if (elifRe.hasMatch(line)) {
        if (branchStack.isNotEmpty) {
          final (int id, int idx) = branchStack.last;
          branchStack[branchStack.length - 1] = (id, idx + 1);
        }
      } else if (elseRe.hasMatch(line)) {
        if (branchStack.isNotEmpty) {
          final (int id, int idx) = branchStack.last;
          branchStack[branchStack.length - 1] = (id, idx + 1);
        }
      } else if (endifRe.hasMatch(line)) {
        if (branchStack.isNotEmpty) branchStack.removeLast();
      } else {
        if (line.trim().startsWith('//')) continue;
        final RegExpMatch? m = uniformRe.firstMatch(line);
        if (m == null) continue;

        final String type = m.group(1) ?? '';
        final String name = m.group(2) ?? '';
        if (type.isEmpty || name.isEmpty) continue;

        final String branchPath =
            branchStack.map(((int, int) p) => '${p.$1}_${p.$2}').join('/');
        final bool isTexture = type.toLowerCase().startsWith('sampler');
        final String prefix = isTexture ? 't' : 'u';
        final String key = '$branchPath:$prefix:$name';

        if (isTexture) {
          if (!seenBranchKeys.add(key)) {
            errors.add(IrValidationError(
              'IR-4',
              shader,
              'duplicate texture name "$name" in MainInput',
            ));
          }
        } else {
          if (!seenBranchKeys.add(key)) {
            errors.add(IrValidationError(
              'IR-3',
              shader,
              'duplicate uniform name "$name" in MainInput',
            ));
          }
          if (!_allowedUniformTypes.contains(type) &&
              typeErrorNames.add(name)) {
            errors.add(IrValidationError(
              'IR-5',
              shader,
              'uniform "$name" has unrecognized type "$type" — '
              'expected one of: ${_allowedUniformTypes.join(', ')}',
            ));
          }
        }
      }
    }
  }

  String _nonEmpty(String? value, String fallback) =>
      (value != null && value.isNotEmpty) ? value : fallback;
}
