import 'package:shader_port/load_sequence_diagnosis.dart';
import 'package:test/test.dart';

void main() {
  test('loadSequenceDiagnosisHelp mentions checkpoints and grep', () {
    final String h = loadSequenceDiagnosisHelp();
    expect(h, contains('precache_OnLevelLoaded_done'));
    expect(h, contains('Lua_Game_RefreshServerList'));
    expect(h, contains('[GameCheckpoint]'));
  });
}
