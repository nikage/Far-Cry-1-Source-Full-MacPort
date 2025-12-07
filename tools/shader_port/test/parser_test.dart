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
#define CUSTOM_ALIAS fDif
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
#ifdef D3D
  OUT.Color += tex2D(baseMap, IN.Tex0.xy);
#else
  OUT.Color += tex2D(baseMap, IN.Tex1.xy);
#endif
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

      final List<Map<String, dynamic>> coreExpressions =
          List<Map<String, dynamic>>.from(result.coreScriptExpressions);
      final Map<String, dynamic> d3dSample = coreExpressions.firstWhere(
        (Map<String, dynamic> entry) =>
            (entry['raw'] as String? ?? '').contains('IN.Tex0.xy'),
      );
      expect(d3dSample['active'], isTrue);
      expect(d3dSample['guards'], isNotEmpty);
      final List<dynamic> d3dGuards =
          d3dSample['guards'] as List<dynamic>? ?? const [];
      expect(
        d3dGuards,
        anyElement(
          predicate(
            (dynamic guard) =>
                guard is Map<String, dynamic> &&
                guard['directive'] == '#ifdef' &&
                guard['state'] == 'true',
          ),
        ),
      );
      final Map<String, dynamic> oglSample = coreExpressions.firstWhere(
        (Map<String, dynamic> entry) =>
            (entry['raw'] as String? ?? '').contains('IN.Tex1.xy'),
      );
      expect(oglSample['active'], isFalse);

      expect(result.coreMacros, isNotEmpty);
      final Map<String, dynamic> macro = result.coreMacros.first;
      expect(macro['name'], 'CUSTOM_ALIAS');
      expect(macro['value'], 'fDif');
      expect(macro['active'], isTrue);

      expect(result.vertexAttributes, contains('TEXCOORD0_2'));
      expect(result.vertexAttributes, contains('TEXCOORD1_2'));
      expect(
        result.vertexAttributes,
        anyElement(
          predicate(
            (dynamic entry) =>
                entry is String && entry.startsWith('COLOR_'),
          ),
        ),
      );
      expect(result.vertexAttributeMetadata, isNotEmpty);
      final Map<String, dynamic> tex0Meta = result.vertexAttributeMetadata
          .firstWhere(
            (Map<String, dynamic> entry) =>
                entry['token'] == 'Tex0' && entry['category'] == 'texcoord',
          );
      expect(tex0Meta['components'], greaterThanOrEqualTo(2));
      expect(tex0Meta['label'], 'TEXCOORD0_2');
    });

    test('expands tangent frame attributes from VertAttributes', () {
      final String shaderSource = '''
VertAttributes { POSITION_3 TANG_3X3 TEXCOORD0_2 }
MainInput { VIEWPROJ_MATRIX }
CoreScript
{
  TANG_MATR
  OUT.Tex0.xy = IN.TexCoord0.xy;
}
''';

      final ParseResult result = parseShaderFromSource(
        shaderSource,
        'Testing/TangentFrame.crycg',
      );

      expect(result.vertexAttributes, contains('POSITION_3'));
      expect(result.vertexAttributes, contains('TANGENT_3'));
      expect(result.vertexAttributes, contains('BINORMAL_3'));
      expect(result.vertexAttributes, contains('NORMAL_3'));
      expect(result.vertexAttributes, contains('TEXCOORD0_2'));

      expect(
        result.vertexAttributeMetadata,
        anyElement(
          predicate(
            (dynamic entry) =>
                entry is Map<String, dynamic> && entry['token'] == 'Tangent',
          ),
        ),
      );
      expect(
        result.vertexAttributeMetadata,
        anyElement(
          predicate(
            (dynamic entry) =>
                entry is Map<String, dynamic> && entry['token'] == 'Binormal',
          ),
        ),
      );
      expect(
        result.vertexAttributeMetadata,
        anyElement(
          predicate(
            (dynamic entry) =>
                entry is Map<String, dynamic> && entry['token'] == 'TNormal',
          ),
        ),
      );
    });

    test('infers tangent frame usage when macros require it', () {
      final String shaderSource = '''
MainInput { VIEWPROJ_MATRIX }
CoreScript
{
  TANG_MATR
  OUT.Tex0.xy = IN.TexCoord0.xy;
}
''';

      final ParseResult result = parseShaderFromSource(
        shaderSource,
        'Testing/TangentFrameUsage.crycg',
      );

      expect(
        result.vertexAttributeMetadata,
        anyElement(
          predicate(
            (dynamic entry) =>
                entry is Map<String, dynamic> && entry['token'] == 'Tangent',
          ),
        ),
      );
      expect(
        result.vertexAttributeMetadata,
        anyElement(
          predicate(
            (dynamic entry) =>
                entry is Map<String, dynamic> && entry['token'] == 'Binormal',
          ),
        ),
      );
      expect(
        result.vertexAttributeMetadata,
        anyElement(
          predicate(
            (dynamic entry) =>
                entry is Map<String, dynamic> && entry['token'] == 'TNormal',
          ),
        ),
      );
    });
  });
}
