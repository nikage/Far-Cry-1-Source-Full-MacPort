import 'dart:io';

import '../lib/pair_validator.dart';

void main(List<String> args) {
  bool strict = false;
  String? manifestPath;

  for (final String arg in args) {
    if (arg == '--strict') {
      strict = true;
    } else if (!arg.startsWith('--')) {
      manifestPath = arg;
    }
  }

  if (manifestPath == null) {
    stderr.writeln(
      'Usage: dart run bin/validate_pairs.dart <generated_manifest.json> [--strict]',
    );
    exit(2);
  }

  final ValidatorResult result = validateManifestFile(manifestPath);

  final int covered = result.pairedFragments + result.fullscreenFragments;
  stdout.writeln(
    'Shader pairing: $covered/${result.totalFragments} fragments covered '
    '(${result.pairedFragments} paired, ${result.fullscreenFragments} fullscreen)',
  );
  stdout.writeln(
    'Coverage: ${(result.coverageRatio * 100).toStringAsFixed(1)}%',
  );

  if (result.warnings.isNotEmpty) {
    stdout.writeln('\nWarnings (Rule 3 — structural compatibility):');
    for (final ValidationError w in result.warnings) {
      stdout.writeln('  $w');
    }
  }

  if (result.errors.isNotEmpty) {
    stderr.writeln('\nErrors:');
    for (final ValidationError e in result.errors) {
      stderr.writeln('  $e');
    }
    exit(1);
  }

  if (strict && result.warnings.isNotEmpty) {
    stderr.writeln('\n--strict: warnings treated as errors');
    exit(1);
  }

  stdout.writeln('\nAll pairing rules passed.');
}
