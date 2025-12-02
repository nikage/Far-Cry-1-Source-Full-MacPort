import 'package:shader_port/metal_generator.dart';
import 'package:test/test.dart';

void main() {
  group('metal generator', () {
    test('builds fragment and pipeline metadata', () {
      const String shaderName = 'TestShader';
      final String normalized = normalizeName(shaderName);
      final String fragmentName = 'generated_${normalized}_fragment';
      final String uniformStruct = '${normalized}_uniforms';

      final List<UniformBinding> uniforms = <UniformBinding>[
        UniformBinding('float4', 'Ambient', ''),
      ];
      final List<TextureBinding> textures = <TextureBinding>[
        TextureBinding('sampler2D', 'baseMap', 0, ''),
      ];
      final List<Map<String, dynamic>> expressions = <Map<String, dynamic>>[
        {
          'type': 'assignment',
          'lhs': 'float4 decalColor',
          'rhs': 'tex2D(baseMap, IN.Tex0.xy)',
          'raw': 'float4 decalColor = tex2D(baseMap, IN.Tex0.xy);',
        },
        {
          'type': 'assignment',
          'lhs': 'float intensity',
          'rhs': 'saturate(IN.Color.x)',
          'raw': 'float intensity = saturate(IN.Color.x);',
        },
        {
          'type': 'assignment',
          'lhs': 'OUT.Color.xyz',
          'rhs': 'decalColor.xyz * intensity',
          'raw': 'OUT.Color.xyz = decalColor.xyz * intensity;',
        },
        {
          'type': 'assignment',
          'lhs': 'OUT.Color',
          'rhs': 'float4(decalColor.xyz, 1.0)',
          'raw': 'OUT.Color = float4(decalColor.xyz, 1.0);',
        },
      ];
      final List<Map<String, dynamic>> flow = <Map<String, dynamic>>[
        {
          'type': 'if',
          'content': 'if (IN.Color.x > 0.5)',
          'indent': 0,
          'opensBlock': true,
        },
      ];

      final ShaderIrData data = ShaderIrData(
        shaderName: shaderName,
        normalizedName: normalized,
        fragmentName: fragmentName,
        uniformStruct: uniformStruct,
        uniforms: uniforms,
        textures: textures,
        coreExpressions: expressions,
        coreMacros: const [],
        coreFlow: flow,
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const ['MASK_FEATURE', 'MASK_FOG'],
      );

      final String code = buildMetal(data);
      expect(code, contains('struct ${normalized}_input'));
      expect(code, contains('float4 Tex0;'));
      expect(code, contains('float4 Color;'));
      expect(
        code,
        contains('baseMap.sample(baseMapSampler, IN.Tex0.xy)'),
      );
      expect(
        code,
        contains('float intensity = clamp(IN.Color.x, 0.0, 1.0);'),
      );
      expect(code, contains('return OUT.Color;'));

      final Map<String, dynamic> pipeline = derivePipelineMetadata(
        shaderName,
        const [],
        <Map<String, dynamic>>[
          {
            'stateSummary': {
              'blend': {
                'enabled': true,
                'src': 'SRCALPHA',
                'dst': 'INVSRCALPHA',
              },
              'depthWrite': false,
              'depthTest': true,
              'depthFunc': 'LESS_EQUAL',
              'cullMode': 'NONE',
              'colorMask': {
                'red': true,
                'green': true,
                'blue': true,
                'alpha': false,
              },
            },
          },
        ],
      );

      expect(pipeline['blendEnabled'], isTrue);
      expect(pipeline['blendMode'], 'alpha');
      final Map<String, dynamic> blendFactors =
          (pipeline['blendFactors'] as Map<String, dynamic>? ??
              const <String, dynamic>{});
      expect(blendFactors['src'], 'SRCALPHA');
      expect(blendFactors['dst'], anyOf('INVSRCALPHA', 'ONE_MINUS_SRC_ALPHA'));
      expect(pipeline['depthWrite'], isFalse);
      expect(pipeline['depthTest'], isTrue);
      expect(pipeline['depthCompare'], 'lessEqual');
      expect(pipeline['cullMode'], 'none');
      final Map<String, dynamic> colorMask =
          (pipeline['colorMask'] as Map<String, dynamic>? ??
              const <String, dynamic>{});
      expect(colorMask['red'], isTrue);
      expect(colorMask['alpha'], isFalse);
    });
  });
}
