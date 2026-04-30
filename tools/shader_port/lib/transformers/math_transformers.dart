part of '../metal_generator.dart';

class FracFunctionTransformer implements LineTransformer {
  @override
  String transform(String line) {
    return line.replaceAll('frac(', 'fract(');
  }
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
