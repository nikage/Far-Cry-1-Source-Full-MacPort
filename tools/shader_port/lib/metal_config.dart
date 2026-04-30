import 'dart:convert';
import 'dart:io';

/// Metal toolchain configuration read from config/metal_toolchain.json.
///
/// Resolution order:
///   1. METAL_STD environment variable (allows CI / test override)
///   2. config/metal_toolchain.json relative to the current working directory
///      (correct when `dart test` or scripts are run from the package root)
///   3. config/metal_toolchain.json relative to the entry-point script's
///      parent-parent directory (bin/*.dart or lib/*.dart invoked directly)
///   4. Hardcoded fallback 'metal3.0'
///
/// Result is cached after the first read.
String get metalStd => _metalStd;
late final String _metalStd = _load();

String _load() {
  final String? envOverride = Platform.environment['METAL_STD'];
  if (envOverride != null && envOverride.isNotEmpty) return envOverride;

  final String sep = Platform.pathSeparator;
  final String relPath = 'config${sep}metal_toolchain.json';

  final List<String> candidates = <String>[
    // Correct when running `dart test` from the package root (tools/shader_port/)
    '${Directory.current.path}$sep$relPath',
    // Correct when running a bin/*.dart or lib/*.dart script directly
    '${File(Platform.script.toFilePath()).parent.parent.path}$sep$relPath',
  ];

  for (final String path in candidates) {
    final File f = File(path);
    if (f.existsSync()) {
      final Map<String, dynamic> data =
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return data['metalStd'] as String;
    }
  }

  return 'metal3.0'; // safe fallback — keeps all callers working even if config is missing
}
