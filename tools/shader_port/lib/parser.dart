import 'dart:convert';
import 'dart:io';

class Block {
  Block(this.name, this.content);
  final String name;
  final String content;
}

class ParseResult {
  ParseResult(this.name, this.extension, this.relativePath, this.includes, this.blocks);
  final String name;
  final String extension;
  final String relativePath;
  final List<String> includes;
  final List<Block> blocks;
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
  return ParseResult(name, extension, relativePath, includes, blocks);
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
        .toList()
  };
  return const JsonEncoder.withIndent('  ').convert(map);
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
