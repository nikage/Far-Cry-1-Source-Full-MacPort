import 'dart:convert' as dart_convert;
import 'dart:io';

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
      expect(result.vertexAttributes, contains('TNORMAL_3'));
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

    test('captures appin declarations with scalar components', () {
      final String shaderSource = '''
DeclarationsScript
{
  struct appin
  {
    float4 Position : POSITION;
    float  HeightMap : BLENDWEIGHT;
  };
}
CoreScript
{
  OUT.Color = float4(IN.HeightMap, 0, 0, 1);
}
''';

      final ParseResult result = parseShaderFromSource(
        shaderSource,
        'Testing/AppinDeclarations.crycg',
      );

      final Map<String, dynamic> heightMapEntry = result.vertexAttributeMetadata
          .firstWhere((Map<String, dynamic> entry) => entry['token'] == 'HeightMap');
      expect(heightMapEntry['components'], 1);
      expect(heightMapEntry['source'], 'declaration');
      expect(heightMapEntry['semantic'], 'BLENDWEIGHT');
    });

    test('captures appin macros defined with IN_* tokens', () {
      final String shaderSource = '''
DeclarationsScript
{
  struct appin
  {
    IN_P
    IN_N
    IN_C0
    IN_T0
  };
}
CoreScript
{
  OUT.Color = IN.Color;
}
''';

      final ParseResult result = parseShaderFromSource(
        shaderSource,
        'Testing/AppinMacros.crycg',
      );

      final Map<String, dynamic> positionEntry = result.vertexAttributeMetadata
          .firstWhere((Map<String, dynamic> entry) => entry['token'] == 'Position');
      expect(positionEntry['components'], 4);
      expect(positionEntry['source'], 'macro');

      final Map<String, dynamic> normalEntry = result.vertexAttributeMetadata
          .firstWhere((Map<String, dynamic> entry) => entry['token'] == 'Normal');
      expect(normalEntry['components'], 3);
      expect(normalEntry['source'], 'macro');
    });

    test('macro metadata overrides explicit VertAttributes components', () {
      final String shaderSource = '''
VertAttributes { POSITION_3 TEXCOORD0_2 }
DeclarationsScript
{
  struct appin
  {
    IN_P
  };
}
CoreScript
{
  OUT.Color = float4(IN.Position, 1.0);
}
''';

      final ParseResult result = parseShaderFromSource(
        shaderSource,
        'Testing/PositionMacroOverride.crycg',
      );

      final Map<String, dynamic> positionEntry = result.vertexAttributeMetadata
          .firstWhere((Map<String, dynamic> entry) => entry['token'] == 'Position');
      expect(positionEntry['components'], 4);
      expect(positionEntry['source'], 'macro');
    });

    test('declarations override explicit vector component counts', () {
      final String shaderSource = '''
VertAttributes { BLENDWEIGHT_4 }
DeclarationsScript
{
  struct appin
  {
    float HeightMap : BLENDWEIGHT;
  };
}
CoreScript
{
  OUT.Color = float4(IN.HeightMap.xxx, 1.0);
}
''';

      final ParseResult result = parseShaderFromSource(
        shaderSource,
        'Testing/HeightMapDeclarationOverride.crycg',
      );

      final Map<String, dynamic> heightMapEntry = result.vertexAttributeMetadata
          .firstWhere((Map<String, dynamic> entry) => entry['token'] == 'HeightMap');
      expect(heightMapEntry['components'], 1);
      expect(heightMapEntry['source'], 'declaration');
    });

    test('captures vertout macros with component overrides', () {
      final String shaderSource = '''
DeclarationsScript
{
  struct vertout
  {
    float2 customTC : TEXCOORD2;
    OUT_T0
    OUT_T1_2
  };
  OUT_T0_T1_C0
  OUT_T5_2
  OUT_Color1
}
CoreScript
{
}
''';

      final ParseResult result = parseShaderFromSource(
        shaderSource,
        'Testing/VertoutDeclarations.crycg',
      );

      expect(result.outputFieldTypes['customTC'], 'float2');
      expect(result.outputFieldTypes['Tex0'], 'float4');
      expect(result.outputFieldTypes['Tex1'], 'float2');
      expect(result.outputFieldTypes['Tex5'], 'float2');
      expect(result.outputFieldTypes['Color'], 'float4');
      expect(result.outputFieldTypes['Color1'], 'float4');
    });
  });

  group('encodeResult', () {
    test('encodes name, extension, and path correctly', () {
      final ParseResult result = parseShaderFromSource(
        'MainInput { uniform float4 Color; }\nCoreScript { OUT.Color = Color; }',
        'Shaders/Simple.crycg',
      );
      final String json = encodeResult(result);
      final dynamic decoded = dart_convert.jsonDecode(json);
      expect(decoded['name'], 'Simple');
      expect(decoded['extension'], 'crycg');
      expect(decoded['path'], 'Shaders/Simple.crycg');
    });

    test('encodes blocks with name and content', () {
      final ParseResult result = parseShaderFromSource(
        'MainInput { uniform float4 Color; }',
        'Shaders/Test.crycg',
      );
      final String json = encodeResult(result);
      final dynamic decoded = dart_convert.jsonDecode(json);
      final List<dynamic> blocks = decoded['blocks'] as List<dynamic>;
      expect(blocks, isNotEmpty);
      expect(blocks.first['name'], 'MainInput');
    });

    test('encodes maskReferences list', () {
      final ParseResult result = parseShaderFromSource(
        '#ifdef D3D\n#endif\nCoreScript {}',
        'Shaders/Mask.crycg',
      );
      final String json = encodeResult(result);
      final dynamic decoded = dart_convert.jsonDecode(json);
      expect((decoded['maskReferences'] as List<dynamic>), contains('D3D'));
    });

    test('round-trips: decoding and re-encoding produces same JSON', () {
      const String source = '''
MainInput { uniform float4 Tint : COLOR; }
CoreScript
{
  OUT.Color = Tint;
}
''';
      final ParseResult result = parseShaderFromSource(source, 'Shaders/RoundTrip.crycg');
      final String json1 = encodeResult(result);
      final dynamic decoded = dart_convert.jsonDecode(json1);
      expect(decoded['name'], isA<String>());
      expect(decoded['coreScriptExpressions'], isA<List<dynamic>>());
      expect(decoded['passStates'], isA<List<dynamic>>());
      expect(decoded['vertexAttributes'], isA<List<dynamic>>());
    });

    test('omits compilerMetadata key when null', () {
      final ParseResult result = parseShaderFromSource(
        'CoreScript { }',
        'Shaders/NoMeta.crycg',
      );
      final String json = encodeResult(result);
      expect(json, isNot(contains('compilerMetadata')));
    });

    test('includes compilerMetadata when provided', () {
      final ParseResult result = parseShaderFromSource(
        'CoreScript { }',
        'Shaders/WithMeta.crycg',
        compilerMetadata: <String, dynamic>{'EntryPoint': 'main'},
      );
      final String json = encodeResult(result);
      final dynamic decoded = dart_convert.jsonDecode(json);
      expect(decoded['compilerMetadata']['EntryPoint'], 'main');
    });
  });

  group('parseShader (file-backed)', () {
    test('produces same result as parseShaderFromSource for same content', () {
      final Directory tmpDir = Directory.systemTemp.createTempSync('parser_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      const String source =
          'MainInput { uniform float4 Ambient; }\nCoreScript { OUT.Color = Ambient; }';
      final File shaderFile = File('${tmpDir.path}/Ambient.crycg')
        ..writeAsStringSync(source);
      final ParseResult fileResult =
          parseShader(shaderFile, 'Testing/Ambient.crycg');
      final ParseResult sourceResult =
          parseShaderFromSource(source, 'Testing/Ambient.crycg');
      expect(fileResult.name, sourceResult.name);
      expect(fileResult.extension, sourceResult.extension);
      expect(fileResult.blocks.length, sourceResult.blocks.length);
      expect(fileResult.maskReferences, equals(sourceResult.maskReferences));
    });

    test('name and extension are derived from the relativePath argument', () {
      final Directory tmpDir = Directory.systemTemp.createTempSync('parser_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final File shaderFile = File('${tmpDir.path}/ignored_filename.crycg')
        ..writeAsStringSync('CoreScript {}');
      final ParseResult result =
          parseShader(shaderFile, 'MyDir/ActualName.crycg');
      expect(result.name, 'ActualName');
      expect(result.extension, 'crycg');
    });
  });
}
