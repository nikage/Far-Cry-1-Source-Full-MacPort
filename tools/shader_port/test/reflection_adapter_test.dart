import 'package:shader_port/reflection_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('ReflectionAdapter', () {
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
}
