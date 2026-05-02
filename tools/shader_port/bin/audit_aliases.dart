/// Parses Assets/Shaders/Source/Shaders/CustomAliases.txt and cross-references
/// the generated Metal manifest to report shader aliases and their resolved targets.
///
/// Usage:
///   dart tools/shader_port/bin/audit_aliases.dart [<project_root>]
///
/// Exit codes:
///   0 = all aliases resolve to a known Metal target
///   1 = one or more aliases have no resolvable Metal target (unresolved)
library audit_aliases;

import 'dart:convert';
import 'dart:io';

import '../lib/alias_auditor.dart';

void main(List<String> args) {
  final root = args.isEmpty ? '.' : args.first;

  final customAliasesPath =
      '$root/Assets/Shaders/Source/Shaders/CustomAliases.txt';
  final manifestPath =
      '$root/RenderDll/XRenderMetal/Generated/generated_manifest.json';

  final aliasFile = File(customAliasesPath);
  final manifestFile = File(manifestPath);

  if (!aliasFile.existsSync()) {
    stderr.writeln('ERROR: CustomAliases.txt not found at $customAliasesPath');
    exit(2);
  }
  if (!manifestFile.existsSync()) {
    stderr.writeln('ERROR: generated_manifest.json not found at $manifestPath');
    stderr.writeln('       Run: dart tools/shader_port/bin/validate_migration.dart .');
    exit(2);
  }

  final aliasContent = aliasFile.readAsStringSync();
  final manifestJson = jsonDecode(manifestFile.readAsStringSync()) as List;

  final manifestNames = {
    for (final e in manifestJson) (e as Map<String, dynamic>)['normalized'] as String,
  };

  final pairs = parseCustomAliases(aliasContent);
  final results = auditAliases(pairs, manifestNames);

  var unresolved = 0;
  var resolved = 0;

  for (final r in results) {
    if (r.metalTarget == null) {
      stderr.writeln('UNRESOLVED  ${r.alias.padRight(52)} <- ${r.rawTarget}');
      unresolved++;
    } else {
      stdout.writeln('OK          ${r.alias.padRight(52)} -> ${r.metalTarget}');
      resolved++;
    }
  }

  stdout.writeln('');
  stdout.writeln('${results.length} aliases total: $resolved resolved, $unresolved unresolved.');

  if (unresolved > 0) {
    stderr.writeln('\nAction required: add explicit alias entries for unresolved names.');
    exit(1);
  }
}
