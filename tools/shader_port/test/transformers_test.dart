import 'package:shader_port/metal_generator.dart';
import 'package:test/test.dart';

void main() {
  group('FloatMacroTransformer', () {
    final FloatMacroTransformer t = FloatMacroTransformer();

    test('replaces FLOAT2 with float2', () {
      expect(t.transform('FLOAT2 v;'), 'float2 v;');
    });

    test('replaces FLOAT3 with float3', () {
      expect(t.transform('FLOAT3 pos;'), 'float3 pos;');
    });

    test('replaces FLOAT4 with float4', () {
      expect(t.transform('FLOAT4 col;'), 'float4 col;');
    });

    test('replaces FLOAT2x3 with float2x3', () {
      expect(t.transform('FLOAT2x3 m;'), 'float2x3 m;');
    });

    test('replaces standalone FLOAT with float', () {
      expect(t.transform('FLOAT x;'), 'float x;');
    });

    test('does not alter already-lowercase float', () {
      expect(t.transform('float4 v;'), 'float4 v;');
    });

    test('handles multiple occurrences on one line', () {
      expect(t.transform('FLOAT2 a; FLOAT3 b;'), 'float2 a; float3 b;');
    });
  });

  group('ZeroCastTransformer', () {
    final ZeroCastTransformer t = ZeroCastTransformer();

    test('converts float4 zero cast to float4(0.0)', () {
      expect(
        t.transform('float4 c = (float4)0;'),
        'float4 c = float4(0.0);',
      );
    });

    test('converts float2 zero cast to float2(0.0)', () {
      expect(
        t.transform('float2 v = (float2)0.0;'),
        'float2 v = float2(0.0);',
      );
    });

    test('leaves unrelated code unchanged', () {
      expect(t.transform('float x = y;'), 'float x = y;');
    });
  });

  group('HalfTypeTransformer', () {
    final HalfTypeTransformer t = HalfTypeTransformer();

    test('replaces half with float', () {
      expect(t.transform('half x;'), 'float x;');
    });

    test('replaces half2 with float2', () {
      expect(t.transform('half2 v;'), 'float2 v;');
    });

    test('replaces half4 with float4', () {
      expect(t.transform('half4 c = half4(1.0, 0.0, 0.0, 1.0);'),
          'float4 c = float4(1.0, 0.0, 0.0, 1.0);');
    });

    test('replaces half3x3 matrix type', () {
      expect(t.transform('half3x3 m;'), 'float3x3 m;');
    });

    test('does not alter float types', () {
      expect(t.transform('float4 v;'), 'float4 v;');
    });
  });

  group('MatrixCastTransformer', () {
    final MatrixCastTransformer t = MatrixCastTransformer();

    test('expands float3x3 cast into row-slice constructor', () {
      final String out = t.transform('float3x3 m = ((float3x3)myMat4);');
      expect(out, contains('float3x3(float3(myMat4[0].xyz)'));
      expect(out, contains('float3(myMat4[1].xyz)'));
      expect(out, contains('float3(myMat4[2].xyz)'));
    });

    test('ignores lines without float3x3 cast', () {
      const String line = 'float4 v = float4(1.0);';
      expect(t.transform(line), line);
    });
  });

  group('HdrEncodeAmbTransformer', () {
    final HdrEncodeAmbTransformer t = HdrEncodeAmbTransformer();

    test('unwraps HDREncodeAmb call', () {
      expect(t.transform('return HDREncodeAmb(color);'), 'return color;');
    });

    test('leaves lines without HDREncodeAmb unchanged', () {
      expect(t.transform('return color;'), 'return color;');
    });
  });

  group('HdrEncodeTransformer', () {
    final HdrEncodeTransformer t = HdrEncodeTransformer();

    test('unwraps HDREncode call', () {
      expect(t.transform('HDREncode(diffuse)'), 'diffuse');
    });
  });

  group('HdrFogBlendTransformer', () {
    final HdrFogBlendTransformer t = HdrFogBlendTransformer();

    test('converts HDRFogBlend to mix/clamp', () {
      final String out = t.transform('HDRFogBlend(color, factor, fog)');
      expect(out, contains('mix(fog, color, clamp(factor, 0.0, 1.0))'));
    });

    test('leaves unrelated lines unchanged', () {
      expect(t.transform('float x = 1.0;'), 'float x = 1.0;');
    });
  });

  group('ExpandFunctionTransformer', () {
    final ExpandFunctionTransformer t = ExpandFunctionTransformer();

    test('expands EXPAND macro', () {
      final String out = t.transform('EXPAND(n)');
      expect(out, contains('2.0 * (n) - 1.0'));
    });

    test('expands EXPANDfloat3 macro', () {
      final String out = t.transform('EXPANDfloat3(n)');
      expect(out, contains('2.0 * (n) - 1.0'));
      expect(out, contains('.xyz'));
    });

    test('expands EXPANDfloat4 macro', () {
      final String out = t.transform('EXPANDfloat4(n)');
      expect(out, contains('2.0 * (n) - 1.0'));
    });
  });

  group('FracFunctionTransformer', () {
    final FracFunctionTransformer t = FracFunctionTransformer();

    test('replaces frac( with fract(', () {
      expect(t.transform('frac(x)'), 'fract(x)');
    });

    test('replaces multiple occurrences', () {
      expect(t.transform('frac(a) + frac(b)'), 'fract(a) + fract(b)');
    });

    test('does not affect fract (already correct)', () {
      expect(t.transform('fract(x)'), 'fract(x)');
    });
  });

  group('SaturateTransformer', () {
    final SaturateTransformer t = SaturateTransformer();

    test('converts saturate to clamp(x, 0, 1)', () {
      expect(t.transform('saturate(v)'), 'clamp(v, 0.0, 1.0)');
    });

    test('converts saturate inside an expression', () {
      final String out = t.transform('float x = saturate(a + b);');
      expect(out, contains('clamp(a + b, 0.0, 1.0)'));
    });

    test('leaves non-saturate lines unchanged', () {
      expect(t.transform('float x = 1.0;'), 'float x = 1.0;');
    });
  });

  group('ClampTransformer', () {
    final ClampTransformer t = ClampTransformer();

    test('normalizes integer clamp bounds to float literals', () {
      expect(t.transform('clamp(x, 0, 1)'), 'clamp(x, 0.0, 1.0)');
    });

    test('leaves float bounds unchanged', () {
      expect(t.transform('clamp(x, 0.0, 1.0)'), 'clamp(x, 0.0, 1.0)');
    });

    test('leaves lines without clamp unchanged', () {
      expect(t.transform('float x = 1.0;'), 'float x = 1.0;');
    });
  });

  group('MinMaxTransformer', () {
    final MinMaxTransformer t = MinMaxTransformer();

    test('normalizes integer min arguments to float', () {
      expect(t.transform('min(x, 0)'), 'min(x, 0.0)');
    });

    test('normalizes integer max arguments to float', () {
      expect(t.transform('max(x, 1)'), 'max(x, 1.0)');
    });

    test('leaves float arguments unchanged', () {
      expect(t.transform('min(x, 0.0)'), 'min(x, 0.0)');
    });

    test('leaves unrelated lines unchanged', () {
      expect(t.transform('float x = 1.0;'), 'float x = 1.0;');
    });
  });

  group('MulFunctionTransformer', () {
    final MulFunctionTransformer t = MulFunctionTransformer();

    test('converts mul(a, b) to (a) * (b)', () {
      expect(t.transform('mul(matA, vecB)'), '(matA) * (vecB)');
    });

    test('converts mul inside assignment', () {
      final String out = t.transform('float4 v = mul(m, p);');
      expect(out, contains('(m) * (p)'));
    });

    test('leaves non-mul lines unchanged', () {
      expect(t.transform('float x = 1.0;'), 'float x = 1.0;');
    });
  });

  group('LerpTransformer', () {
    final LerpTransformer t = LerpTransformer();

    test('converts lerp(a, b, t) to mix(a, b, t)', () {
      expect(t.transform('lerp(a, b, t)'), 'mix(a, b, t)');
    });

    test('converts lerp inside expression', () {
      final String out = t.transform('float4 c = lerp(c1, c2, factor);');
      expect(out, contains('mix(c1, c2, factor)'));
    });

    test('leaves non-lerp lines unchanged', () {
      expect(t.transform('float x = 1.0;'), 'float x = 1.0;');
    });
  });

  group('UniformReferenceTransformer', () {
    test('qualifies known uniform references with uniforms.', () {
      final UniformReferenceTransformer t =
          UniformReferenceTransformer({'LightPos', 'CameraPos'});
      expect(t.transform('float3 d = LightPos.xyz;'), contains('uniforms.LightPos.xyz'));
    });

    test('does not qualify unknown identifiers', () {
      final UniformReferenceTransformer t = UniformReferenceTransformer({'LightPos'});
      expect(t.transform('float3 d = SomeOther.xyz;'), 'float3 d = SomeOther.xyz;');
    });

    test('does not double-qualify already-qualified references', () {
      final UniformReferenceTransformer t = UniformReferenceTransformer({'LightPos'});
      final String out = t.transform('float3 a = uniforms.LightPos.xyz;');
      expect(out, isNot(contains('uniforms.uniforms')));
    });

    test('does not qualify declaration of the uniform name', () {
      final UniformReferenceTransformer t = UniformReferenceTransformer({'LightPos'});
      final String out = t.transform('float4 LightPos;');
      expect(out, isNot(contains('uniforms.LightPos')));
    });

    test('empty uniform set leaves line unchanged', () {
      final UniformReferenceTransformer t = UniformReferenceTransformer({});
      const String line = 'float4 x = SomeVar;';
      expect(t.transform(line), line);
    });
  });

  group('ComputeLightVectorsTransformer', () {
    final ComputeLightVectorsTransformer t = ComputeLightVectorsTransformer();

    test('expands ComputeLightVectors call into 5 statements', () {
      final String out = t.transform('ComputeLightVectors();');
      final List<String> stmts =
          out.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(stmts.length, 5);
    });

    test('emitted code references LightPos and CameraPos uniforms', () {
      final String out = t.transform('ComputeLightVectors();');
      expect(out, contains('uniforms.LightPos'));
      expect(out, contains('uniforms.CameraPos'));
    });

    test('leaves lines without ComputeLightVectors unchanged', () {
      const String line = 'float3 v = pos.xyz;';
      expect(t.transform(line), line);
    });
  });
}
