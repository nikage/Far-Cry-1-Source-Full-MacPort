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

  stdout.writeln('metal_generator_test: all checks passed');
}

void _check(bool condition, String message) {
  if (!condition) {
    stderr.writeln('Test failure: $message');
    exit(1);
  }
}

