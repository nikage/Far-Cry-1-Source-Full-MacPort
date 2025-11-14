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
    this.vertexAttributes,
    this.directives,
    this.coreScriptFlow,
    this.maskReferences,
  );

  final String name;
  final String extension;
  final String relativePath;
  final List<String> includes;
  final List<Block> blocks;
  final List<Map<String, dynamic>> textureStages;
  final List<Map<String, dynamic>> passStates;
  final List<Map<String, dynamic>> coreScriptExpressions;
  final List<String> vertexAttributes;
  final List<String> directives;
  final List<Map<String, dynamic>> coreScriptFlow;
  final List<String> maskReferences;
}

void main(List<String> args) {
  final Directory root = (args.isEmpty ? Directory.current : Directory(args.first)).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath = root.path.endsWith(sep) ? root.path : root.path + sep;
  final Directory legacyDir = Directory(rootPath + 'Shaders${sep}Legacy');
  if (!legacyDir.existsSync()) {
    stderr.writeln('Missing directory: ${legacyDir.path}');
    exit(1);
  }
  final Directory outputDir = Directory(rootPath + 'tools${sep}shader_port${sep}output${sep}ir');
  outputDir.createSync(recursive: true);
  final List<Map<String, dynamic>> index = [];
  for (final FileSystemEntity entity in legacyDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final String lower = entity.path.toLowerCase();
    if (!(lower.endsWith('.cryps') || lower.endsWith('.crycg'))) continue;
    final String relative = entity.path.substring(legacyDir.path.length + 1).replaceAll(RegExp(r'[\\/]'), '/');
    final ParseResult result = parseShader(entity, relative);
    final File targetFile = File(outputDir.path + sep + relative + '.json');
    targetFile.parent.createSync(recursive: true);
    targetFile.writeAsStringSync(encodeResult(result));
    index.add({
      'name': result.name,
      'extension': result.extension,
      'relative': relative,
      'ir': targetFile.path.substring(rootPath.length).replaceAll(RegExp(r'[\\/]'), '/'),
      'blocks': result.blocks.map((b) => b.name).toList()
    });
  }
  final File indexFile = File(outputDir.path + sep + 'index.json');
  index.sort((a, b) => a['relative'].compareTo(b['relative']));
  indexFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(index));
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
      final String line = content.substring(index, lineEnd == -1 ? content.length : lineEnd).trim();
      if (line.startsWith('#include')) {
        final int quoteStart = line.indexOf('"');
        final int quoteEnd = quoteStart == -1 ? -1 : line.indexOf('"', quoteStart + 1);
        if (quoteStart != -1 && quoteEnd != -1 && quoteEnd > quoteStart)
          includes.add(line.substring(quoteStart + 1, quoteEnd));
      }
      index = lineEnd == -1 ? content.length : lineEnd + 1;
      continue;
    }
    if (depth == 0 && isIdentifierStart(charCode)) {
      final int start = index;
      index++;
      while (index < content.length && isIdentifierPart(content.codeUnitAt(index))) index++;
      final String identifier = content.substring(start, index);
      final int nextIndex = skipWhitespace(content, index);
      if (nextIndex < content.length && content.codeUnitAt(nextIndex) == 123) {
        final int blockEnd = findMatchingBrace(content, nextIndex);
        if (blockEnd == -1) {
          index = nextIndex + 1;
          continue;
        }
        final String blockContent = content.substring(nextIndex + 1, blockEnd).trimRight();
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
  final List<Map<String, dynamic>> coreExpressions = extractCoreExpressions(blocks);
  final List<String> vertexAttributes = extractVertexAttributes(blocks);
  final List<String> directives = extractDirectives(content);
  final List<Map<String, dynamic>> coreFlow = extractCoreScriptFlow(blocks);
  final List<String> maskReferences = extractMaskReferences(content);
  return ParseResult(
    name,
    extension,
    relativePath,
    includes,
    blocks,
    textureStages,
    passStates,
    coreExpressions,
    vertexAttributes,
    directives,
    coreFlow,
    maskReferences,
  );
}

String encodeResult(ParseResult result) {
  final Map<String, dynamic> map = {
    'name': result.name,
    'extension': result.extension,
    'path': result.relativePath,
    'includes': result.includes,
    'blocks': result.blocks
        .map((block) => {
              'name': block.name,
              'content': block.content
            })
        .toList(),
    'textureStages': result.textureStages,
    'passStates': result.passStates,
    'coreScriptExpressions': result.coreScriptExpressions,
    'vertexAttributes': result.vertexAttributes,
    'directives': result.directives,
    'coreScriptFlow': result.coreScriptFlow,
    'maskReferences': result.maskReferences,
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
    final List<Map<String, String>> statements = _extractAssignments(block.content);
    if (statements.isEmpty) {
      continue;
    }
    stages.add({
      'block': block.name,
      'statements': statements,
    });
  }
  return stages;
}

List<Map<String, dynamic>> extractPassStates(List<Block> blocks) {
  final List<Map<String, dynamic>> states = [];
  for (final Block block in blocks) {
    final String lower = block.name.toLowerCase();
    if (!(lower.contains('pass') || lower.contains('state'))) {
      continue;
    }
    final List<Map<String, String>> statements = _extractAssignments(block.content);
    final List<Map<String, dynamic>> entries = _parseStateEntries(block.content);
    if (statements.isEmpty && entries.isEmpty) {
      continue;
    }
    states.add({
      'block': block.name,
      'statements': statements,
      'entries': entries,
    });
  }
  return states;
}

List<Map<String, dynamic>> extractCoreExpressions(List<Block> blocks) {
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
      });
      continue;
    }
    if (line == '{' || line == '}') {
      continue;
    }
    if (line.contains('=')) {
      final int index = line.indexOf('=');
      final String lhs = line.substring(0, index).trim();
      final String rhs = line.substring(index + 1).trim().replaceAll(';', '');
      final bool isSample = rhs.contains('tex2D') || rhs.contains('texCUBE') || rhs.contains('tex3D');
      expressions.add({
        'type': 'assignment',
        'lhs': lhs,
        'rhs': rhs,
        'textureSample': isSample,
        'raw': line,
      });
    } else {
      expressions.add({
        'type': 'statement',
        'raw': line,
      });
    }
  }
  return expressions;
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
    'FogDisable'
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
  final RegExp ifdefPattern = RegExp(r'#\s*(?:ifn?def|ifdef|ifndef)\s+([A-Za-z_][A-Za-z0-9_]*)');
  for (final Match match in ifdefPattern.allMatches(content)) {
    final String? value = match.group(1);
    if (value != null && value.isNotEmpty) {
      tokens.add(value);
    }
  }
  final RegExp definedPattern = RegExp(r'defined\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)');
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
    String contentText = opensBlock ? line.substring(0, line.length - 1).trimRight() : line;
    if (contentText.endsWith(';')) {
      contentText = contentText.substring(0, contentText.length - 1).trimRight();
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
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95;
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
