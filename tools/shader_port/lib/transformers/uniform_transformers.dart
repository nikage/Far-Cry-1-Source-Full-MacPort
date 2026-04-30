part of '../metal_generator.dart';

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
    final int wsEnd = index;
    int wsStart = wsEnd;
    while (wsStart > 0 && line[wsStart - 1] == ' ') {
      wsStart--;
    }
    if (wsStart == wsEnd) {
      return false;
    }
    int tokenEnd = wsStart;
    int tokenStart = tokenEnd;
    while (tokenStart > 0 &&
        _isIdentChar(line[tokenStart - 1])) {
      tokenStart--;
    }
    if (tokenStart == tokenEnd) {
      return false;
    }
    final String token = line.substring(tokenStart, tokenEnd);
    const List<String> typeRoots = <String>[
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
    return typeRoots.any((String r) => token.startsWith(r));
  }

  static bool _isIdentChar(String c) =>
      (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) ||
      (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ||
      (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122) ||
      c == '_';
}
