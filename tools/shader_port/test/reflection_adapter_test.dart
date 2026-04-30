import 'package:shader_port/reflection_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('ReflectionAdapter — happy path', () {
    test('extracts uniforms, textures, and inputs', () {
      final Map<String, dynamic> raw = <String, dynamic>{
        'EntryPoint': 'MainVS',
        'Resources': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'CBV', 'name': 'Globals', 'slot': 0},
          <String, dynamic>{'type': 'SRV', 'name': 'baseMap', 'slot': 1},
        ],
        'vertex_inputs': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'position0', 'components': 4},
        ],
      };
      final ReflectionInfo info = ReflectionAdapter(raw).toInfo();
      expect(info.entryPoint, 'MainVS');
      expect(info.uniforms, isNotEmpty);
      expect(info.textures, isNotEmpty);
      expect(info.vertexInputs.first['name'], 'position0');
    });
  });

  group('ReflectionAdapter — empty inputs', () {
    test('empty map produces empty lists and null entryPoint', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{}).toInfo();
      expect(info.uniforms, isEmpty);
      expect(info.textures, isEmpty);
      expect(info.vertexInputs, isEmpty);
      expect(info.entryPoint, isNull);
    });

    test('empty Resources list produces no uniforms or textures', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{
        'Resources': <dynamic>[],
      }).toInfo();
      expect(info.uniforms, isEmpty);
      expect(info.textures, isEmpty);
    });

    test('empty vertex_inputs list produces empty vertexInputs', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{
        'vertex_inputs': <dynamic>[],
      }).toInfo();
      expect(info.vertexInputs, isEmpty);
    });
  });

  group('ReflectionAdapter — alternate key forms', () {
    test('reads entryPoint from lowercase entryPoint key', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{
        'entryPoint': 'main',
      }).toInfo();
      expect(info.entryPoint, 'main');
    });

    test('extracts uniforms from direct uniforms list (not Resources)', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{
        'uniforms': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'DirectUniform', 'type': 'float4'},
        ],
      }).toInfo();
      expect(info.uniforms, hasLength(1));
      expect(info.uniforms.first['name'], 'DirectUniform');
    });

    test('extracts textures from direct textures list (not Resources)', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{
        'textures': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'envMap', 'slot': 0},
        ],
      }).toInfo();
      expect(info.textures, hasLength(1));
      expect(info.textures.first['name'], 'envMap');
    });

    test('reads vertex_inputs from inputs key as fallback', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{
        'inputs': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'pos', 'components': 3},
        ],
      }).toInfo();
      expect(info.vertexInputs, hasLength(1));
      expect(info.vertexInputs.first['name'], 'pos');
    });

    test('string entries in vertex_inputs are wrapped as name map', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{
        'vertex_inputs': <dynamic>['COLOR0', 'TEXCOORD0'],
      }).toInfo();
      expect(info.vertexInputs, hasLength(2));
      expect(info.vertexInputs.first['name'], 'COLOR0');
    });

    test('CBV entries use Name/Type uppercase key variants', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{
        'Resources': <Map<String, dynamic>>[
          <String, dynamic>{'Type': 'CBV', 'Name': 'Globals', 'Slot': 0},
        ],
      }).toInfo();
      expect(info.uniforms, isNotEmpty);
    });
  });

  group('ReflectionAdapter — missing top-level keys', () {
    test('missing EntryPoint returns null without throwing', () {
      expect(
        () => ReflectionAdapter(<String, dynamic>{'Resources': <dynamic>[]}).toInfo(),
        returnsNormally,
      );
      expect(
        ReflectionAdapter(<String, dynamic>{'Resources': <dynamic>[]}).toInfo().entryPoint,
        isNull,
      );
    });

    test('missing uniforms and Resources keys returns empty uniforms', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{
        'vertex_inputs': <dynamic>[],
      }).toInfo();
      expect(info.uniforms, isEmpty);
    });

    test('non-iterable Resources value is ignored without throwing', () {
      expect(
        () => ReflectionAdapter(<String, dynamic>{'Resources': 'not-a-list'}).toInfo(),
        returnsNormally,
      );
    });
  });

  group('ReflectionAdapter — arraySize propagation', () {
    test('arraySize from uniforms list is preserved in output', () {
      final ReflectionInfo info = ReflectionAdapter(<String, dynamic>{
        'uniforms': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Bones', 'type': 'float4', 'arraySize': 64},
        ],
      }).toInfo();
      expect(info.uniforms.first['arraySize'], 64);
    });
  });
}
