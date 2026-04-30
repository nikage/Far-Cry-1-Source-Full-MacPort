import 'dart:convert';

import 'package:test/test.dart';

import '../bin/hook_validate_migration.dart';

void main() {
  group('isRelevantChange', () {
    test('returns true when a tools/shader_port file changed', () {
      expect(
        isRelevantChange(['tools/shader_port/lib/metal_generator.dart']),
        isTrue,
      );
    });

    test('returns true when a RenderDll/XRenderMetal file changed', () {
      expect(
        isRelevantChange(['RenderDll/XRenderMetal/Generated/foo.metal']),
        isTrue,
      );
    });

    test('returns true when shader_pair_overrides changed', () {
      expect(
        isRelevantChange([
          'tools/shader_port/config/shader_pair_overrides.json',
        ]),
        isTrue,
      );
    });

    test('returns true when one of many changed files matches', () {
      expect(
        isRelevantChange([
          'README.md',
          'docs/notes.md',
          'tools/shader_port/bin/compile_check.dart',
        ]),
        isTrue,
      );
    });

    test('returns false when no relevant files changed', () {
      expect(
        isRelevantChange(['README.md', 'docs/notes.md', 'CMakeLists.txt']),
        isFalse,
      );
    });

    test('returns false for an empty change list', () {
      expect(isRelevantChange([]), isFalse);
    });
  });

  group('buildFollowupJson', () {
    test('returns valid JSON with followup_message key', () {
      final String json = buildFollowupJson('some error output');
      final dynamic decoded = jsonDecode(json);
      expect(decoded, isA<Map>());
      expect((decoded as Map).containsKey('followup_message'), isTrue);
    });

    test('includes error output inside the followup_message', () {
      final String json = buildFollowupJson('error: undefined symbol');
      final Map<String, dynamic> decoded =
          jsonDecode(json) as Map<String, dynamic>;
      expect(
        decoded['followup_message'] as String,
        contains('error: undefined symbol'),
      );
    });

    test('truncates output to last 50 lines', () {
      final String longOutput =
          List<String>.generate(100, (int i) => 'line $i').join('\n');
      final String json = buildFollowupJson(longOutput);
      final Map<String, dynamic> decoded =
          jsonDecode(json) as Map<String, dynamic>;
      final String msg = decoded['followup_message'] as String;
      expect(msg, contains('line 99'));
      expect(msg, isNot(contains('line 0')));
    });

    test('output shorter than 50 lines is not truncated', () {
      final String shortOutput =
          List<String>.generate(10, (int i) => 'line $i').join('\n');
      final String json = buildFollowupJson(shortOutput);
      final Map<String, dynamic> decoded =
          jsonDecode(json) as Map<String, dynamic>;
      final String msg = decoded['followup_message'] as String;
      expect(msg, contains('line 0'));
      expect(msg, contains('line 9'));
    });

    test('escapes double quotes in output so JSON remains valid', () {
      final String json = buildFollowupJson('error: type "float4" not found');
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('escapes backslashes in output so JSON remains valid', () {
      final String json = buildFollowupJson(r'path\to\file.metal');
      expect(() => jsonDecode(json), returnsNormally);
    });
  });
}
