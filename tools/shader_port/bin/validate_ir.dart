import 'dart:convert';
import 'dart:io';

import 'package:shader_port/ir_validator.dart';

void main(List<String> args) {
  String rootArg = '.';
  String? irDirArg;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--ir-dir' && i + 1 < args.length) {
      irDirArg = args[++i];
    } else if (!args[i].startsWith('--')) {
      rootArg = args[i];
    }
  }

  final Directory root = Directory(rootArg).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath =
      root.path.endsWith(sep) ? root.path : '${root.path}$sep';

  final String irPath = irDirArg ??
      '${rootPath}tools${sep}shader_port${sep}output${sep}ir';
  final Directory irDir = Directory(irPath);

  if (!irDir.existsSync()) {
    stderr.writeln('IR directory not found: $irPath');
    stderr.writeln(
      'Run dart tools/shader_port/lib/parser.dart first to generate IR files.',
    );
    exit(1);
  }

  final IrValidator validator = IrValidator();
  final List<IrValidationError> allErrors = <IrValidationError>[];
  int checked = 0;
  int failed = 0;

  for (final FileSystemEntity entity
      in irDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.json')) continue;
    final String fileName = entity.path.split(sep).last;
    if (fileName == 'index.json') continue;

    final dynamic parsed;
    try {
      parsed = jsonDecode(entity.readAsStringSync(encoding: utf8));
    } catch (e) {
      stderr.writeln('WARN: validate_ir: could not parse ${entity.path}: $e');
      continue;
    }

    if (parsed is! Map<String, dynamic>) continue;

    final String relative = entity.path
        .substring(irDir.path.length + 1)
        .replaceAll(RegExp(r'[\\/]'), '/');

    final IrValidationResult result = validator.validateIr(parsed, relative);
    checked++;

    if (!result.passed) {
      failed++;
      for (final IrValidationError error in result.errors) {
        allErrors.add(error);
        stderr.writeln(error.toString());
      }
    }
  }

  if (checked == 0) {
    stderr.writeln('No IR JSON files found in: $irPath');
    exit(1);
  }

  if (allErrors.isEmpty) {
    stdout.writeln('IR validation passed: $checked shaders checked, 0 errors.');
    exit(0);
  }

  stdout.writeln(
    '\nIR validation failed: $failed/$checked shaders have errors '
    '(${allErrors.length} total).',
  );
  exit(1);
}
