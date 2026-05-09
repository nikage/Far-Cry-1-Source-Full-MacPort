import 'package:shader_port/metal_generator.dart';
import 'package:test/test.dart';

void main() {
  group('resolveFragmentOutputFieldType', () {
    test('declared type in outputFieldTypes wins', () {
      expect(
        resolveFragmentOutputFieldType(
          'Color',
          const {'Color': 'float4'},
          const {},
        ),
        'float4',
      );
      expect(
        resolveFragmentOutputFieldType(
          'Color',
          const {'Color': 'float3'},
          const {'Color': 4},
        ),
        'float3',
      );
    });

    test('analyzer usage infers width; non-Depth enforces minimum float2', () {
      expect(
        resolveFragmentOutputFieldType(
          'Tex0',
          const {},
          const {'Tex0': 1},
        ),
        'float2',
      );
      expect(
        resolveFragmentOutputFieldType(
          'SomeField',
          const {},
          const {'SomeField': 3},
        ),
        'float3',
      );
      expect(
        resolveFragmentOutputFieldType(
          'Color',
          const {},
          const {'Color': 3},
        ),
        'float3',
      );
      expect(
        resolveFragmentOutputFieldType(
          'Color',
          const {},
          const {'Color': 1},
        ),
        'float2',
      );
    });

    test('Depth allows single-component float', () {
      expect(
        resolveFragmentOutputFieldType(
          'Depth',
          const {},
          const {'Depth': 1},
        ),
        'float',
      );
    });

    test('builtin Color names default to float4 without declaration or usage',
        () {
      expect(
        resolveFragmentOutputFieldType('Color', const {}, const {}),
        'float4',
      );
      expect(
        resolveFragmentOutputFieldType('Color0', const {}, const {}),
        'float4',
      );
      expect(
        resolveFragmentOutputFieldType('Color1', const {}, const {}),
        'float4',
      );
    });

    test('Depth defaults to float without declaration or usage', () {
      expect(
        resolveFragmentOutputFieldType('Depth', const {}, const {}),
        'float',
      );
    });

    test('unknown field falls back to float4', () {
      expect(
        resolveFragmentOutputFieldType('UnknownRT', const {}, const {}),
        'float4',
      );
    });
  });
}
