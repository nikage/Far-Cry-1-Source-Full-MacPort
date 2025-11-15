import 'dart:io';

import '../lib/metal_generator.dart';

void main() {
  final String shaderName = 'TestShader';
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
    coreFlow: flow,
    passStates: const [],
    maskReferences: const ['MASK_FEATURE', 'MASK_FOG'],
  );

  final String code = buildMetal(data);

  _check(code.contains('struct ${normalized}_input'), 'input struct missing');
  _check(code.contains('float4 Tex0;'), 'Tex0 field missing');
  _check(code.contains('float4 Color;'), 'Color field missing');
  _check(
    code.contains('baseMap.sample(baseMapSampler, IN.Tex0.xy)'),
    'texture sampling not converted',
  );
  _check(
    code.contains('float intensity = clamp(IN.Color.x, 0.0, 1.0);'),
    'saturate not rewritten',
  );
  _check(code.contains('return OUT.Color;'), 'return statement missing');

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
  _check(pipeline['blendEnabled'] == true, 'pipeline blendEnabled incorrect');
  _check(pipeline['blendMode'] == 'alpha', 'pipeline blendMode incorrect');
  final Map<String, dynamic> blendFactors =
      (pipeline['blendFactors'] as Map<String, dynamic>? ?? const <String, dynamic>{});
  _check(blendFactors['src'] == 'SRCALPHA', 'pipeline src blend factor incorrect');
  _check(blendFactors['dst'] == 'INVSRCALPHA', 'pipeline dst blend factor incorrect');
  _check(pipeline['depthWrite'] == false, 'pipeline depthWrite incorrect');
  _check(pipeline['depthTest'] == true, 'pipeline depthTest incorrect');
  _check(pipeline['depthCompare'] == 'lessEqual', 'pipeline depthCompare incorrect');
  _check(pipeline['cullMode'] == 'none', 'pipeline cull mode incorrect');
  final Map<String, dynamic> colorMask =
      (pipeline['colorMask'] as Map<String, dynamic>? ?? const <String, dynamic>{});
  _check(colorMask['red'] == true && colorMask['alpha'] == false, 'pipeline color mask incorrect');

  stdout.writeln('metal_generator_test: all checks passed');
}

void _check(bool condition, String message) {
  if (!condition) {
    stderr.writeln('Test failure: $message');
    exit(1);
  }
}

