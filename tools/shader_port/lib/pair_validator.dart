import 'dart:convert';
import 'dart:io';

class ValidationError {
  const ValidationError(this.rule, this.shader, this.message);
  final String rule;
  final String shader;
  final String message;

  @override
  String toString() => '[Rule $rule] $shader: $message';
}

class ValidatorResult {
  ValidatorResult({
    required this.errors,
    required this.warnings,
    required this.totalFragments,
    required this.pairedFragments,
    required this.fullscreenFragments,
  });

  final List<ValidationError> errors;
  final List<ValidationError> warnings;
  final int totalFragments;
  final int pairedFragments;
  final int fullscreenFragments;

  bool get passed => errors.isEmpty;

  double get coverageRatio =>
      totalFragments == 0 ? 1.0 : (pairedFragments + fullscreenFragments) / totalFragments;
}

ValidatorResult validate(List<Map<String, dynamic>> manifest) {
  final List<ValidationError> errors = [];
  final List<ValidationError> warnings = [];

  final Set<String> vertexEntryPoints = {
    for (final Map<String, dynamic> e in manifest)
      if (e['stage'] == 'vertex') e['entryPoint'] as String,
  };

  final Map<String, Map<String, dynamic>> vertexByEntryPoint = {
    for (final Map<String, dynamic> e in manifest)
      if (e['stage'] == 'vertex') e['entryPoint'] as String: e,
  };

  final List<Map<String, dynamic>> fragments = [
    for (final Map<String, dynamic> e in manifest)
      if (e['stage'] == 'fragment') e,
  ];

  int pairedCount = 0;
  int fullscreenCount = 0;

  for (final Map<String, dynamic> frag in fragments) {
    final String shader = frag['shader'] as String? ?? frag['normalized'] as String? ?? '?';
    final String? vep = frag['vertexEntryPoint'] as String?;
    final String category = frag['pipelineCategory'] as String? ?? 'mesh';

    if (vep != null) {
      pairedCount++;

      // Rule 2: vertexEntryPoint must reference a real vertex entry.
      if (!vertexEntryPoints.contains(vep)) {
        errors.add(ValidationError(
          '2',
          shader,
          'vertexEntryPoint "$vep" not found in manifest vertex entries',
        ));
        continue;
      }

      // Rule 3: structural compatibility — VS vertexOutputs must cover FS
      // vertexAttributes (by normalized name, case-insensitive).
      final Map<String, dynamic>? vertEntry = vertexByEntryPoint[vep];
      if (vertEntry != null) {
        _checkStructuralCompatibility(frag, vertEntry, shader, warnings);
      }
    } else if (category == 'fullscreen') {
      fullscreenCount++;
    } else {
      // Rule 1: every non-fullscreen fragment must have a vertexEntryPoint.
      errors.add(ValidationError(
        '1',
        shader,
        'fragment shader has no vertexEntryPoint and pipelineCategory is "$category" (not "fullscreen")',
      ));
    }
  }

  return ValidatorResult(
    errors: errors,
    warnings: warnings,
    totalFragments: fragments.length,
    pairedFragments: pairedCount,
    fullscreenFragments: fullscreenCount,
  );
}

// CG/HLSL semantic prefixes that are standard GPU-pipeline values always
// available to fragment shaders regardless of VS outputs.
final RegExp _kCgSemanticPattern = RegExp(
  r'^(position|texcoord|color|normal|binormal|tangent|blendweight|blendindices|psize|fog|depth)\d*(_\d+)?$',
  caseSensitive: false,
);

void _checkStructuralCompatibility(
  Map<String, dynamic> frag,
  Map<String, dynamic> vert,
  String shaderName,
  List<ValidationError> warnings,
) {
  final dynamic vsOutputsRaw = vert['vertexOutputs'];
  if (vsOutputsRaw is! List || vsOutputsRaw.isEmpty) return;

  final dynamic fsAttrsRaw = frag['vertexAttributes'];
  if (fsAttrsRaw is! List || fsAttrsRaw.isEmpty) return;

  final Set<String> vsOutputNames = {
    for (final dynamic o in vsOutputsRaw)
      if (o is Map<String, dynamic> && o['name'] is String)
        (o['name'] as String).toLowerCase(),
  };

  final List<String> missingFromVs = [];
  for (final dynamic attr in fsAttrsRaw) {
    if (attr is! String) continue;
    final String trimmed = attr.trim();
    if (trimmed.isEmpty) continue;
    // Skip raw CG/HLSL semantic strings (POSITION_3, TEXCOORD0_2, etc.) —
    // these are always covered by the hardware pipeline, not by VS output names.
    if (_kCgSemanticPattern.hasMatch(trimmed)) continue;
    final String normalized = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized.isEmpty) continue;
    if (RegExp(r'^tex\d+$').hasMatch(normalized)) continue;
    if (normalized == 'hposition' || normalized == 'position') continue;
    if (!vsOutputNames.any((o) =>
        o == normalized ||
        (o.length > 4 && normalized.length > 4 && normalized.contains(o)))) {
      missingFromVs.add(trimmed);
    }
  }

  if (missingFromVs.isNotEmpty) {
    warnings.add(ValidationError(
      '3',
      shaderName,
      'VS output set may not cover FS varyings: ${missingFromVs.join(', ')}',
    ));
  }
}

ValidatorResult validateManifestFile(String manifestPath) {
  final File file = File(manifestPath);
  if (!file.existsSync()) {
    return ValidatorResult(
      errors: [
        ValidationError('0', manifestPath, 'manifest file not found'),
      ],
      warnings: [],
      totalFragments: 0,
      pairedFragments: 0,
      fullscreenFragments: 0,
    );
  }
  final dynamic raw = jsonDecode(file.readAsStringSync(encoding: utf8));
  if (raw is! List) {
    return ValidatorResult(
      errors: [ValidationError('0', manifestPath, 'manifest root must be a JSON array')],
      warnings: [],
      totalFragments: 0,
      pairedFragments: 0,
      fullscreenFragments: 0,
    );
  }
  final List<Map<String, dynamic>> manifest = [
    for (final dynamic e in raw)
      if (e is Map<String, dynamic>) e,
  ];
  return validate(manifest);
}
