import 'package:shader_port/parser.dart';
import 'package:test/test.dart';

void main() {
  group('parser', () {
    test('extracts mask references, flow, and summaries', () {
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

      expect(result.maskReferences, contains('D3D'));
      expect(result.maskReferences, contains('FEATURE_ENABLED'));
      expect(result.maskReferences, contains('USE_EXTRA'));
      expect(result.positionScripts, isEmpty);
      expect(result.outputFieldTypes, isEmpty);

      expect(result.coreScriptFlow, isNotEmpty);
      expect(
        result.coreScriptFlow,
        anyElement(
          predicate(
            (dynamic node) =>
                node is Map<String, dynamic> &&
                node['type'] == 'if' &&
                node['indent'] == 0,
          ),
        ),
      );
      expect(
        result.coreScriptFlow,
        anyElement(
          predicate(
            (dynamic node) =>
                node is Map<String, dynamic> && node['type'] == 'else',
          ),
        ),
      );
      expect(
        result.coreScriptFlow,
        anyElement(
          predicate(
            (dynamic node) =>
                node is Map<String, dynamic> && node['type'] == 'for',
          ),
        ),
      );

      final Map<String, dynamic> pass = result.passStates.firstWhere(
        (Map<String, dynamic> state) => state['block'] == 'Pass0',
      );
      final List<dynamic> entries =
          (pass['entries'] as List<dynamic>? ?? const <dynamic>[]);
      expect(
        entries,
        anyElement(
          predicate(
            (dynamic entry) =>
                entry is Map<String, dynamic> &&
                entry['type'] == 'assignment' &&
                entry['key'] == 'CullMode' &&
                entry['value'] == 'Back',
          ),
        ),
      );
      expect(
        entries,
        anyElement(
          predicate(
            (dynamic entry) =>
                entry is Map<String, dynamic> &&
                entry['type'] == 'call' &&
                entry['value'] == 'SetTexture(0, baseMap)',
          ),
        ),
      );

      final Map<String, dynamic> summary =
          (pass['stateSummary'] as Map<String, dynamic>? ??
              const <String, dynamic>{});
      expect(summary['cullMode'], 'BACK');
      expect(summary['alphaTest'], isTrue);
      expect(summary['depthWrite'], isFalse);

      final Map<String, dynamic> blend =
          (summary['blend'] as Map<String, dynamic>? ??
              const <String, dynamic>{});
      expect(blend['enabled'], isTrue);
      expect(blend['src'], 'SRCALPHA');
      expect(
        blend['dst'],
        anyOf('INVSRCALPHA', 'ONE_MINUS_SRC_ALPHA'),
      );

      final Map<String, dynamic> colorMask =
          (summary['colorMask'] as Map<String, dynamic>? ??
              const <String, dynamic>{});
      expect(colorMask['red'], isTrue);
      expect(colorMask['green'], isTrue);
      expect(colorMask['blue'], isTrue);
      expect(colorMask['alpha'], isFalse);

      final Map<String, dynamic> colorMask1 =
          (summary['colorMask1'] as Map<String, dynamic>? ??
              const <String, dynamic>{});
      expect(colorMask1, isNotEmpty);
      expect(
        colorMask1.values,
        everyElement(isFalse),
      );
      final num alphaRef = summary['alphaRef'] as num? ?? -1;
      expect(alphaRef, closeTo(0.5, 0.001));
    });
  });
}
