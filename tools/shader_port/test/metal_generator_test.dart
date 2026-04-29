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

    test('summarizes declared vertex outputs when analyzer finds none', () {
      final ShaderIrData data = ShaderIrData(
        shaderName: 'CGVProgNoOutputWrites',
        normalizedName: 'cgvprognooutputwrites',
        fragmentName: 'generated_cgvprognooutputwrites_vertex',
        uniformStruct: 'cgvprognooutputwrites_uniforms',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {
          'HPosition': 'float4',
          'Tex3': 'float4',
          'Tex4': 'float2',
        },
        maskReferences: const [],
        stage: 'vertex',
        vertexAttributes: const [],
        vertexAttributeMetadata: const [],
      );

      final List<Map<String, dynamic>> outputs = summarizeVertexOutputs(data);
      expect(
        outputs,
        anyElement(
          (Map<String, dynamic> entry) =>
              entry['name'] == 'Tex3' && entry['components'] == 4,
        ),
      );
      expect(
        outputs,
        anyElement(
          (Map<String, dynamic> entry) =>
              entry['name'] == 'Tex4' && entry['components'] == 2,
        ),
      );
    });

    test('zero initializes vertex outputs that core script never writes', () {
      final ShaderIrData data = ShaderIrData(
        shaderName: 'CGVProgMissingTexOutputs',
        normalizedName: 'cgvprogmissingtexoutputs',
        fragmentName: 'generated_cgvprogmissingtexoutputs_vertex',
        uniformStruct: 'cgvprogmissingtexoutputs_uniforms',
        uniforms: const [],
        textures: const [],
        coreExpressions: <Map<String, dynamic>>[
          {
            'type': 'assignment',
            'lhs': 'OUT.HPosition',
            'rhs': 'float4(IN.Position.xyz, 1.0)',
            'raw': 'OUT.HPosition = float4(IN.Position.xyz, 1.0);',
          },
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {
          'HPosition': 'float4',
          'Tex3': 'float4',
          'Tex4': 'float2',
        },
        maskReferences: const [],
        stage: 'vertex',
        vertexAttributes: const ['POSITION_3'],
        vertexAttributeMetadata: const <Map<String, dynamic>>[
          {
            'token': 'Position',
            'category': 'position',
            'semantic': 'POSITION',
            'components': 4,
            'source': 'macro',
          },
        ],
      );

      final String code = buildMetal(data);
      expect(code, contains('OUT.Tex3 = float4(0.0);'));
      expect(code, contains('OUT.Tex4 = float2(0.0);'));
    });

    test('orderVertexAttributes assigns DX9 base layout with tangent stream', () {
      final List<Map<String, dynamic>> metadata = <Map<String, dynamic>>[
        {
          'token': 'TexCoord0',
          'category': 'texcoord',
          'components': 2,
          'index': 0,
        },
        {
          'token': 'Color',
          'category': 'color',
          'components': 4,
          'index': 0,
        },
        {
          'token': 'Position',
          'category': 'position',
          'components': 4,
        },
        {
          'token': 'Normal',
          'category': 'normal',
          'components': 3,
        },
        {
          'token': 'Tangent',
          'category': 'tangent',
          'components': 3,
        },
        {
          'token': 'Binormal',
          'category': 'binormal',
          'components': 3,
        },
        {
          'token': 'TNormal',
          'category': 'normal',
          'components': 3,
        },
      ];

      final List<Map<String, dynamic>> ordered = orderVertexAttributes(metadata);
      expect(
        ordered.map((Map<String, dynamic> entry) => entry['token']),
        <String>['Position', 'Normal', 'Color', 'TexCoord0', 'Tangent', 'Binormal', 'TNormal'],
      );
      final Map<String, dynamic> texEntry = ordered.firstWhere(
        (Map<String, dynamic> entry) => entry['token'] == 'TexCoord0',
      );
      expect(texEntry['slot'], 3);
      final Map<String, dynamic> tangentEntry = ordered.firstWhere(
        (Map<String, dynamic> entry) => entry['token'] == 'Tangent',
      );
      expect(tangentEntry['slot'], 4);
      expect(tangentEntry['bufferIndex'], 1);
      final Map<String, dynamic> tnormalEntry = ordered.firstWhere(
        (Map<String, dynamic> entry) => entry['token'] == 'TNormal',
      );
      expect(tnormalEntry['slot'], 6);
      expect(tnormalEntry['bufferIndex'], 1);
    });

    test('orderVertexAttributes synthesizes missing normal/color for tangents', () {
      final List<Map<String, dynamic>> metadata = <Map<String, dynamic>>[
        {
          'token': 'Position',
          'category': 'position',
          'components': 4,
        },
        {
          'token': 'TexCoord0',
          'category': 'texcoord',
          'components': 2,
          'index': 0,
        },
        {
          'token': 'Tangent',
          'category': 'tangent',
          'components': 3,
        },
        {
          'token': 'Binormal',
          'category': 'binormal',
          'components': 3,
        },
        {
          'token': 'TNormal',
          'category': 'normal',
          'components': 3,
        },
      ];

      final List<Map<String, dynamic>> ordered = orderVertexAttributes(metadata);
      expect(
        ordered.map((Map<String, dynamic> entry) => entry['token']),
        <String>['Position', 'Normal', 'Color', 'TexCoord0', 'Tangent', 'Binormal', 'TNormal'],
      );
      final Map<String, dynamic> normalEntry = ordered.firstWhere(
        (Map<String, dynamic> entry) => entry['token'] == 'Normal',
      );
      expect(normalEntry['source'], 'synthetic');
      final Map<String, dynamic> colorEntry = ordered.firstWhere(
        (Map<String, dynamic> entry) => entry['token'] == 'Color',
      );
      expect(colorEntry['source'], 'synthetic');
    });

    test('vertex input struct uses DX9 slot numbering', () {
      final ShaderIrData data = ShaderIrData(
        shaderName: 'CGVProgDx9Layout',
        normalizedName: 'cgvprogdx9layout',
        fragmentName: 'generated_cgvprogdx9layout_vertex',
        uniformStruct: 'cgvprogdx9layout_uniforms',
        uniforms: const [],
        textures: const [],
        coreExpressions: const <Map<String, dynamic>>[
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0',
            'rhs': 'IN.TexCoord0',
            'raw': 'OUT.Tex0 = IN.TexCoord0;',
          },
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {
          'HPosition': 'float4',
          'Tex0': 'float2',
        },
        maskReferences: const [],
        stage: 'vertex',
        vertexAttributes: const [],
        vertexAttributeMetadata: const <Map<String, dynamic>>[
          {
            'token': 'Position',
            'category': 'position',
            'semantic': 'POSITION',
            'components': 4,
          },
          {
            'token': 'TexCoord0',
            'category': 'texcoord',
            'semantic': 'TEXCOORD',
            'components': 2,
            'index': 0,
          },
          {
            'token': 'Tangent',
            'category': 'tangent',
            'semantic': 'TANGENT',
            'components': 3,
          },
          {
            'token': 'Binormal',
            'category': 'binormal',
            'semantic': 'BINORMAL',
            'components': 3,
          },
          {
            'token': 'TNormal',
            'category': 'normal',
            'semantic': 'NORMAL',
            'components': 3,
          },
        ],
      );

      final String code = buildMetal(data);
      expect(code, contains('float4 Position [[attribute(0)]];'));
      expect(code, contains('float3 Normal [[attribute(1)]];'));
      expect(code, contains('float4 Color [[attribute(2)]];'));
      expect(code, contains('float2 TexCoord0 [[attribute(3)]];'));
      expect(code, contains('float3 Tangent [[attribute(4)]];'));
      expect(code, contains('float3 Binormal [[attribute(5)]];'));
      expect(code, contains('float3 TNormal [[attribute(6)]];'));
    });
  });
}
