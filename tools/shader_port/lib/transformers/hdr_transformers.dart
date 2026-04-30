part of '../metal_generator.dart';

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
