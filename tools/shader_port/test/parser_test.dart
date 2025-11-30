import 'dart:io';

import '../lib/parser.dart';

void main() {
  final String shaderSource = '''
#ifdef D3D
#endif

MainInput { uniform sampler2D baseMap : texunit0; }

Pass0
{
  CullMode = Back;
  AlphaTest = On;
  DepthWrite = Off;
  Blend = On;
  BlendFunc = SrcAlpha, OneMinusSrcAlpha;
  ColorWriteEnable = Red|Green|Blue;
  ColorWriteEnable1 = 0;
  AlphaRef = 0.5;
  SetTexture(0, baseMap);
}

CoreScript
{
  if (IN.Color.x > 0.5)
  {
    OUT.Color = float4(1, 0, 0, 1);
  }
  else
  {
    OUT.Color = float4(0, 1, 0, 1);
  }
  for (int i = 0; i < 4; ++i)
  {
    OUT.Color.xyz += IN.Data[i];
  }
#if %FEATURE_ENABLED
  OUT.Color *= Constants;
#endif
#if defined(USE_EXTRA)
  OUT.Color.xyz += float3(0.1, 0.1, 0.1);
#endif
}
''';

  final ParseResult result = parseShaderFromSource(
    shaderSource,
    'Testing/Example.crycg',
  );

  _check(result.maskReferences.contains('D3D'), 'expected D3D reference');
  _check(
    result.maskReferences.contains('FEATURE_ENABLED'),
    'expected FEATURE_ENABLED reference',
  );
  _check(
    result.maskReferences.contains('USE_EXTRA'),
    'expected USE_EXTRA reference',
  );
  _check(result.positionScripts.isEmpty, 'expected no position scripts');
  _check(result.outputFieldTypes.isEmpty, 'expected no output field overrides');

  _check(
    result.coreScriptFlow.isNotEmpty,
    'coreScriptFlow should not be empty',
  );
  _check(
    result.coreScriptFlow.any(
      (node) => node['type'] == 'if' && node['indent'] == 0,
    ),
    'expected top-level if node',
  );
  _check(
    result.coreScriptFlow.any((node) => node['type'] == 'else'),
    'expected else node in flow',
  );
  _check(
    result.coreScriptFlow.any((node) => node['type'] == 'for'),
    'expected for node in flow',
  );

  final Map<String, dynamic> pass = result.passStates.firstWhere(
    (state) => state['block'] == 'Pass0',
    orElse: () => throw StateError('Pass0 not found'),
  );
  final List<dynamic> entries = (pass['entries'] as List<dynamic>? ?? const []);
  _check(
    entries.any(
      (entry) =>
          entry is Map<String, dynamic> &&
          entry['type'] == 'assignment' &&
          entry['key'] == 'CullMode' &&
          entry['value'] == 'Back',
    ),
    'expected CullMode assignment in pass entries',
  );
  _check(
    entries.any(
      (entry) =>
          entry is Map<String, dynamic> &&
          entry['type'] == 'call' &&
          entry['value'] == 'SetTexture(0, baseMap)',
    ),
    'expected SetTexture call in pass entries',
  );

  final Map<String, dynamic> summary =
      (pass['stateSummary'] as Map<String, dynamic>? ??
      const <String, dynamic>{});
  _check(summary['cullMode'] == 'BACK', 'expected cullMode summary');
  _check(summary['alphaTest'] == true, 'expected alphaTest boolean summary');
  _check(summary['depthWrite'] == false, 'expected depthWrite boolean summary');
  final Map<String, dynamic> blend =
      (summary['blend'] as Map<String, dynamic>? ?? const <String, dynamic>{});
  _check(blend['enabled'] == true, 'expected blend enabled');
  final String? srcFactor = blend['src'] as String?;
  final String? dstFactor = blend['dst'] as String?;
  _check(srcFactor == 'SRCALPHA', 'expected src blend factor');
  _check(
    dstFactor == 'INVSRCALPHA' || dstFactor == 'ONE_MINUS_SRC_ALPHA',
    'expected dst blend factor',
  );
  final Map<String, dynamic> colorMask =
      (summary['colorMask'] as Map<String, dynamic>? ??
      const <String, dynamic>{});
  _check(colorMask['red'] == true, 'expected red color mask');
  _check(colorMask['green'] == true, 'expected green color mask');
  _check(colorMask['blue'] == true, 'expected blue color mask');
  _check(colorMask['alpha'] == false, 'expected alpha mask disabled');
  final Map<String, dynamic> colorMask1 =
      (summary['colorMask1'] as Map<String, dynamic>? ??
      const <String, dynamic>{});
  _check(colorMask1.isNotEmpty, 'expected secondary color mask entry');
  _check(
    colorMask1.values.every((dynamic value) => value == false),
    'expected secondary color mask disabled',
  );
  final num alphaRef = summary['alphaRef'] as num? ?? -1;
  _check((alphaRef - 0.5).abs() < 0.001, 'expected alphaRef summary');

  stdout.writeln('parser_test: all checks passed');
}

void _check(bool condition, String message) {
  if (!condition) {
    stderr.writeln('Test failure: $message');
    exit(1);
  }
}
