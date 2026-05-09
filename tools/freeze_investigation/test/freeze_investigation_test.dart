import 'package:test/test.dart';
import 'package:freeze_investigation/freeze_investigation.dart';

void main() {
  test('stack capture block documents sample and lldb', () {
    expect(kStackCaptureShellBlock, contains('sample'));
    expect(kStackCaptureShellBlock, contains('lldb'));
    expect(kStackCaptureShellBlock, contains('bt all'));
  });

  test('exit 9 notes mention SIGKILL', () {
    expect(kExitCode9Notes, contains('SIGKILL'));
  });

  test('checklist is non-empty and references FreezeInv prefix', () {
    final c = investigationChecklist();
    expect(c, isNotEmpty);
    expect(c.join('\n'), contains(kFreezeInvLogPrefix));
  });

  test('shader risk sites list vehicle and player light', () {
    expect(kShaderNullRiskSites.join(' '), contains('XVehicle'));
    expect(kShaderNullRiskSites.join(' '), contains('XPlayerLight'));
  });
}
