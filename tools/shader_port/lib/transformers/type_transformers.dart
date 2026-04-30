part of '../metal_generator.dart';

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
