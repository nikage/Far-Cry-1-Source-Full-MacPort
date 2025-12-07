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
        stage: 'fragment',
        vertexAttributes: const [],
        vertexAttributeMetadata: const <Map<String, dynamic>>[
          {
            'token': 'Tex0',
            'category': 'texcoord',
            'semantic': 'TEXCOORD',
            'components': 2,
            'index': 0,
          },
          {
            'token': 'Color',
            'category': 'color',
            'semantic': 'COLOR',
            'components': 4,
            'index': 0,
          },
        ],
      );

      final String code = buildMetal(data);
      expect(code, contains('struct ${normalized}_input'));
      expect(code, contains('float2 Tex0;'));
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

    test('promotes dot operands for transform texture shader', () {
      final ShaderIrData data = ShaderIrData(
        shaderName: 'CGVProgTransformTexture',
        normalizedName: 'cgvprogtransformtexture',
        fragmentName: 'generated_cgvprogtransformtexture_vertex',
        uniformStruct: 'cgvprogtransformtexture_uniforms',
        uniforms: <UniformBinding>[
          UniformBinding('float4', 'MatrixRow0', ''),
          UniformBinding('float4', 'MatrixRow1', ''),
          UniformBinding('float4', 'MatrixRow2', ''),
          UniformBinding('float4', 'MatrixRow3', ''),
          UniformBinding('float4x4', 'ModelViewProj', ''),
        ],
        textures: const [],
        coreExpressions: <Map<String, dynamic>>[
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0.x',
            'rhs': 'dot(IN.TexCoord0, MatrixRow0)',
            'raw': 'OUT.Tex0.x = dot(IN.TexCoord0, MatrixRow0);',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0.y',
            'rhs': 'dot(IN.TexCoord0, MatrixRow1)',
            'raw': 'OUT.Tex0.y = dot(IN.TexCoord0, MatrixRow1);',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0.z',
            'rhs': 'dot(IN.TexCoord0, MatrixRow2)',
            'raw': 'OUT.Tex0.z = dot(IN.TexCoord0, MatrixRow2);',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0.w',
            'rhs': 'dot(IN.TexCoord0, MatrixRow3)',
            'raw': 'OUT.Tex0.w = dot(IN.TexCoord0, MatrixRow3);',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Color',
            'rhs': 'IN.Color',
            'raw': 'OUT.Color   = IN.Color;',
          },
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const ['PosCommon'],
        positionScriptBlocks: const [],
        outputFieldTypes: const {
          'HPosition': 'float4',
          'Tex0': 'float4',
          'Color': 'float4',
        },
        maskReferences: const [],
        stage: 'vertex',
        vertexAttributes: const ['COLOR_4', 'POSITION_3', 'TEXCOORD0_2'],
        vertexAttributeMetadata: const <Map<String, dynamic>>[
          {
            'token': 'Color',
            'category': 'color',
            'semantic': 'COLOR',
            'components': 4,
            'index': 0,
            'source': 'macro',
          },
          {
            'token': 'Position',
            'category': 'position',
            'semantic': 'POSITION',
            'components': 3,
            'source': 'macro',
          },
          {
            'token': 'TexCoord0',
            'category': 'texcoord',
            'semantic': 'TEXCOORD',
            'components': 2,
            'index': 0,
            'source': 'macro',
          },
        ],
      );

      final String code = buildMetal(data);
      expect(
        code,
        contains(
          'dot(float4(IN.TexCoord0.x, IN.TexCoord0.y, 0.0, 1.0), uniforms.MatrixRow0)',
        ),
      );
      expect(code, contains('OUT.HPosition = (uniforms.ModelViewProj) *'));
    });

    test('summarizes vertex outputs with component counts', () {
      final ShaderIrData data = ShaderIrData(
        shaderName: 'CGVProgTestVertex',
        normalizedName: 'cgvprogtestvertex',
        fragmentName: 'generated_cgvprogtestvertex_vertex',
        uniformStruct: 'cgvprogtestvertex_uniforms',
        uniforms: <UniformBinding>[
          UniformBinding('float4x4', 'ModelViewProj', ''),
        ],
        textures: const [],
        coreExpressions: <Map<String, dynamic>>[
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0.x',
            'rhs': 'IN.TexCoord0.x',
            'raw': 'OUT.Tex0.x = IN.TexCoord0.x;',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0.y',
            'rhs': 'IN.TexCoord0.y',
            'raw': 'OUT.Tex0.y = IN.TexCoord0.y;',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex1.xyz',
            'rhs': 'float3(IN.TexCoord0.xy, 1.0)',
            'raw': 'OUT.Tex1.xyz = float3(IN.TexCoord0.xy, 1.0);',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Color.w',
            'rhs': '1.0',
            'raw': 'OUT.Color.w = 1.0;',
          },
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {
          'HPosition': 'float4',
          'Tex0': 'float4',
          'Tex1': 'float4',
          'Color': 'float4',
        },
        maskReferences: const [],
        stage: 'vertex',
        vertexAttributes: const [],
        vertexAttributeMetadata: const [],
      );

      final List<Map<String, dynamic>> outputs = summarizeVertexOutputs(data);
      expect(outputs, hasLength(3));
      expect(
        outputs,
        containsAllInOrder(<Map<String, dynamic>>[
          {'name': 'Color', 'components': 4},
          {'name': 'Tex0', 'components': 2},
          {'name': 'Tex1', 'components': 3},
        ]),
      );
    });
  });
}
