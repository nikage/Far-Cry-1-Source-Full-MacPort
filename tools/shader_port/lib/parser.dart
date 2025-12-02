import 'dart:convert';
import 'dart:io';

class Block {
  Block(this.name, this.content);
  final String name;
  final String content;
}

class ParseResult {
  ParseResult(
    this.name,
    this.extension,
    this.relativePath,
    this.includes,
    this.blocks,
    this.textureStages,
    this.passStates,
    this.coreScriptExpressions,
    this.coreMacros,
    this.vertexAttributes,
    this.directives,
    this.coreScriptFlow,
    this.maskReferences,
    this.positionScripts,
    this.positionScriptBlocks,
    this.outputFieldTypes,
  );

  final String name;
  final String extension;
  final String relativePath;
  final List<String> includes;
  final List<Block> blocks;
  final List<Map<String, dynamic>> textureStages;
  final List<Map<String, dynamic>> passStates;
  final List<Map<String, dynamic>> coreScriptExpressions;
  final List<Map<String, dynamic>> coreMacros;
  final List<String> vertexAttributes;
  final List<String> directives;
  final List<Map<String, dynamic>> coreScriptFlow;
  final List<String> maskReferences;
  final List<String> positionScripts;
  final List<Map<String, String>> positionScriptBlocks;
  final Map<String, String> outputFieldTypes;
}

void main(List<String> args) {
  final Directory root =
      (args.isEmpty ? Directory.current : Directory(args.first)).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath = root.path.endsWith(sep) ? root.path : root.path + sep;
  final Directory legacyDir = Directory(rootPath + 'Shaders${sep}Legacy');
  if (!legacyDir.existsSync()) {
    stderr.writeln('Missing directory: ${legacyDir.path}');
    exit(1);
  }
  final Directory outputDir = Directory(
    rootPath + 'tools${sep}shader_port${sep}output${sep}ir',
  );
  outputDir.createSync(recursive: true);
  final List<Map<String, dynamic>> index = [];
  for (final FileSystemEntity entity in legacyDir.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final String lower = entity.path.toLowerCase();
    if (!(lower.endsWith('.cryps') || lower.endsWith('.crycg'))) continue;
    final String relative = entity.path
        .substring(legacyDir.path.length + 1)
        .replaceAll(RegExp(r'[\\/]'), '/');
    final ParseResult result = parseShader(entity, relative);
    final File targetFile = File(outputDir.path + sep + relative + '.json');
    targetFile.parent.createSync(recursive: true);
    targetFile.writeAsStringSync(encodeResult(result));
    index.add({
      'name': result.name,
      'extension': result.extension,
      'relative': relative,
      'ir': targetFile.path
          .substring(rootPath.length)
          .replaceAll(RegExp(r'[\\/]'), '/'),
      'blocks': result.blocks.map((b) => b.name).toList(),
    });
  }
  final File indexFile = File(outputDir.path + sep + 'index.json');
  index.sort((a, b) => a['relative'].compareTo(b['relative']));
  indexFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(index),
  );
  stdout.writeln('Parsed ${index.length} shader scripts into IR');
}

ParseResult parseShader(File file, String relativePath) {
  final String content = file.readAsStringSync(encoding: latin1);
  return parseShaderFromSource(content, relativePath);
}

ParseResult parseShaderFromSource(String source, String relativePath) {
  return _parseShaderContent(source, relativePath);
}

ParseResult _parseShaderContent(String content, String relativePath) {
  final List<String> includes = [];
  final List<Block> blocks = [];
  int index = 0;
  int depth = 0;
  while (index < content.length) {
    final int charCode = content.codeUnitAt(index);
    if (charCode == 47 && index + 1 < content.length) {
      final int next = content.codeUnitAt(index + 1);
      if (next == 47) {
        index = skipLine(content, index + 2);
        continue;
      } else if (next == 42) {
        index = skipBlockComment(content, index + 2);
        continue;
      }
    }
    if (charCode == 34 || charCode == 39) {
      index = skipString(content, index + 1, charCode);
      continue;
    }
    if (charCode == 123) {
      depth++;
      index++;
      continue;
    }
    if (charCode == 125) {
      if (depth > 0) depth--;
      index++;
      continue;
    }
    if (charCode == 35 && depth == 0) {
      final int lineEnd = content.indexOf('\n', index);
      final String line = content
          .substring(index, lineEnd == -1 ? content.length : lineEnd)
          .trim();
      if (line.startsWith('#include')) {
        final int quoteStart = line.indexOf('"');
        final int quoteEnd = quoteStart == -1
            ? -1
            : line.indexOf('"', quoteStart + 1);
        if (quoteStart != -1 && quoteEnd != -1 && quoteEnd > quoteStart)
          includes.add(line.substring(quoteStart + 1, quoteEnd));
      }
      index = lineEnd == -1 ? content.length : lineEnd + 1;
      continue;
    }
    if (depth == 0 && isIdentifierStart(charCode)) {
      final int start = index;
      index++;
      while (index < content.length &&
          isIdentifierPart(content.codeUnitAt(index)))
        index++;
      final String identifier = content.substring(start, index);
      final int nextIndex = skipWhitespace(content, index);
      if (nextIndex < content.length && content.codeUnitAt(nextIndex) == 123) {
        final int blockEnd = findMatchingBrace(content, nextIndex);
        if (blockEnd == -1) {
          index = nextIndex + 1;
          continue;
        }
        final String blockContent = content
            .substring(nextIndex + 1, blockEnd)
            .trimRight();
        blocks.add(Block(identifier, blockContent));
        index = blockEnd + 1;
        continue;
      }
    }
    index++;
  }
  final String fileName = relativePath.split('/').last;
  final int dot = fileName.lastIndexOf('.');
  final String name = dot == -1 ? fileName : fileName.substring(0, dot);
  final String extension = dot == -1 ? '' : fileName.substring(dot + 1);
  final List<Map<String, dynamic>> textureStages = extractTextureStages(blocks);
  final List<Map<String, dynamic>> passStates = extractPassStates(blocks);
  final List<Map<String, dynamic>> coreMacros = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> coreExpressions =
      extractCoreExpressions(blocks, coreMacros);
  final List<String> vertexAttributes = extractVertexAttributes(blocks);
  final List<String> directives = extractDirectives(content);
  final List<Map<String, dynamic>> coreFlow = extractCoreScriptFlow(blocks);
  final List<String> maskReferences = extractMaskReferences(content);
  final List<String> positionScripts = extractPositionScripts(content);
  final List<Map<String, String>> positionScriptBlocks =
      extractPositionScriptBlocks(blocks);
  final Map<String, String> outputFieldTypes = extractOutputFieldTypes(blocks);
  return ParseResult(
    name,
    extension,
    relativePath,
    includes,
    blocks,
    textureStages,
    passStates,
    coreExpressions,
    coreMacros,
    vertexAttributes,
    directives,
    coreFlow,
    maskReferences,
    positionScripts,
    positionScriptBlocks,
    outputFieldTypes,
  );
}

String encodeResult(ParseResult result) {
  final Map<String, dynamic> map = {
    'name': result.name,
    'extension': result.extension,
    'path': result.relativePath,
    'includes': result.includes,
    'blocks': result.blocks
        .map((block) => {'name': block.name, 'content': block.content})
        .toList(),
    'textureStages': result.textureStages,
    'passStates': result.passStates,
    'coreScriptExpressions': result.coreScriptExpressions,
    'coreMacros': result.coreMacros,
    'vertexAttributes': result.vertexAttributes,
    'directives': result.directives,
    'coreScriptFlow': result.coreScriptFlow,
    'maskReferences': result.maskReferences,
    'positionScripts': result.positionScripts,
    'positionScriptBlocks': result.positionScriptBlocks,
    'outputFieldTypes': result.outputFieldTypes,
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}

List<Map<String, dynamic>> extractTextureStages(List<Block> blocks) {
  final List<Map<String, dynamic>> stages = [];
  for (final Block block in blocks) {
    final String lower = block.name.toLowerCase();
    if (!lower.contains('tex') && !lower.contains('layer')) {
      continue;
    }
    final List<Map<String, String>> statements = _extractAssignments(
      block.content,
    );
    if (statements.isEmpty) {
      continue;
    }
    stages.add({'block': block.name, 'statements': statements});
  }
  return stages;
}

List<Map<String, dynamic>> extractPassStates(List<Block> blocks) {
  final List<Map<String, dynamic>> states = [];
  for (final Block block in blocks) {
    final List<Map<String, String>> statements = _extractAssignments(
      block.content,
    );
    final List<Map<String, dynamic>> entries = _parseStateEntries(
      block.content,
    );
    if (statements.isEmpty && entries.isEmpty) {
      continue;
    }
    final Map<String, dynamic> summary = _summarizePassState(
      statements,
      entries,
    );
    final bool blockNameSuggestsPass = _blockNameSuggestsPass(block.name);
    final bool hasPassStateCall = entries.any((entry) {
      if (entry['type'] != 'call') {
        return false;
      }
      final String? value = entry['value'] as String?;
      return value != null && _isPassStateCall(value);
    });
    if (summary.isEmpty && !blockNameSuggestsPass && !hasPassStateCall) {
      continue;
    }
    final Map<String, dynamic> stateInfo = {
      'block': block.name,
      'statements': statements,
      'entries': entries,
    };
    if (summary.isNotEmpty) {
      stateInfo['stateSummary'] = summary;
    }
    states.add(stateInfo);
  }
  return states;
}

List<Map<String, dynamic>> extractCoreExpressions(
  List<Block> blocks, [
  List<Map<String, dynamic>>? macroSink,
]) {
  Block? coreBlock;
  for (final Block block in blocks) {
    if (block.name.toLowerCase() == 'corescript') {
      coreBlock = block;
      break;
    }
  }
  if (coreBlock == null) {
    return const [];
  }
  final List<Map<String, dynamic>> expressions = [];
  final List<_GuardFrame> guardStack = <_GuardFrame>[];
  final List<String> lines = coreBlock.content.split('\n');
  for (final String rawLine in lines) {
    final String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('//')) {
      expressions.add({
        'type': 'comment',
        'value': line.substring(2).trim(),
        'guards': _materializeGuards(guardStack),
        'active': _guardStackActive(guardStack),
      });
      continue;
    }
    if (line == '{' || line == '}') {
      continue;
    }
    if (line.startsWith('#')) {
      if (_maybeRecordMacro(line, guardStack, macroSink)) {
        continue;
      }
      _handleCoreDirective(line, guardStack, expressions);
      continue;
    }
    final Map<String, dynamic>? entry = _parseCoreExpressionLine(line);
    if (entry == null) {
      continue;
    }
    entry['guards'] = _materializeGuards(guardStack);
    entry['active'] = _guardStackActive(guardStack);
    expressions.add(entry);
  }
  return expressions;
}

Map<String, dynamic>? _parseCoreExpressionLine(String line) {
  if (line.contains('=')) {
    final int index = line.indexOf('=');
    if (index <= 0) {
      return null;
    }
    final String lhs = line.substring(0, index).trim();
    final String rhs = line.substring(index + 1).trim().replaceAll(';', '');
    final bool isSample =
        rhs.contains('tex2D') || rhs.contains('texCUBE') || rhs.contains('tex3D');
    return {
      'type': 'assignment',
      'lhs': lhs,
      'rhs': rhs,
      'textureSample': isSample,
      'raw': line,
    };
  }
  return {'type': 'statement', 'raw': line};
}

bool _maybeRecordMacro(
  String line,
  List<_GuardFrame> guardStack,
  List<Map<String, dynamic>>? sink,
) {
  if (sink == null) {
    return false;
  }
  final RegExpMatch? match =
      RegExp(r'^#\s*define\s+([A-Za-z_][A-Za-z0-9_]*)\s*(.*)$').firstMatch(line);
  if (match == null) {
    return false;
  }
  final String name = match.group(1)!;
  if (name.contains('(')) {
    return false;
  }
  final String value = (match.group(2) ?? '').trim();
  sink.add({
    'name': name,
    'value': value,
    'guards': _materializeGuards(guardStack),
    'active': _guardStackActive(guardStack),
    'raw': line,
  });
  return true;
}

String _directiveArgument(String source, int prefixLength) {
  if (source.length <= prefixLength) {
    return '';
  }
  return source.substring(prefixLength).trim();
}

void _handleCoreDirective(
  String line,
  List<_GuardFrame> guardStack,
  List<Map<String, dynamic>> expressions,
) {
  final String trimmed = line.trim();
  final String normalized =
      trimmed.startsWith('#') ? trimmed.substring(1).trimLeft() : trimmed;
  final String lower = normalized.toLowerCase();
  if (lower.startsWith('ifdef')) {
    final String symbol = _directiveArgument(normalized, 5);
    final _GuardState state = _evaluateGuardSymbol(symbol);
    guardStack.add(
      _GuardFrame(
        directive: '#ifdef',
        expression: symbol,
        state: state,
        shouldEmit: state == _GuardState.unknown,
      ),
    );
    if (guardStack.last.shouldEmit) {
      expressions.add({
        'type': 'directive',
        'raw': line,
        'guards': _materializeGuards(guardStack.sublist(0, guardStack.length - 1)),
        'active': true,
      });
    }
    return;
  }
  if (lower.startsWith('ifndef')) {
    final String symbol = _directiveArgument(normalized, 6);
    final _GuardState state = _invertGuardState(_evaluateGuardSymbol(symbol));
    guardStack.add(
      _GuardFrame(
        directive: '#ifndef',
        expression: symbol,
        state: state,
        shouldEmit: state == _GuardState.unknown,
      ),
    );
    if (guardStack.last.shouldEmit) {
      expressions.add({
        'type': 'directive',
        'raw': line,
        'guards': _materializeGuards(guardStack.sublist(0, guardStack.length - 1)),
        'active': true,
      });
    }
    return;
  }
  if (lower.startsWith('if')) {
    final String expression = _directiveArgument(normalized, 2);
    final _GuardState state = _evaluateGuardExpression(expression);
    guardStack.add(
      _GuardFrame(
        directive: '#if',
        expression: expression,
        state: state,
        shouldEmit: state == _GuardState.unknown,
      ),
    );
    if (guardStack.last.shouldEmit) {
      expressions.add({
        'type': 'directive',
        'raw': line,
        'guards': _materializeGuards(guardStack.sublist(0, guardStack.length - 1)),
        'active': true,
      });
    }
    return;
  }
  if (lower.startsWith('elif')) {
    if (guardStack.isEmpty) {
      return;
    }
    final _GuardFrame frame = guardStack.last;
    final String expression = _directiveArgument(normalized, 4);
    _updateElifFrame(frame, expression);
    if (frame.shouldEmit) {
      expressions.add({
        'type': 'directive',
        'raw': line,
        'guards': _materializeGuards(guardStack.sublist(0, guardStack.length - 1)),
        'active': true,
      });
    }
    return;
  }
  if (lower.startsWith('else')) {
    if (guardStack.isEmpty) {
      return;
    }
    final _GuardFrame frame = guardStack.last;
    _updateElseFrame(frame);
    if (frame.shouldEmit) {
      expressions.add({
        'type': 'directive',
        'raw': line,
        'guards': _materializeGuards(guardStack.sublist(0, guardStack.length - 1)),
        'active': true,
      });
    }
    return;
  }
  if (lower.startsWith('endif')) {
    if (guardStack.isEmpty) {
      return;
    }
    final _GuardFrame frame = guardStack.removeLast();
    if (frame.shouldEmit) {
      expressions.add({
        'type': 'directive',
        'raw': line,
        'guards': _materializeGuards(guardStack),
        'active': true,
      });
    }
    return;
  }
  expressions.add({
    'type': 'directive',
    'raw': line,
    'guards': _materializeGuards(guardStack),
    'active': true,
  });
}

void _updateElifFrame(_GuardFrame frame, String expression) {
  if (frame.anyKnownTrue) {
    frame.directive = '#elif';
    frame.expression = expression;
    frame.state = _GuardState.falseValue;
    return;
  }
  if (frame.maybeTrue) {
    frame.directive = '#elif';
    frame.expression = expression;
    frame.state = _GuardState.unknown;
    return;
  }
  final _GuardState state = _evaluateGuardExpression(expression);
  frame.directive = '#elif';
  frame.expression = expression;
  frame.state = state;
  if (state == _GuardState.trueValue) {
    frame.anyKnownTrue = true;
    frame.maybeTrue = true;
  } else if (state == _GuardState.unknown) {
    frame.maybeTrue = true;
  }
}

void _updateElseFrame(_GuardFrame frame) {
  frame.directive = '#else';
  frame.expression = 'else';
  if (frame.anyKnownTrue) {
    frame.state = _GuardState.falseValue;
    return;
  }
  if (frame.maybeTrue) {
    frame.state = _GuardState.unknown;
    return;
  }
  frame.state = _GuardState.trueValue;
  frame.anyKnownTrue = true;
  frame.maybeTrue = true;
}

List<Map<String, dynamic>> _materializeGuards(List<_GuardFrame> stack) {
  if (stack.isEmpty) {
    return const [];
  }
  return stack
      .map(
        (_GuardFrame frame) => {
          'directive': frame.directive,
          'expression': frame.expression,
          'state': _guardStateToString(frame.state),
        },
      )
      .toList();
}

bool? _guardStackActive(List<_GuardFrame> stack) {
  bool hasUnknown = false;
  for (final _GuardFrame frame in stack) {
    if (frame.state == _GuardState.falseValue) {
      return false;
    }
    if (frame.state == _GuardState.unknown) {
      hasUnknown = true;
    }
  }
  if (hasUnknown) {
    return null;
  }
  return true;
}

_GuardState _evaluateGuardExpression(String expression) {
  final String trimmed = expression.trim();
  if (trimmed == '1') {
    return _GuardState.trueValue;
  }
  if (trimmed == '0') {
    return _GuardState.falseValue;
  }
  final RegExp definedPattern =
      RegExp(r'^(!)?\s*defined\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$');
  final RegExpMatch? match = definedPattern.firstMatch(trimmed.replaceAll(' ', ''));
  if (match != null) {
    final bool negated = (match.group(1) ?? '').contains('!');
    final String symbol = match.group(2) ?? '';
    return negated
        ? _invertGuardState(_evaluateGuardSymbol(symbol))
        : _evaluateGuardSymbol(symbol);
  }
  return _GuardState.unknown;
}

_GuardState _evaluateGuardSymbol(String symbol) {
  final String upper = symbol.trim().toUpperCase();
  if (upper == 'D3D') {
    return _GuardState.trueValue;
  }
  if (upper == 'OPENGL') {
    return _GuardState.falseValue;
  }
  if (upper == '_PS_1_1') {
    return _GuardState.falseValue;
  }
  return _GuardState.unknown;
}

_GuardState _invertGuardState(_GuardState state) {
  if (state == _GuardState.trueValue) {
    return _GuardState.falseValue;
  }
  if (state == _GuardState.falseValue) {
    return _GuardState.trueValue;
  }
  return _GuardState.unknown;
}

String _guardStateToString(_GuardState state) {
  switch (state) {
    case _GuardState.trueValue:
      return 'true';
    case _GuardState.falseValue:
      return 'false';
    case _GuardState.unknown:
    default:
      return 'unknown';
  }
}

class _GuardFrame {
  _GuardFrame({
    required this.directive,
    required this.expression,
    required this.state,
    required this.shouldEmit,
  })  : anyKnownTrue = state == _GuardState.trueValue,
        maybeTrue = state != _GuardState.falseValue;

  String directive;
  String expression;
  _GuardState state;
  final bool shouldEmit;
  bool anyKnownTrue;
  bool maybeTrue;
}

enum _GuardState {
  trueValue,
  falseValue,
  unknown,
}

List<Map<String, String>> _extractAssignments(String content) {
  final List<Map<String, String>> results = [];
  final List<String> lines = content.split('\n');
  for (final String rawLine in lines) {
    final String line = rawLine.trim();
    if (line.isEmpty || line == '{' || line == '}') {
      continue;
    }
    if (line.startsWith('//')) {
      results.add({'comment': line.substring(2).trim()});
      continue;
    }
    if (line.contains('=')) {
      final int index = line.indexOf('=');
      final String lhs = line.substring(0, index).trim();
      final String rhs = line.substring(index + 1).trim().replaceAll(';', '');
      results.add({'lhs': lhs, 'rhs': rhs, 'raw': line});
    } else {
      results.add({'raw': line});
    }
  }
  return results;
}

List<Map<String, dynamic>> _parseStateEntries(String content) {
  final List<Map<String, dynamic>> entries = [];
  final List<String> lines = content.split('\n');
  for (final String rawLine in lines) {
    String line = rawLine.trim();
    if (line.isEmpty || line == '{' || line == '}') {
      continue;
    }
    if (line.startsWith('//')) {
      entries.add({'type': 'comment', 'value': line.substring(2).trim()});
      continue;
    }
    if (line.contains('=')) {
      final int eq = line.indexOf('=');
      if (eq != -1) {
        final String key = line.substring(0, eq).trim();
        String value = line.substring(eq + 1).trim();
        if (value.endsWith(';')) {
          value = value.substring(0, value.length - 1).trimRight();
        }
        entries.add({'type': 'assignment', 'key': key, 'value': value});
        continue;
      }
    }
    if (line.contains('(') && line.contains(')')) {
      if (line.endsWith(';')) {
        line = line.substring(0, line.length - 1).trimRight();
      }
      entries.add({'type': 'call', 'value': line});
      continue;
    }
    if (line.endsWith(';')) {
      line = line.substring(0, line.length - 1).trimRight();
    }
    entries.add({'type': 'statement', 'value': line});
  }
  return entries;
}

class _PassStateKeyInfo {
  const _PassStateKeyInfo(this.canonical, [this.index]);

  final String canonical;
  final int? index;
}

class _InlineStateAssignment {
  _InlineStateAssignment(this.key, this.value);

  final String key;
  final String value;
}

class _OutputFieldSpec {
  const _OutputFieldSpec(this.field, this.type);

  final String field;
  final String type;
}

_OutputFieldSpec? _mapOutputMacroToSpec(String macro) {
  switch (macro) {
    case 'OUT_P':
      return const _OutputFieldSpec('HPosition', 'float4');
    case 'OUT_C0':
      return const _OutputFieldSpec('Color', 'float4');
    case 'OUT_C1':
      return const _OutputFieldSpec('Color1', 'float4');
  }
  final RegExp texPattern = RegExp(r'^OUT_T(\d+)(?:_(\d+))?$');
  final RegExpMatch? match = texPattern.firstMatch(macro);
  if (match != null) {
    final String index = match.group(1)!;
    final String? componentCount = match.group(2);
    String type = 'float4';
    if (componentCount != null) {
      switch (componentCount) {
        case '1':
          type = 'float';
          break;
        case '2':
          type = 'float2';
          break;
        case '3':
          type = 'float3';
          break;
        case '4':
          type = 'float4';
          break;
        default:
          type = 'float$componentCount';
          break;
      }
    }
    return _OutputFieldSpec('Tex$index', type);
  }
  return null;
}

const Map<String, String> _passStateKeyLookup = {
  'alphablendenable': 'blendEnable',
  'alphafunc': 'alphaFunc',
  'alpharef': 'alphaRef',
  'alphatest': 'alphaTest',
  'blend': 'blendEnable',
  'blendenable': 'blendEnable',
  'blendfunc': 'blendFunc',
  'blendfuncseparate': 'blendFuncSeparate',
  'blendop': 'blendOp',
  'blendopalpha': 'blendOpAlpha',
  'colormask': 'colorMask',
  'colorwriteenable': 'colorMask',
  'cullmode': 'cullMode',
  'depthbias': 'depthBias',
  'depthfunc': 'depthFunc',
  'depthtest': 'depthTest',
  'depthwrite': 'depthWrite',
  'destblend': 'destBlend',
  'destblendalpha': 'destBlendAlpha',
  'fogenable': 'fogEnable',
  'mask': 'mask',
  'shademode': 'shadeMode',
  'slopebias': 'slopeDepthBias',
  'srcblend': 'srcBlend',
  'srcblendalpha': 'srcBlendAlpha',
  'stencilenable': 'stencilEnable',
  'stencilfail': 'stencilFail',
  'stencilfailback': 'stencilFailBack',
  'stencilfailfront': 'stencilFailFront',
  'stencilfunc': 'stencilFunc',
  'stencilfuncback': 'stencilFuncBack',
  'stencilfuncfront': 'stencilFuncFront',
  'stencilmask': 'stencilMask',
  'stencilmaskback': 'stencilMaskBack',
  'stencilmaskfront': 'stencilMaskFront',
  'stencilpass': 'stencilPass',
  'stencilpassback': 'stencilPassBack',
  'stencilpassfront': 'stencilPassFront',
  'stencilreffront': 'stencilRefFront',
  'stencilrefback': 'stencilRefBack',
  'stencilref': 'stencilRef',
  'stencilwritemask': 'stencilWriteMask',
  'stencilwritemaskback': 'stencilWriteMaskBack',
  'stencilwritemaskfront': 'stencilWriteMaskFront',
  'stencilzfail': 'stencilZFail',
  'stencilzfailback': 'stencilZFailBack',
  'stencilzfailfront': 'stencilZFailFront',
  'zfunc': 'depthFunc',
  'ztest': 'depthTest',
  'zwrite': 'depthWrite',
};

const Map<String, String> _enumAliases = {
  'ONE_MINUS_SRC_ALPHA': 'INVSRCALPHA',
  'ONEMINUSSRCALPHA': 'INVSRCALPHA',
  'ONE_MINUS_DEST_ALPHA': 'INVDSTALPHA',
  'ONE_MINUS_DST_ALPHA': 'INVDSTALPHA',
  'ONEMINUSDSTALPHA': 'INVDSTALPHA',
  'ONE_MINUS_SRC_COLOR': 'INVSRCOLOR',
  'ONE_MINUS_DEST_COLOR': 'INVDSTCOLOR',
  'ONE_MINUS_DST_COLOR': 'INVDSTCOLOR',
  'ONEMINUSSRCOLOR': 'INVSRCOLOR',
  'ONEMINUSDSTCOLOR': 'INVDSTCOLOR',
};

bool _blockNameSuggestsPass(String name) {
  final String lower = name.toLowerCase();
  return lower.contains('pass') || lower.contains('state');
}

bool _isPassStateCall(String call) {
  final String lowered = call.trim().toLowerCase();
  return lowered.startsWith('settexture');
}

_PassStateKeyInfo? _identifyPassStateKey(String rawKey) {
  String key = rawKey.replaceAll(RegExp(r'\s+'), '');
  key = key.replaceAll(':', '');
  final String lower = key.toLowerCase();
  final RegExpMatch? match = RegExp(r'^([a-z_]+?)(\d+)$').firstMatch(lower);
  int? index;
  String lookupKey = lower;
  if (match != null) {
    lookupKey = match.group(1)!;
    index = int.tryParse(match.group(2)!);
  }
  String? canonical = _passStateKeyLookup[lookupKey];
  canonical ??= _passStateKeyLookup[lower];
  if (canonical == null) {
    return null;
  }
  return _PassStateKeyInfo(canonical, index);
}

Map<String, dynamic> _summarizePassState(
  List<Map<String, String>> statements,
  List<Map<String, dynamic>> entries,
) {
  final Map<String, dynamic> summary = {};
  final Map<String, dynamic> blend = {};
  final Map<String, Map<String, bool>> colorMasks = {};

  for (final Map<String, String> statement in statements) {
    String? lhs = statement['lhs'];
    String? rhs = statement['rhs'];
    if ((lhs == null || rhs == null) && statement.containsKey('raw')) {
      final _InlineStateAssignment? inline = _parseInlineState(
        statement['raw']!,
      );
      if (inline != null) {
        lhs = inline.key;
        rhs = inline.value;
      }
    }
    if (lhs == null || rhs == null) {
      continue;
    }
    final _PassStateKeyInfo? keyInfo = _identifyPassStateKey(lhs);
    if (keyInfo == null) {
      continue;
    }
    final String value = rhs.trim();
    switch (keyInfo.canonical) {
      case 'alphaFunc':
        summary['alphaFunc'] = _normalizeEnumValue(value);
        break;
      case 'alphaRef':
        final num? numeric = _parseNumericValue(value);
        if (numeric != null) {
          summary['alphaRef'] = numeric;
        }
        break;
      case 'alphaTest':
        final bool? boolValue = _parseBoolValue(value);
        if (boolValue != null) {
          summary['alphaTest'] = boolValue;
        } else {
          summary['alphaTestMode'] = _normalizeEnumValue(value);
        }
        break;
      case 'blendEnable':
        final bool? boolValue = _parseBoolValue(value);
        if (boolValue != null) {
          blend['enabled'] = boolValue;
        } else {
          blend['mode'] = _normalizeEnumValue(value);
        }
        break;
      case 'blendFunc':
        final List<String> tokens = _splitStateValues(value);
        if (tokens.length >= 2) {
          blend['src'] = tokens[0];
          blend['dst'] = tokens[1];
        }
        if (tokens.length >= 4) {
          blend['srcAlpha'] = tokens[2];
          blend['dstAlpha'] = tokens[3];
        }
        break;
      case 'blendFuncSeparate':
        final List<String> tokens = _splitStateValues(value);
        if (tokens.length >= 2) {
          blend['src'] = tokens[0];
          blend['dst'] = tokens[1];
        }
        if (tokens.length >= 4) {
          blend['srcAlpha'] = tokens[2];
          blend['dstAlpha'] = tokens[3];
        }
        break;
      case 'blendOp':
        blend['op'] = _normalizeEnumValue(value);
        break;
      case 'blendOpAlpha':
        blend['opAlpha'] = _normalizeEnumValue(value);
        break;
      case 'colorMask':
        final Map<String, bool> mask = _parseColorMask(value);
        final String key = keyInfo.index == null
            ? 'colorMask'
            : 'colorMask${keyInfo.index}';
        colorMasks[key] = mask;
        break;
      case 'cullMode':
        summary['cullMode'] = _normalizeEnumValue(value);
        break;
      case 'depthBias':
        final num? numeric = _parseNumericValue(value);
        if (numeric != null) {
          summary['depthBias'] = numeric;
        }
        break;
      case 'depthFunc':
        summary['depthFunc'] = _normalizeEnumValue(value);
        break;
      case 'depthTest':
        final bool? boolValue = _parseBoolValue(value);
        if (boolValue != null) {
          summary['depthTest'] = boolValue;
        } else {
          summary['depthFunc'] = _normalizeEnumValue(value);
        }
        break;
      case 'depthWrite':
        final bool? boolValue = _parseBoolValue(value);
        if (boolValue != null) {
          summary['depthWrite'] = boolValue;
        }
        break;
      case 'destBlend':
        blend['dst'] = _normalizeEnumValue(value);
        break;
      case 'destBlendAlpha':
        blend['dstAlpha'] = _normalizeEnumValue(value);
        break;
      case 'fogEnable':
        final bool? boolValue = _parseBoolValue(value);
        if (boolValue != null) {
          summary['fogEnable'] = boolValue;
        }
        break;
      case 'mask':
        summary['mask'] = _normalizeEnumValue(value);
        break;
      case 'shadeMode':
        summary['shadeMode'] = _normalizeEnumValue(value);
        break;
      case 'slopeDepthBias':
        final num? numeric = _parseNumericValue(value);
        if (numeric != null) {
          summary['slopeDepthBias'] = numeric;
        }
        break;
      case 'srcBlend':
        blend['src'] = _normalizeEnumValue(value);
        break;
      case 'srcBlendAlpha':
        blend['srcAlpha'] = _normalizeEnumValue(value);
        break;
      case 'stencilEnable':
        final bool? boolValue = _parseBoolValue(value);
        if (boolValue != null) {
          summary['stencilEnable'] = boolValue;
        }
        break;
      case 'stencilFail':
        summary['stencilFail'] = _normalizeEnumValue(value);
        break;
      case 'stencilFailBack':
        summary['stencilFailBack'] = _normalizeEnumValue(value);
        break;
      case 'stencilFailFront':
        summary['stencilFailFront'] = _normalizeEnumValue(value);
        break;
      case 'stencilFunc':
        summary['stencilFunc'] = _normalizeEnumValue(value);
        break;
      case 'stencilFuncBack':
        summary['stencilFuncBack'] = _normalizeEnumValue(value);
        break;
      case 'stencilFuncFront':
        summary['stencilFuncFront'] = _normalizeEnumValue(value);
        break;
      case 'stencilMask':
        final num? numeric = _parseNumericValue(value);
        if (numeric != null) {
          summary['stencilMask'] = numeric;
        }
        break;
      case 'stencilMaskBack':
        final num? numericBack = _parseNumericValue(value);
        if (numericBack != null) {
          summary['stencilMaskBack'] = numericBack;
        }
        break;
      case 'stencilMaskFront':
        final num? numericFront = _parseNumericValue(value);
        if (numericFront != null) {
          summary['stencilMaskFront'] = numericFront;
        }
        break;
      case 'stencilPass':
        summary['stencilPass'] = _normalizeEnumValue(value);
        break;
      case 'stencilPassBack':
        summary['stencilPassBack'] = _normalizeEnumValue(value);
        break;
      case 'stencilPassFront':
        summary['stencilPassFront'] = _normalizeEnumValue(value);
        break;
      case 'stencilRef':
        final num? numeric = _parseNumericValue(value);
        if (numeric != null) {
          summary['stencilRef'] = numeric;
        }
        break;
      case 'stencilRefBack':
        final num? numericBack = _parseNumericValue(value);
        if (numericBack != null) {
          summary['stencilRefBack'] = numericBack;
        }
        break;
      case 'stencilRefFront':
        final num? numericFront = _parseNumericValue(value);
        if (numericFront != null) {
          summary['stencilRefFront'] = numericFront;
        }
        break;
      case 'stencilWriteMask':
        final num? numeric = _parseNumericValue(value);
        if (numeric != null) {
          summary['stencilWriteMask'] = numeric;
        }
        break;
      case 'stencilWriteMaskBack':
        final num? numericBack = _parseNumericValue(value);
        if (numericBack != null) {
          summary['stencilWriteMaskBack'] = numericBack;
        }
        break;
      case 'stencilWriteMaskFront':
        final num? numericFront = _parseNumericValue(value);
        if (numericFront != null) {
          summary['stencilWriteMaskFront'] = numericFront;
        }
        break;
      case 'stencilZFail':
        summary['stencilZFail'] = _normalizeEnumValue(value);
        break;
      case 'stencilZFailBack':
        summary['stencilZFailBack'] = _normalizeEnumValue(value);
        break;
      case 'stencilZFailFront':
        summary['stencilZFailFront'] = _normalizeEnumValue(value);
        break;
    }
  }

  if (blend.isNotEmpty) {
    summary['blend'] = blend;
  }
  if (colorMasks.isNotEmpty) {
    summary.addAll(colorMasks);
  }

  return summary;
}

_InlineStateAssignment? _parseInlineState(String raw) {
  final String cleaned = raw.replaceAll(';', '').trim();
  if (cleaned.isEmpty) {
    return null;
  }
  final int spaceIndex = cleaned.indexOf(RegExp(r'\s'));
  if (spaceIndex == -1) {
    return null;
  }
  final String key = cleaned.substring(0, spaceIndex).trim();
  final String value = cleaned.substring(spaceIndex + 1).trim();
  if (key.isEmpty || value.isEmpty) {
    return null;
  }
  return _InlineStateAssignment(key, value);
}

bool? _parseBoolValue(String value) {
  final String normalized = value.replaceAll(';', '').trim().toLowerCase();
  switch (normalized) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
    case 'enable':
    case 'enabled':
      return true;
    case '0':
    case 'false':
    case 'no':
    case 'off':
    case 'disable':
    case 'disabled':
      return false;
    default:
      return null;
  }
}

num? _parseNumericValue(String value) {
  final String normalized = value.replaceAll(';', '').trim();
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized.startsWith('0x') || normalized.startsWith('0X')) {
    return int.tryParse(normalized.substring(2), radix: 16);
  }
  final int? intValue = int.tryParse(normalized);
  if (intValue != null) {
    return intValue;
  }
  return double.tryParse(normalized);
}

String _normalizeEnumValue(String value) {
  String normalized = value.replaceAll(';', '').trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  normalized = normalized.replaceAll(RegExp(r'[-]+'), '_');
  normalized = normalized.replaceAll(RegExp(r'\s+'), '_');
  normalized = normalized.toUpperCase();
  return _enumAliases[normalized] ?? normalized;
}

List<String> _splitStateValues(String raw) {
  final String cleaned = raw.replaceAll(';', '').trim();
  if (cleaned.isEmpty) {
    return const [];
  }
  final List<String> tokens = cleaned
      .split(RegExp(r'[,\s]+'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList();
  return tokens.map(_normalizeEnumValue).toList();
}

Map<String, bool> _parseColorMask(String value) {
  final Map<String, bool> mask = {
    'red': false,
    'green': false,
    'blue': false,
    'alpha': false,
  };
  final String cleaned = value.replaceAll(';', '').trim();
  if (cleaned.isEmpty) {
    return mask;
  }
  final num? numeric = _parseNumericValue(cleaned);
  if (numeric != null) {
    final int bits = numeric.toInt();
    mask['red'] = (bits & 0x1) != 0;
    mask['green'] = (bits & 0x2) != 0;
    mask['blue'] = (bits & 0x4) != 0;
    mask['alpha'] = (bits & 0x8) != 0;
    return mask;
  }
  final List<String> tokens = cleaned
      .split(RegExp(r'[|,\s]+'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .map((token) => token.toUpperCase())
      .toList();
  if (tokens.isEmpty) {
    return mask;
  }
  for (final String token in tokens) {
    switch (token) {
      case 'RGBA':
      case 'RGB_A':
      case 'ALL':
        mask.updateAll((_, __) => true);
        break;
      case 'RGB':
        mask['red'] = true;
        mask['green'] = true;
        mask['blue'] = true;
        break;
      case 'NONE':
        mask.updateAll((_, __) => false);
        break;
      case 'RED':
      case 'R':
        mask['red'] = true;
        break;
      case 'GREEN':
      case 'G':
        mask['green'] = true;
        break;
      case 'BLUE':
      case 'B':
        mask['blue'] = true;
        break;
      case 'ALPHA':
      case 'A':
        mask['alpha'] = true;
        break;
    }
  }
  return mask;
}

List<String> extractVertexAttributes(List<Block> blocks) {
  for (final Block block in blocks) {
    if (block.name.toLowerCase() == 'vertattributes') {
      String content = block.content.replaceAll('{', ' ').replaceAll('}', ' ');
      final List<String> tokens = content
          .split(RegExp(r'\s+'))
          .map((token) => token.trim())
          .where((token) => token.isNotEmpty)
          .toList();
      return tokens;
    }
  }
  return const [];
}

List<String> extractDirectives(String content) {
  final List<String> directives = [];
  const Set<String> allowed = {
    'PS20Only',
    'PS30Only',
    'PS20Fragment',
    'Projected',
    'Projected_Clip',
    'ProjectedClip',
    'TwoSided',
    'HalfPrecision',
    'HalfPrecisionOnly',
    'FogDisable',
  };
  for (final String rawLine in content.split('\n')) {
    final String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('//')) {
      continue;
    }
    if (line.contains('{') || line.contains('}') || line.contains(' ')) {
      continue;
    }
    if (allowed.contains(line)) {
      directives.add(line);
    }
  }
  return directives;
}

List<Map<String, dynamic>> extractCoreScriptFlow(List<Block> blocks) {
  Block? coreBlock;
  for (final Block block in blocks) {
    if (block.name.toLowerCase() == 'corescript') {
      coreBlock = block;
      break;
    }
  }
  if (coreBlock == null) {
    return const [];
  }
  return _buildCoreScriptFlow(coreBlock.content);
}

List<String> extractMaskReferences(String content) {
  final Set<String> tokens = <String>{};
  final RegExp percentPattern = RegExp(r'%([A-Za-z0-9_]+)');
  for (final Match match in percentPattern.allMatches(content)) {
    final String? value = match.group(1);
    if (value != null && value.isNotEmpty) {
      tokens.add(value);
    }
  }
  final RegExp ifdefPattern = RegExp(
    r'#\s*(?:ifn?def|ifdef|ifndef)\s+([A-Za-z_][A-Za-z0-9_]*)',
  );
  for (final Match match in ifdefPattern.allMatches(content)) {
    final String? value = match.group(1);
    if (value != null && value.isNotEmpty) {
      tokens.add(value);
    }
  }
  final RegExp definedPattern = RegExp(
    r'defined\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)',
  );
  for (final Match match in definedPattern.allMatches(content)) {
    final String? value = match.group(1);
    if (value != null && value.isNotEmpty) {
      tokens.add(value);
    }
  }
  final List<String> result = tokens.toList();
  result.sort();
  return result;
}

List<String> extractPositionScripts(String content) {
  final RegExp pattern = RegExp(
    r'PositionScript\s*=\s*([A-Za-z_][A-Za-z0-9_]*)',
  );
  final Set<String> scripts = <String>{};
  for (final RegExpMatch match in pattern.allMatches(content)) {
    final String? script = match.group(1);
    if (script != null && script.isNotEmpty) {
      scripts.add(script.trim());
    }
  }
  final List<String> result = scripts.toList();
  result.sort();
  return result;
}

List<Map<String, String>> extractPositionScriptBlocks(List<Block> blocks) {
  final List<Map<String, String>> scripts = <Map<String, String>>[];
  for (final Block block in blocks) {
    final String lower = block.name.toLowerCase();
    if (!lower.startsWith('positionscript')) {
      continue;
    }
    String name = '';
    final RegExpMatch? match = RegExp(
      r'positionscript\s*=\s*([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false,
    ).firstMatch(block.name);
    if (match != null) {
      name = match.group(1) ?? '';
    }
    scripts.add({'name': name, 'content': block.content});
  }
  return scripts;
}

Map<String, String> extractOutputFieldTypes(List<Block> blocks) {
  final Map<String, String> result = <String, String>{};
  final RegExp macroPattern = RegExp(r'OUT_[A-Za-z0-9_]+');
  for (final Block block in blocks) {
    if (block.name.toLowerCase() != 'declarationsscript') {
      continue;
    }
    for (final RegExpMatch match in macroPattern.allMatches(block.content)) {
      final String macro = match.group(0)!;
      final _OutputFieldSpec? spec = _mapOutputMacroToSpec(macro);
      if (spec != null) {
        result.putIfAbsent(spec.field, () => spec.type);
      }
    }
    final RegExp structPattern = RegExp(
      r'struct\s+vertout\s*\{([\s\S]*?)\};',
      multiLine: true,
    );
    final RegExpMatch? structMatch = structPattern.firstMatch(block.content);
    if (structMatch != null) {
      final String body = structMatch.group(1)!;
      final List<String> structLines = body.split('\n');
      for (final String rawLine in structLines) {
        final String line = rawLine.trim();
        if (line.isEmpty ||
            line.startsWith('//') ||
            line.startsWith('#')) {
          continue;
        }
        final RegExpMatch? fieldMatch = RegExp(
          r'(float[0-9]*(?:x[0-9]+)?)\s+([A-Za-z0-9_]+)',
        ).firstMatch(line);
        if (fieldMatch != null) {
          final String type = fieldMatch.group(1)!;
          final String name = fieldMatch.group(2)!;
          result.putIfAbsent(name, () => type);
        }
      }
    }
  }
  return result;
}

List<Map<String, dynamic>> _buildCoreScriptFlow(String content) {
  final List<Map<String, dynamic>> flow = [];
  final List<String> lines = content.split('\n');
  int depth = 0;
  for (final String rawLine in lines) {
    if (rawLine.isEmpty) {
      continue;
    }
    String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('//')) {
      continue;
    }

    int leadingClosures = 0;
    while (line.startsWith('}')) {
      leadingClosures++;
      line = line.substring(1).trimLeft();
    }
    if (leadingClosures > 0) {
      depth = depth - leadingClosures;
      if (depth < 0) {
        depth = 0;
      }
    }
    if (line.isEmpty) {
      continue;
    }

    final bool opensBlock = line.endsWith('{');
    String contentText = opensBlock
        ? line.substring(0, line.length - 1).trimRight()
        : line;
    if (contentText.endsWith(';')) {
      contentText = contentText
          .substring(0, contentText.length - 1)
          .trimRight();
    }
    final String type = _classifyFlowLine(contentText);

    flow.add({
      'indent': depth,
      'type': type,
      'content': contentText,
      'opensBlock': opensBlock,
    });

    if (opensBlock) {
      depth++;
    }
    final int trailingClosures = _countCharacter(line, '}');
    if (trailingClosures > 0) {
      depth = depth - trailingClosures;
      if (depth < 0) {
        depth = 0;
      }
    }
  }
  return flow;
}

String _classifyFlowLine(String line) {
  final String lower = line.toLowerCase();
  if (lower.startsWith('if ') || lower.startsWith('if(')) {
    return 'if';
  }
  if (lower.startsWith('else if')) {
    return 'else_if';
  }
  if (lower == 'else') {
    return 'else';
  }
  if (lower.startsWith('for ') || lower.startsWith('for(')) {
    return 'for';
  }
  if (lower.startsWith('while ') || lower.startsWith('while(')) {
    return 'while';
  }
  if (lower.startsWith('do ')) {
    return 'do';
  }
  if (lower.startsWith('switch ') || lower.startsWith('switch(')) {
    return 'switch';
  }
  if (lower.startsWith('case ') || lower.startsWith('default')) {
    return 'case';
  }
  if (lower.startsWith('#')) {
    return 'directive';
  }
  if (lower.startsWith('return')) {
    return 'return';
  }
  return 'statement';
}

int _countCharacter(String source, String charValue) {
  int count = 0;
  for (int i = 0; i < source.length; i++) {
    if (source[i] == charValue) {
      count++;
    }
  }
  return count;
}

int skipLine(String content, int index) {
  final int newline = content.indexOf('\n', index);
  return newline == -1 ? content.length : newline + 1;
}

int skipBlockComment(String content, int index) {
  final int end = content.indexOf('*/', index);
  return end == -1 ? content.length : end + 2;
}

int skipString(String content, int index, int quote) {
  while (index < content.length) {
    final int code = content.codeUnitAt(index);
    if (code == quote) return index + 1;
    if (code == 92 && index + 1 < content.length) {
      index += 2;
      continue;
    }
    index++;
  }
  return content.length;
}

int skipWhitespace(String content, int index) {
  while (index < content.length) {
    final int code = content.codeUnitAt(index);
    if (code != 32 && code != 9 && code != 10 && code != 13) break;
    index++;
  }
  return index;
}

bool isIdentifierStart(int code) {
  return (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 95;
}

bool isIdentifierPart(int code) {
  return isIdentifierStart(code) || (code >= 48 && code <= 57);
}

int findMatchingBrace(String content, int braceIndex) {
  int index = braceIndex + 1;
  int depth = 1;
  while (index < content.length) {
    final int code = content.codeUnitAt(index);
    if (code == 47 && index + 1 < content.length) {
      final int next = content.codeUnitAt(index + 1);
      if (next == 47) {
        index = skipLine(content, index + 2);
        continue;
      } else if (next == 42) {
        index = skipBlockComment(content, index + 2);
        continue;
      }
    }
    if (code == 34 || code == 39) {
      index = skipString(content, index + 1, code);
      continue;
    }
    if (code == 123) {
      depth++;
      index++;
      continue;
    }
    if (code == 125) {
      depth--;
      if (depth == 0) return index;
      index++;
      continue;
    }
    index++;
  }
  return -1;
}
