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
      expect(code, contains('float2 Tex0 [[user(Tex0)]];'));
      expect(code, contains('float4 Color [[user(Color)]];'));
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

    test('manifestLookupAliasesForNormalizedFragment maps cgrcflare to flare_from_light',
        () {
      expect(
        manifestLookupAliasesForNormalizedFragment('cgrcflare'),
        equals(<String>['flare_from_light']),
      );
      expect(
        manifestLookupAliasesForNormalizedFragment('cgrcscreentexmap'),
        equals(<String>['screentexmap']),
      );
      expect(manifestLookupAliasesForNormalizedFragment('other'), isEmpty);
      expect(
        manifestLookupAliasesForNormalizedFragment(
          'cgrcbump_diffspec_singlelight_ps20',
          aliasesTxtByTarget: {
            'cgrcbump_diffspec_singlelight_ps20': <String>['tbumpspec'],
          },
        ),
        equals(<String>['tbumpspec']),
      );
    });

    test(
        'findUnmatchedAliasTargets reports every Aliases.txt target whose '
        'normalized name is not in the manifest', () {
      final Map<String, List<String>> aliasesByTarget = {
        'templbumpspec': <String>['tbumpspec'],
        'cgrcambienttempl': <String>['default', 'temploldambient'],
        'nodraw': <String>['no_draw'],
      };
      final Set<String> manifestNormalized = <String>{
        'cgrcambienttempl',
        'cgrcflare',
      };
      final List<String> unmatched =
          findUnmatchedAliasTargets(aliasesByTarget, manifestNormalized);
      expect(unmatched, equals(<String>['nodraw', 'templbumpspec']),
          reason: 'must list only targets missing from the manifest, sorted');
      expect(unmatched, isNot(contains('cgrcambienttempl')),
          reason: 'matched targets must not appear in the unmatched list');
    });

    test('findUnmatchedAliasTargets returns empty when every target matches',
        () {
      final Map<String, List<String>> aliasesByTarget = {
        'cgrcflare': <String>['flare_from_light'],
      };
      final Set<String> manifestNormalized = <String>{'cgrcflare'};
      expect(
        findUnmatchedAliasTargets(aliasesByTarget, manifestNormalized),
        isEmpty,
      );
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

  group('resolveVertexEntryPoint heuristic — token transform rules', () {
    Map<String, String> _verts(List<String> keys) => {
          for (final String k in keys) k: 'generated_${k}_vertex',
        };

    String? _resolve(String fragNorm, List<String> vertKeys) =>
        resolveVertexEntryPointForTest(fragNorm, _verts(vertKeys));

    test('alphaglow token is removed before matching', () {
      expect(
        _resolve('cgrcambient_alphaglow',
            ['cgvprogambient_vs20', 'cgvprogambient']),
        isNotNull,
      );
    });

    test('glitter token is removed before matching', () {
      expect(
        _resolve('cgrcambient_glitter',
            ['cgvprogambient_vs20', 'cgvprogambient']),
        isNotNull,
      );
    });

    test('specgloss is renamed to specpass_gloss before matching', () {
      expect(
        _resolve('cgrcbump_specgloss',
            ['cgvprogbump_specpass_gloss_vs20', 'cgvprogbump_specpass_gloss']),
        isNotNull,
      );
    });

    test('singlelight token is removed before matching', () {
      expect(
        _resolve('cgrcbump_diffspec_singlelight',
            ['cgvprogbump_diffspecpass_vs20', 'cgvprogbump_diffspecpass']),
        isNotNull,
      );
    });

    test('hp and atten tokens are swapped to match vertex ordering', () {
      expect(
        _resolve('cgrcbump_diffspec_hp_atten',
            ['cgvprogbump_diffspecpass_atten_hp_vs20',
             'cgvprogbump_diffspecpass_atten_hp']),
        isNotNull,
      );
    });

    test('gloss-stripping fallback resolves when vertex lacks gloss suffix', () {
      expect(
        _resolve('cgrcbump_diffspec_gloss',
            ['cgvprogbump_diffspecpass_vs20', 'cgvprogbump_diffspecpass']),
        isNotNull,
      );
    });

    test('substring fallback (corrected direction) does not produce false match', () {
      // After stripping the cgrc prefix, the fragment stem never starts with
      // cgvprog, so it cannot contain a vertex key as a substring. The fallback
      // is inert for standard naming conventions — which is correct behaviour.
      expect(
        _resolve('cgrcbump_diffspecpass_extra',
            ['cgvprogbump_diffspecpass']),
        isNull,
      );
    });

    test('substring fallback does not match when vertex key is <= 8 chars', () {
      expect(
        _resolve('cgrcbumplong_extra',
            ['cgvbump']),
        isNull,
      );
    });

    test('returns null when no match exists', () {
      expect(
        _resolve('cgrccompletely_unknown_shader', ['cgvprogambient_vs20']),
        isNull,
      );
    });
  });

  group('ModelViewProj synthetic uniform', () {
    ShaderIrData _makeVertexShaderWithout({
      List<UniformBinding> extraUniforms = const [],
      List<Map<String, dynamic>> extraExpressions = const [],
    }) {
      final String normalized = normalizeName('CGVProgModelVP');
      return ShaderIrData(
        shaderName: 'CGVProgModelVP',
        normalizedName: normalized,
        fragmentName: 'generated_${normalized}_vertex',
        uniformStruct: '${normalized}_uniforms',
        uniforms: [...extraUniforms],
        textures: const [],
        coreExpressions: [
          ...extraExpressions,
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0.xy',
            'rhs': 'IN.TexCoord0.xy',
            'raw': 'OUT.Tex0.xy = IN.TexCoord0.xy;',
            'active': true,
          },
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {'HPosition': 'float4', 'Tex0': 'float2'},
        maskReferences: const [],
        stage: 'vertex',
        vertexAttributes: const ['POSITION_3', 'TEXCOORD0_2'],
        vertexAttributeMetadata: const [
          {
            'token': 'Position',
            'category': 'position',
            'semantic': 'POSITION',
            'components': 4,
          },
          {
            'token': 'TexCoord0',
            'category': 'texcoord',
            'semantic': 'TEXCOORD0',
            'components': 2,
            'index': 0,
          },
        ],
      );
    }

    test(
        'ModelViewProj is injected into uniform struct when body references it '
        'and IR did not declare it', () {
      final ShaderIrData data = _makeVertexShaderWithout(
        extraExpressions: [
          {
            'type': 'assignment',
            'lhs': 'OUT.HPosition',
            'rhs': 'uniforms.ModelViewProj * float4(IN.Position.xyz, 1.0)',
            'raw':
                'OUT.HPosition = uniforms.ModelViewProj * float4(IN.Position.xyz, 1.0);',
            'active': true,
          },
        ],
      );
      final String metal = buildMetal(data);
      expect(metal, contains('ModelViewProj'));
      expect(metal, contains('float4x4'));
    });

    test(
        'ModelViewProj is injected via HPosition fallback path even when '
        'core expressions do not reference it directly', () {
      final ShaderIrData data = _makeVertexShaderWithout();
      final String metal = buildMetal(data);
      expect(metal, contains('ModelViewProj'),
          reason: 'fallback HPosition assignment requires ModelViewProj in uniform struct');
      expect(metal, contains('float4x4'),
          reason: 'ModelViewProj must be typed as float4x4 in the struct');
    });

    test(
        'ModelViewProj is not duplicated when IR already declares it', () {
      final ShaderIrData data = _makeVertexShaderWithout(
        extraUniforms: [UniformBinding('float4x4', 'ModelViewProj', '')],
        extraExpressions: [
          {
            'type': 'assignment',
            'lhs': 'OUT.HPosition',
            'rhs': 'uniforms.ModelViewProj * float4(IN.Position.xyz, 1.0)',
            'raw':
                'OUT.HPosition = uniforms.ModelViewProj * float4(IN.Position.xyz, 1.0);',
            'active': true,
          },
        ],
      );
      final String metal = buildMetal(data);
      final int occurrences = 'ModelViewProj'.allMatches(metal).length;
      expect(occurrences, greaterThan(0));
      final RegExp structField =
          RegExp(r'float4x4\s+ModelViewProj\s*;');
      expect(
        structField.allMatches(metal).length,
        equals(1),
        reason: 'ModelViewProj should appear exactly once in the struct',
      );
    });
  });

  group('MetalFragmentBuilder — pairedVertexOutputs reconciliation', () {
    ShaderIrData _makeFragmentWithTex(
        {int metadataComponents = 2}) {
      return ShaderIrData(
        shaderName: 'CGRCTest',
        normalizedName: 'cgrctest',
        fragmentName: 'cgrctest_frag',
        uniformStruct: 'cgrctest_uniforms',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [
          {
            'type': 'assignment',
            'lhs': 'float4 c',
            'rhs': 'tex2D(baseMap, IN.Tex0.xy)',
            'raw': 'float4 c = tex2D(baseMap, IN.Tex0.xy);',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Color',
            'rhs': 'c',
            'raw': 'OUT.Color = c;',
          },
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const [],
        stage: 'fragment',
        vertexAttributes: const ['TEXCOORD0_2'],
        vertexAttributeMetadata: [
          {
            'token': 'Tex0',
            'category': 'texcoord',
            'semantic': 'TEXCOORD0',
            'components': metadataComponents,
            'index': 0,
          },
        ],
      );
    }

    test(
        'without pairedVertexOutputs, fragment _input uses fragment metadata '
        'component count', () {
      final ShaderIrData data = _makeFragmentWithTex(metadataComponents: 2);
      final String metal = MetalFragmentBuilder(
        data,
        isVertexStage: false,
      ).build();
      expect(metal, contains('float2 Tex0'),
          reason: 'should use metadata-derived float2 when no pairing provided');
    });

    test(
        'with pairedVertexOutputs, fragment _input uses vertex component count '
        'regardless of fragment metadata', () {
      final ShaderIrData data = _makeFragmentWithTex(metadataComponents: 2);
      final String metal = MetalFragmentBuilder(
        data,
        isVertexStage: false,
        pairedVertexOutputs: const {'Tex0': 3},
      ).build();
      expect(metal, contains('float3 Tex0'),
          reason: 'pairedVertexOutputs must override metadata-derived float2 → float3');
      expect(metal, isNot(contains('float2 Tex0')),
          reason: 'original metadata-derived float2 must not appear');
    });

    test(
        'real-world Refractive fix: VS Tex1=float2, FS metadata=float4 → '
        'pairedVertexOutputs produces float2 Tex1 in _input', () {
      final ShaderIrData data = ShaderIrData(
        shaderName: 'CGRCRefractive',
        normalizedName: 'cgrcrefractive',
        fragmentName: 'cgrcrefractive_frag',
        uniformStruct: 'cgrcrefractive_uniforms',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [
          {
            'type': 'assignment',
            'lhs': 'float4 refr',
            'rhs': 'tex2D(refrMap, IN.Tex1.xy)',
            'raw': 'float4 refr = tex2D(refrMap, IN.Tex1.xy);',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Color',
            'rhs': 'refr',
            'raw': 'OUT.Color = refr;',
          },
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const [],
        stage: 'fragment',
        vertexAttributes: const ['TEXCOORD1_4'],
        vertexAttributeMetadata: const [
          {
            'token': 'Tex1',
            'category': 'texcoord',
            'semantic': 'TEXCOORD1',
            'components': 4,
            'index': 1,
          },
        ],
      );
      final String metalWithout = MetalFragmentBuilder(
        data,
        isVertexStage: false,
      ).build();
      expect(metalWithout, contains('float4 Tex1'),
          reason: 'without pairing, metadata-derived float4 should be used');

      final String metalWith = MetalFragmentBuilder(
        data,
        isVertexStage: false,
        pairedVertexOutputs: const {'Tex1': 2},
      ).build();
      expect(metalWith, contains('float2 Tex1'),
          reason: 'with pairedVertexOutputs, VS float2 must win over FS float4');
      expect(metalWith, isNot(contains('float4 Tex1')),
          reason: 'FS metadata float4 must not appear in input struct');
    });

    test(
        'pairedVertexOutputs does not override explicit _inputFieldTypeOverrides '
        '(e.g. Tangent always stays float3)', () {
      final ShaderIrData data = ShaderIrData(
        shaderName: 'CGRCTangentTest',
        normalizedName: 'cgrctangenttest',
        fragmentName: 'cgrctangenttest_frag',
        uniformStruct: 'cgrctangenttest_uniforms',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [
          {
            'type': 'assignment',
            'lhs': 'float3 t',
            'rhs': 'IN.Tangent',
            'raw': 'float3 t = IN.Tangent;',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Color',
            'rhs': 'float4(t, 1.0)',
            'raw': 'OUT.Color = float4(t, 1.0);',
          },
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const [],
        stage: 'fragment',
        vertexAttributes: const [],
        vertexAttributeMetadata: const [
          {
            'token': 'Tangent',
            'category': 'tangent',
            'semantic': 'TANGENT',
            'components': 4,
          },
        ],
      );
      final String metal = MetalFragmentBuilder(
        data,
        isVertexStage: false,
        pairedVertexOutputs: const {'Tangent': 4},
      ).build();
      expect(metal, contains('float3 Tangent'),
          reason: '_inputFieldTypeOverrides for Tangent must win over pairedVertexOutputs=4');
    });

    test(
        'pairedVertexOutputs narrower than body requirement uses required '
        'count to avoid compile errors', () {
      final ShaderIrData data = ShaderIrData(
        shaderName: 'CGRCNarrowVS',
        normalizedName: 'cgrcnarrowvs',
        fragmentName: 'cgrcnarrowvs_frag',
        uniformStruct: 'cgrcnarrowvs_uniforms',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [
          {
            'type': 'assignment',
            'lhs': 'float3 t',
            'rhs': 'IN.Tex2.xyz',
            'raw': 'float3 t = IN.Tex2.xyz;',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Color',
            'rhs': 'float4(t, 1.0)',
            'raw': 'OUT.Color = float4(t, 1.0);',
          },
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const [],
        stage: 'fragment',
        vertexAttributes: const ['TEXCOORD2_2'],
        vertexAttributeMetadata: const [
          {
            'token': 'Tex2',
            'category': 'texcoord',
            'semantic': 'TEXCOORD2',
            'components': 2,
            'index': 2,
          },
        ],
      );
      // VS only outputs float2 Tex2, but FS body accesses .xyz (needs float3).
      // pairedVertexOutputs says 2, but required = 3 → max(2,3) = 3.
      final String metal = MetalFragmentBuilder(
        data,
        isVertexStage: false,
        pairedVertexOutputs: const {'Tex2': 2},
      ).build();
      expect(metal, contains('float3 Tex2'),
          reason: 'required count (3) must win when pairedVertexOutputs (2) is too narrow');
      expect(metal, isNot(contains('float2 Tex2')),
          reason: 'float2 would cause a compile error when body accesses .xyz');
    });

    test(
        'field not in pairedVertexOutputs falls back to metadata-derived type', () {
      final ShaderIrData data = ShaderIrData(
        shaderName: 'CGRCFallback',
        normalizedName: 'cgrcfallback',
        fragmentName: 'cgrcfallback_frag',
        uniformStruct: 'cgrcfallback_uniforms',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [
          {
            'type': 'assignment',
            'lhs': 'float2 uv',
            'rhs': 'IN.Tex0.xy',
            'raw': 'float2 uv = IN.Tex0.xy;',
          },
          {
            'type': 'assignment',
            'lhs': 'float2 uv2',
            'rhs': 'IN.Tex1.xy',
            'raw': 'float2 uv2 = IN.Tex1.xy;',
          },
          {
            'type': 'assignment',
            'lhs': 'OUT.Color',
            'rhs': 'float4(uv, uv2)',
            'raw': 'OUT.Color = float4(uv, uv2);',
          },
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const [],
        stage: 'fragment',
        vertexAttributes: const ['TEXCOORD0_2', 'TEXCOORD1_3'],
        vertexAttributeMetadata: const [
          {
            'token': 'Tex0',
            'category': 'texcoord',
            'semantic': 'TEXCOORD0',
            'components': 2,
            'index': 0,
          },
          {
            'token': 'Tex1',
            'category': 'texcoord',
            'semantic': 'TEXCOORD1',
            'components': 3,
            'index': 1,
          },
        ],
      );
      // pairedVertexOutputs only has Tex0 → Tex1 must fall back to metadata
      final String metal = MetalFragmentBuilder(
        data,
        isVertexStage: false,
        pairedVertexOutputs: const {'Tex0': 4},
      ).build();
      expect(metal, contains('float4 Tex0'),
          reason: 'Tex0 overridden to float4 via pairedVertexOutputs');
      expect(metal, contains('float3 Tex1'),
          reason: 'Tex1 not in pairedVertexOutputs → falls back to metadata float3');
    });
  });

  group('VS output requirements — vsOutputRequirements param', () {
    ShaderIrData _makeVertexWithTex({
      List<Map<String, dynamic>> expressions = const [],
      List<Map<String, dynamic>> metadata = const [],
      Map<String, String> outputFieldTypes = const {},
    }) {
      return ShaderIrData(
        shaderName: 'CGVProgTest',
        normalizedName: 'cgvprogtest',
        fragmentName: '',
        uniformStruct: 'cgvprogtest_uniforms',
        uniforms: const [],
        textures: const [],
        coreExpressions: expressions,
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: outputFieldTypes,
        maskReferences: const [],
        stage: 'vertex',
        vertexAttributes: const [],
        vertexAttributeMetadata: metadata,
      );
    }

    test('vsOutputRequirements widens existing output type', () {
      final ShaderIrData data = _makeVertexWithTex(
        expressions: const [
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex1',
            'rhs': 'IN.Tex1.xy',
            'raw': 'OUT.Tex1 = IN.Tex1.xy;',
          },
        ],
        outputFieldTypes: const {'HPosition': 'float4'},
        metadata: const [
          {'token': 'Position', 'category': 'position', 'components': 3},
          {'token': 'Tex1', 'category': 'texcoord', 'components': 2},
        ],
      );
      final String metal = MetalFragmentBuilder(
        data,
        isVertexStage: true,
        vsOutputRequirements: const {'Tex1': 4},
      ).build();
      expect(metal, contains('float4 Tex1'),
          reason: 'vsOutputRequirements should widen Tex1 from float2 to float4 in output struct');
      expect(metal, isNot(contains('float2 Tex1 [[user')),
          reason: 'narrower type must not remain in output struct');
    });

    test('vsOutputRequirements adds missing field with IN pass-through', () {
      final ShaderIrData data = _makeVertexWithTex(
        expressions: const [
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0',
            'rhs': 'IN.Tex0',
            'raw': 'OUT.Tex0 = IN.Tex0;',
          },
        ],
        outputFieldTypes: const {'HPosition': 'float4'},
        metadata: const [
          {'token': 'Position', 'category': 'position', 'components': 3},
          {'token': 'Tex0', 'category': 'texcoord', 'components': 2},
          {'token': 'Tex2', 'category': 'texcoord', 'components': 3},
        ],
      );
      final String metal = MetalFragmentBuilder(
        data,
        isVertexStage: true,
        vsOutputRequirements: const {'Tex2': 3},
      ).build();
      expect(metal, contains('float3 Tex2 [[user(Tex2)]]'),
          reason: 'missing field Tex2 must appear in output struct');
      expect(metal, contains('OUT.Tex2 = IN.Tex2'),
          reason: 'Tex2 is in vertex input so should be passed through from IN');
    });

    test('vsOutputRequirements adds missing field with zero-fill when not in input', () {
      final ShaderIrData data = _makeVertexWithTex(
        expressions: const [
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0',
            'rhs': 'IN.Tex0',
            'raw': 'OUT.Tex0 = IN.Tex0;',
          },
        ],
        outputFieldTypes: const {'HPosition': 'float4'},
        metadata: const [
          {'token': 'Position', 'category': 'position', 'components': 3},
          {'token': 'Tex0', 'category': 'texcoord', 'components': 2},
        ],
      );
      final String metal = MetalFragmentBuilder(
        data,
        isVertexStage: true,
        vsOutputRequirements: const {'Color1': 4},
      ).build();
      expect(metal, contains('float4 Color1 [[user(Color1)]]'),
          reason: 'Color1 not in input attrs so must appear in output struct');
      expect(metal, contains('OUT.Color1 = float4(0.0)'),
          reason: 'Color1 not in VS input → zero-fill');
    });

    test('body already writes field — no duplicate pass-through emitted', () {
      final ShaderIrData data = _makeVertexWithTex(
        expressions: const [
          {
            'type': 'assignment',
            'lhs': 'OUT.Tex0',
            'rhs': 'float2(1.0, 0.5)',
            'raw': 'OUT.Tex0 = float2(1.0, 0.5);',
          },
        ],
        outputFieldTypes: const {'HPosition': 'float4'},
        metadata: const [
          {'token': 'Position', 'category': 'position', 'components': 3},
          {'token': 'Tex0', 'category': 'texcoord', 'components': 2},
        ],
      );
      final String metal = MetalFragmentBuilder(
        data,
        isVertexStage: true,
        vsOutputRequirements: const {'Tex0': 2},
      ).build();
      final int assignCount =
          'OUT.Tex0'.allMatches(metal).length;
      expect(assignCount, equals(2),
          reason: 'body already assigns Tex0 — translator adds a prologue zero-fill (1) + body assignment (2); pass-through must not inject a third');
      expect(metal, contains('OUT.Tex0 = float2(1.0, 0.5)'),
          reason: 'the body assignment must still be present');
    });

    test('_collectVsRequiredOutputs aggregates max components across multiple paired FSes', () {
      final type_record = (
        relative: 'test.json',
        result: ShaderIrParser().parse({
          'shaderName': 'CGVProgTest',
          'stage': 'vertex',
          'normalizedName': 'cgvprogtest',
          'extension': 'crycg',
        }, 'test.json'),
        data: _makeVertexWithTex(),
        metalFileName: 'test.metal',
      );
      final ShaderIrData fs1Data = ShaderIrData(
        shaderName: 'CGRCFS1',
        normalizedName: 'cgrcfs1',
        fragmentName: 'cgrcfs1_frag',
        uniformStruct: 'u',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const [],
        stage: 'fragment',
        vertexAttributes: const [],
        vertexAttributeMetadata: const [
          {'token': 'Tex1', 'category': 'texcoord', 'components': 2},
        ],
      );
      final ShaderIrData fs2Data = ShaderIrData(
        shaderName: 'CGRCFS2',
        normalizedName: 'cgrcfs2',
        fragmentName: 'cgrcfs2_frag',
        uniformStruct: 'u',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const [],
        stage: 'fragment',
        vertexAttributes: const [],
        vertexAttributeMetadata: const [
          {'token': 'Tex1', 'category': 'texcoord', 'components': 4},
        ],
      );
      final allShaders = [
        type_record,
        (
          relative: 'fs1.json',
          result: ShaderIrParser().parse({
            'shaderName': 'CGRCFS1',
            'stage': 'fragment',
            'normalizedName': 'cgrcfs1',
            'extension': 'crycg',
          }, 'fs1.json'),
          data: fs1Data,
          metalFileName: 'fs1.metal',
        ),
        (
          relative: 'fs2.json',
          result: ShaderIrParser().parse({
            'shaderName': 'CGRCFS2',
            'stage': 'fragment',
            'normalizedName': 'cgrcfs2',
            'extension': 'crycg',
          }, 'fs2.json'),
          data: fs2Data,
          metalFileName: 'fs2.metal',
        ),
      ];
      final pairing = {
        'cgrcfs1': (
          vertexEntryPoint: 'generated_cgvprogtest_vertex',
          vertexNorm: 'cgvprogtest',
          overrideCategory: null,
        ),
        'cgrcfs2': (
          vertexEntryPoint: 'generated_cgvprogtest_vertex',
          vertexNorm: 'cgvprogtest',
          overrideCategory: null,
        ),
      };
      final result = collectVsRequiredOutputs(allShaders, pairing);
      expect(result['cgvprogtest']?['Tex1'], equals(4),
          reason: 'max of fs1(2) and fs2(4) must be 4');
    });

    test('_collectVsRequiredOutputs skips position-category fields', () {
      final ShaderIrData fsData = ShaderIrData(
        shaderName: 'CGRCFSP',
        normalizedName: 'cgrcfsp',
        fragmentName: 'cgrcfsp_frag',
        uniformStruct: 'u',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const [],
        stage: 'fragment',
        vertexAttributes: const [],
        vertexAttributeMetadata: const [
          {'token': 'Position', 'category': 'position', 'components': 3},
          {'token': 'Tex0', 'category': 'texcoord', 'components': 2},
        ],
      );
      final allShaders = [
        (
          relative: 'fsp.json',
          result: ShaderIrParser().parse({
            'shaderName': 'CGRCFSP',
            'stage': 'fragment',
            'normalizedName': 'cgrcfsp',
            'extension': 'crycg',
          }, 'fsp.json'),
          data: fsData,
          metalFileName: 'fsp.metal',
        ),
      ];
      final pairing = {
        'cgrcfsp': (
          vertexEntryPoint: 'generated_cgvprogvs_vertex',
          vertexNorm: 'cgvprogvs',
          overrideCategory: null,
        ),
      };
      final result = collectVsRequiredOutputs(allShaders, pairing);
      expect(result['cgvprogvs']?.containsKey('Position'), isFalse,
          reason: 'position-category fields must be excluded');
      expect(result['cgvprogvs']?['Tex0'], equals(2),
          reason: 'non-position field Tex0 must be included');
    });

    test('texCUBE macro hint widens Tex1/Tex2/Tex3 to float3 in requirements', () {
      // A FS that uses texCUBE: the macro hint forces Tex1,Tex2,Tex3 to 3
      // components regardless of what vertexAttributeMetadata says (2 here).
      final ShaderIrData fsData = ShaderIrData(
        shaderName: 'CGRCCubemap',
        normalizedName: 'cgrccubemap',
        fragmentName: 'cgrccubemap_frag',
        uniformStruct: 'u',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [
          {'lhs': 'OUT.Color', 'rhs': 'texCUBE(envMap, IN.Tex2.xyz)', 'active': true},
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const [],
        stage: 'fragment',
        vertexAttributes: const [],
        vertexAttributeMetadata: const [
          {'token': 'Tex0', 'category': 'texcoord', 'components': 2},
          {'token': 'Tex1', 'category': 'texcoord', 'components': 2},
          {'token': 'Tex2', 'category': 'texcoord', 'components': 2},
        ],
      );
      final allShaders = [
        (
          relative: 'cube.json',
          result: ShaderIrParser().parse({
            'shaderName': 'CGRCCubemap',
            'stage': 'fragment',
            'normalizedName': 'cgrccubemap',
            'extension': 'crycg',
          }, 'cube.json'),
          data: fsData,
          metalFileName: 'cube.metal',
        ),
      ];
      final pairing = {
        'cgrccubemap': (
          vertexEntryPoint: 'generated_cgvprogvs_vertex',
          vertexNorm: 'cgvprogvs',
          overrideCategory: null,
        ),
      };
      final result = collectVsRequiredOutputs(allShaders, pairing);
      expect(result['cgvprogvs']?['Tex1'], equals(3),
          reason: 'texCUBE macro hint must widen Tex1 to 3');
      expect(result['cgvprogvs']?['Tex2'], equals(3),
          reason: 'texCUBE macro hint must widen Tex2 to 3');
      expect(result['cgvprogvs']?['Tex0'], equals(2),
          reason: 'Tex0 not in texCUBE hint stays at 2');
    });

    test('_vs20 requirements propagate to bare canonical VS key', () {
      // Ensures that when a FS is paired with a _vs20 VS, the bare VS variant
      // (which shares the same runtime canonical key) is also widened.
      final ShaderIrData fsData = ShaderIrData(
        shaderName: 'CGRCBump_Test',
        normalizedName: 'cgrcbump_test',
        fragmentName: 'cgrcbump_test_frag',
        uniformStruct: 'u',
        uniforms: const [],
        textures: const [],
        coreExpressions: const [
          {'lhs': 'OUT.Color', 'rhs': 'texCUBE(envMap, IN.Tex1.xyz)', 'active': true},
        ],
        coreMacros: const [],
        coreFlow: const [],
        passStates: const [],
        positionScripts: const [],
        positionScriptBlocks: const [],
        outputFieldTypes: const {},
        maskReferences: const [],
        stage: 'fragment',
        vertexAttributes: const [],
        vertexAttributeMetadata: const [
          {'token': 'Tex1', 'category': 'texcoord', 'components': 2},
        ],
      );
      final allShaders = [
        (
          relative: 'test.json',
          result: ShaderIrParser().parse({
            'shaderName': 'CGRCBump_Test',
            'stage': 'fragment',
            'normalizedName': 'cgrcbump_test',
            'extension': 'crycg',
          }, 'test.json'),
          data: fsData,
          metalFileName: 'test.metal',
        ),
      ];
      final pairing = {
        'cgrcbump_test': (
          vertexEntryPoint: 'generated_cgvprogbump_pass_vs20_vertex',
          vertexNorm: 'cgvprogbump_pass_vs20',
          overrideCategory: null,
        ),
      };
      final result = collectVsRequiredOutputs(allShaders, pairing);
      expect(result['cgvprogbump_pass_vs20']?['Tex1'], equals(3),
          reason: 'versioned key must be widened');
      expect(result['cgvprogbump_pass']?['Tex1'], equals(3),
          reason: 'bare canonical key must also be widened');
    });
  });

  group('duplicate IR paths', () {
    test('prefers HWScripts over flat CGVShaders path', () {
      expect(
        preferDuplicateIrPath(
          'HWScripts/Declarations/CGVShaders/CGVProgHeatHaze.crycg.json',
          'CGVShaders/CGVProgHeatHaze.crycg.json',
        ),
        isTrue,
      );
      expect(
        preferDuplicateIrPath(
          'CGVShaders/CGVProgHeatHaze.crycg.json',
          'HWScripts/Declarations/CGVShaders/CGVProgHeatHaze.crycg.json',
        ),
        isFalse,
      );
    });

    test('tie-break prefers longer relative path', () {
      expect(
        preferDuplicateIrPath(
          'A/B/C/X.crycg.json',
          'A/B/X.crycg.json',
        ),
        isTrue,
      );
    });
  });
}
