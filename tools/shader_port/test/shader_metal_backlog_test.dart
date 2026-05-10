import 'package:shader_port/shader_metal_backlog.dart';
import 'package:test/test.dart';

void main() {
  test('normalizeCryMetalShaderName lowercases ASCII', () {
    expect(normalizeCryMetalShaderName('GunShip_Light'), 'gunship_light');
  });

  test('manifestNormalizedKeysFromJson collects normalized field', () {
    const String json = '[{"normalized":"a"},{"normalized":"b"}]';
    expect(manifestNormalizedKeysFromJson(json), {'a', 'b'});
  });

  test('missingBacklogNormals', () {
    const String backlog = '''
{"version":1,"entries":[{"name":"InManifest"},{"name":"MissingOne"}]}
''';
    final List<Map<String, dynamic>> entries =
        backlogEntriesFromJson(backlog);
    final List<String> miss = missingBacklogNormals({'inmanifest'}, entries);
    expect(miss, ['missingone']);
  });

  test('renderGatesDiagnosisHelp mentions CryTrace and ShutdownClient', () {
    final String h = renderGatesDiagnosisHelp();
    expect(h, contains('[CryTrace]'));
    expect(h, contains('ShutdownClient'));
    expect(h, contains('sample'));
  });
}
