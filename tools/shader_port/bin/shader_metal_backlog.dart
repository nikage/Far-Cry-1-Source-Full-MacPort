import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shader_port/shader_metal_backlog.dart';

Future<void> main(List<String> args) async {
  final String root = args.isNotEmpty
      ? args.first
      : Directory.current.path;
  final String manifestPath = p.join(
    root,
    'RenderDll',
    'XRenderMetal',
    'Generated',
    'generated_manifest.json',
  );
  final String backlogPath = p.join(
    root,
    'tools',
    'shader_port',
    'config',
    'ef_load_shader_metal_backlog.json',
  );

  final File mf = File(manifestPath);
  final File bf = File(backlogPath);
  if (!mf.existsSync()) {
    stderr.writeln('Missing $manifestPath (run validate_migration / generator first).');
    exitCode = 2;
    return;
  }
  if (!bf.existsSync()) {
    stderr.writeln('Missing $backlogPath');
    exitCode = 2;
    return;
  }

  final Set<String> keys =
      manifestNormalizedKeysFromJson(mf.readAsStringSync());
  final List<Map<String, dynamic>> entries =
      backlogEntriesFromJson(bf.readAsStringSync());
  final List<String> missing = missingBacklogNormals(keys, entries);

  stdout.writeln(
    'Manifest normalized entries: ${keys.length}; backlog entries: ${entries.length}',
  );
  if (missing.isEmpty) {
    stdout.writeln('All backlog shader base names are present in the manifest.');
    return;
  }
  stdout.writeln('Still missing from manifest (normalized):');
  for (final String m in missing) {
    stdout.writeln('  $m');
  }
  stdout.writeln(
    '\nNext: extend tools/shader_port generator / shader_pair_overrides.json, then:',
  );
  stdout.writeln('  dart tools/shader_port/bin/validate_migration.dart $root');
}
