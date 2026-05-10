import 'dart:convert';

/// Matches [NormalizeShaderName] in MetalShaderManager.mm (ASCII lower case).
String normalizeCryMetalShaderName(String name) {
  return name.toLowerCase();
}

Set<String> manifestNormalizedKeysFromJson(String manifestJson) {
  final dynamic decoded = jsonDecode(manifestJson);
  if (decoded is! List) {
    throw FormatException('generated_manifest.json must be a JSON array');
  }
  final Set<String> out = {};
  for (final dynamic item in decoded) {
    if (item is Map && item['normalized'] is String) {
      out.add(item['normalized'] as String);
    }
  }
  return out;
}

List<Map<String, dynamic>> backlogEntriesFromJson(String backlogJson) {
  final dynamic decoded = jsonDecode(backlogJson);
  if (decoded is! Map) {
    throw FormatException('backlog must be a JSON object');
  }
  final dynamic entries = decoded['entries'];
  if (entries is! List) {
    throw FormatException('backlog.entries must be a list');
  }
  final List<Map<String, dynamic>> out = [];
  for (final dynamic e in entries) {
    if (e is Map) {
      out.add(Map<String, dynamic>.from(e));
    }
  }
  return out;
}

/// Returns normalized names from backlog that are absent from [manifestKeys].
List<String> missingBacklogNormals(
  Set<String> manifestKeys,
  List<Map<String, dynamic>> backlogEntries,
) {
  final List<String> missing = [];
  for (final Map<String, dynamic> e in backlogEntries) {
    final dynamic n = e['name'];
    if (n is! String || n.isEmpty) {
      continue;
    }
    final String norm = normalizeCryMetalShaderName(n);
    if (!manifestKeys.contains(norm)) {
      missing.add(norm);
    }
  }
  return missing;
}

String renderGatesDiagnosisHelp() {
  return '''
Metal / black-world investigation (CryTrace)

1) cry_trace_render_gates defaults to 1 (set 0 to disable). Override in console or SystemCfgOverride.Cfg.

2) After reproducing, grep log.txt for: [CryTrace]

3) If the screen stays black for ~60s and there is still no [CryTrace] while using a Debug build, capture a main-thread sample while black:
   sample <pid> 5 -file /tmp/farcry_black.txt

4) @ClientHasQuit / ShutdownClient: emitted from CXGame::ShutdownClient (GameClientServer.cpp). Expected call sites include:
   - CXGame destructor / shutdown (Game.cpp)
   - LoadLevel when keepclient is false (Game.cpp) before restarting server/client
   - SaveConfiguration while quitting (GameLoading.cpp)
   - StartupClient failure paths (GameClientServer.cpp)
   - Script Game.Connect / Game.Disconnect (ScriptObjectGame.cpp)
   A quit immediately before a second "Loading level" is usually intentional teardown for reload, not proof of failure.

5) Shader manifest gaps: run dart run shader_port:shader_metal_backlog <repo-root>
   Full pipeline: dart tools/shader_port/bin/validate_migration.dart <repo-root>
''';
}
