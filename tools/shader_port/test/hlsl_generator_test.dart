import 'package:shader_port/hlsl_generator.dart';
import 'package:test/test.dart';

Map<String, dynamic> _ir({
  List<dynamic> blocks = const [],
  List<dynamic> coreScriptExpressions = const [],
}) {
  return <String, dynamic>{
    'blocks': blocks,
    'coreScriptExpressions': coreScriptExpressions,
  };
}

Map<String, dynamic> _mainInput(String content) =>
    <String, dynamic>{'name': 'MainInput', 'content': content};

void main() {
  group('buildHlsl — structure invariants', () {
    test('empty IR produces GeneratedInput struct but no cbuffer or textures', () {
      final String hlsl = buildHlsl(<String, dynamic>{});
      expect(hlsl, contains('struct GeneratedInput'));
      expect(hlsl, isNot(contains('cbuffer')));
      expect(hlsl, isNot(contains('Texture2D')));
      expect(hlsl, contains('float4 GeneratedMain(GeneratedInput input)'));
    });

    test('GeneratedInput always declares all 8 texcoord channels', () {
      final String hlsl = buildHlsl(<String, dynamic>{});
      for (int i = 0; i < 8; i++) {
        expect(hlsl, contains('texCoord$i'));
      }
    });

    test('function signature contains SV_Target return semantic', () {
      final String hlsl = buildHlsl(<String, dynamic>{});
      expect(hlsl, contains(': SV_Target'));
    });
  });

  group('buildHlsl — uniform cbuffer', () {
    test('single uniform emits cbuffer with register b0', () {
      final String hlsl = buildHlsl(
        _ir(blocks: [_mainInput('uniform float4 Diffuse;')]),
      );
      expect(hlsl, contains('cbuffer GeneratedUniforms : register(b0)'));
      expect(hlsl, contains('Diffuse'));
    });

    test('multiple uniforms all appear inside cbuffer block', () {
      final String hlsl = buildHlsl(
        _ir(blocks: [_mainInput('uniform float4 Ambient;\nuniform float Opacity;')]),
      );
      final int cbufferStart = hlsl.indexOf('cbuffer');
      final int cbufferEnd = hlsl.indexOf('}', cbufferStart);
      final String cbufferBlock = hlsl.substring(cbufferStart, cbufferEnd);
      expect(cbufferBlock, contains('Ambient'));
      expect(cbufferBlock, contains('Opacity'));
    });

    test('sampler does not appear in cbuffer', () {
      final String hlsl = buildHlsl(
        _ir(blocks: [_mainInput('uniform sampler2D baseMap;\nuniform float4 Color;')]),
      );
      final int cbufferStart = hlsl.indexOf('cbuffer');
      if (cbufferStart != -1) {
        final int cbufferEnd = hlsl.indexOf('}', cbufferStart);
        final String cbufferBlock = hlsl.substring(cbufferStart, cbufferEnd);
        expect(cbufferBlock, isNot(contains('baseMap')));
      }
    });
  });

  group('buildHlsl — texture declarations', () {
    test('sampler2D emits Texture2D and SamplerState at register t0/s0', () {
      final String hlsl = buildHlsl(
        _ir(blocks: [_mainInput('uniform sampler2D baseMap;')]),
      );
      expect(hlsl, contains('Texture2D baseMap : register(t0)'));
      expect(hlsl, contains('SamplerState baseMapSampler : register(s0)'));
    });

    test('two samplers get sequential texture/sampler registers', () {
      final String hlsl = buildHlsl(
        _ir(blocks: [_mainInput('uniform sampler2D mapA;\nuniform sampler2D mapB;')]),
      );
      expect(hlsl, contains('register(t0)'));
      expect(hlsl, contains('register(t1)'));
      expect(hlsl, contains('register(s0)'));
      expect(hlsl, contains('register(s1)'));
    });
  });

  group('buildHlsl — default fallback body (no coreExpressions)', () {
    test('Texture2D sampler fallback uses .Sample() call', () {
      final String hlsl = buildHlsl(
        _ir(blocks: [_mainInput('uniform sampler2D baseMap;')]),
      );
      expect(hlsl, contains('baseMap.Sample(baseMapSampler'));
    });

    test('3D texture fallback emits comment instead of sample call', () {
      final String hlsl = buildHlsl(
        _ir(blocks: [_mainInput('uniform sampler3D volMap;')]),
      );
      expect(hlsl, contains('// Texture sampling not implemented for'));
      expect(hlsl, isNot(contains('volMap.Sample(')));
    });

    test('cube texture fallback emits comment instead of sample call', () {
      final String hlsl = buildHlsl(
        _ir(blocks: [_mainInput('uniform samplerCUBE envMap;')]),
      );
      expect(hlsl, contains('// Texture sampling not implemented for'));
    });

    test('float4 uniform fallback multiplies result', () {
      final String hlsl = buildHlsl(
        _ir(blocks: [_mainInput('uniform float4 TintColor;')]),
      );
      expect(hlsl, contains('result *= TintColor'));
    });

    test('non-float4 uniform alone does not emit multiply fallback', () {
      final String hlsl = buildHlsl(
        _ir(blocks: [_mainInput('uniform float Opacity;')]),
      );
      expect(hlsl, isNot(contains('result *= Opacity')));
    });
  });

  group('translateType', () {
    test('float maps to float', () => expect(translateType('float'), 'float'));
    test('float2 maps to float2', () => expect(translateType('float2'), 'float2'));
    test('float3 maps to float3', () => expect(translateType('float3'), 'float3'));
    test('float4 maps to float4', () => expect(translateType('float4'), 'float4'));
    test('half4 maps to float4', () => expect(translateType('half4'), 'float4'));
    test('FLOAT4 (uppercase) maps to float4', () => expect(translateType('FLOAT4'), 'float4'));
    test('unknown type maps to float4', () => expect(translateType('matrix3x3'), 'float4'));
  });

  group('translateTextureType', () {
    test('samplerCUBE maps to TextureCube', () =>
        expect(translateTextureType('samplerCUBE'), 'TextureCube'));
    test('sampler_cube maps to TextureCube', () =>
        expect(translateTextureType('sampler_cube'), 'TextureCube'));
    test('sampler3D maps to Texture3D', () =>
        expect(translateTextureType('sampler3D'), 'Texture3D'));
    test('sampler2D maps to Texture2D', () =>
        expect(translateTextureType('sampler2D'), 'Texture2D'));
    test('default empty string maps to Texture2D', () =>
        expect(translateTextureType(''), 'Texture2D'));
  });

  group('translateCoreScript', () {
    test('empty list returns empty', () {
      expect(translateCoreScript(<dynamic>[]), isEmpty);
    });

    test('entry with active=false is skipped', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'raw', 'active': false, 'raw': 'float x = 1;'},
      ]);
      expect(lines, isEmpty);
    });

    test('entry with type==comment emits // prefix', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'comment', 'value': 'my note'},
      ]);
      expect(lines, hasLength(1));
      expect(lines.first, startsWith('//'));
      expect(lines.first, contains('my note'));
    });

    test('entry with empty raw string is skipped', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'raw', 'raw': ''},
      ]);
      expect(lines, isEmpty);
    });

    test('OUT.Color is rewritten to result', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'assignment', 'raw': 'OUT.Color = float4(1,0,0,1);'},
      ]);
      expect(lines.first, contains('result'));
      expect(lines.first, isNot(contains('OUT.Color')));
    });

    test('IN.Color is rewritten to input.color', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'assignment', 'raw': 'float4 c = IN.Color;'},
      ]);
      expect(lines.first, contains('input.color'));
    });

    test('IN.Color1 is rewritten to input.color1', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'assignment', 'raw': 'float4 c = IN.Color1;'},
      ]);
      expect(lines.first, contains('input.color1'));
    });

    test('IN.clipDistance is rewritten to input.clipDistance', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'raw', 'raw': 'float d = IN.clipDistance;'},
      ]);
      expect(lines.first, contains('input.clipDistance'));
    });

    test('IN.Tex0 is rewritten to input.texCoord0', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'raw', 'raw': 'float2 uv = IN.Tex0.xy;'},
      ]);
      expect(lines.first, contains('input.texCoord0'));
    });

    test('IN.Tex7 is rewritten to input.texCoord7', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'raw', 'raw': 'float2 uv = IN.Tex7.xy;'},
      ]);
      expect(lines.first, contains('input.texCoord7'));
    });

    test('tex2D call is rewritten to .Sample() form', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'raw', 'raw': 'float4 c = tex2D(baseMap, IN.Tex0.xy);'},
      ]);
      expect(lines.first, contains('baseMap.Sample(baseMapSampler'));
    });

    test('texCUBE call is rewritten to .Sample() form', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'raw', 'raw': 'float4 r = texCUBE(envMap, dir);'},
      ]);
      expect(lines.first, contains('envMap.Sample(envMapSampler'));
    });

    test('non-map entry in list is skipped', () {
      final List<String> lines = translateCoreScript(<dynamic>['not a map']);
      expect(lines, isEmpty);
    });

    test('active entries without active key are included', () {
      final List<String> lines = translateCoreScript(<dynamic>[
        <String, dynamic>{'type': 'raw', 'raw': 'float x = 1.0;'},
      ]);
      expect(lines, hasLength(1));
    });
  });

  group('buildHlsl — coreExpressions body', () {
    test('coreExpressions are emitted inside function body', () {
      final String hlsl = buildHlsl(
        _ir(coreScriptExpressions: [
          <String, dynamic>{'type': 'raw', 'raw': 'float4 color = IN.Color * 2.0;'},
        ]),
      );
      expect(hlsl, contains('input.color * 2.0'));
    });

    test('multiple coreExpressions are all present', () {
      final String hlsl = buildHlsl(
        _ir(coreScriptExpressions: [
          <String, dynamic>{'type': 'raw', 'raw': 'float x = 1.0;'},
          <String, dynamic>{'type': 'raw', 'raw': 'float y = 2.0;'},
        ]),
      );
      expect(hlsl, contains('float x = 1.0'));
      expect(hlsl, contains('float y = 2.0'));
    });
  });
}
