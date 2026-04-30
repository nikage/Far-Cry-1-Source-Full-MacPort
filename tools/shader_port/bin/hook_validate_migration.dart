import 'dart:convert';
import 'dart:io';

bool isRelevantChange(List<String> changedFiles) {
  return changedFiles.any(
    (String f) =>
        f.contains('tools/shader_port') ||
        f.contains('RenderDll/XRenderMetal') ||
        f.contains('shader_pair_overrides'),
  );
}

String buildFollowupJson(String output) {
  final List<String> lines = output.split('\n');
  final String truncated =
      lines.length > 50 ? lines.sublist(lines.length - 50).join('\n') : output;
  final String escaped =
      truncated.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return jsonEncode(<String, String>{
    'followup_message':
        'Shader migration validation failed after your changes. '
        'Fix all reported issues before finishing.\n\n'
        '```\n$escaped\n```',
  });
}

Future<List<String>> _gitChangedFiles(String projectRoot) async {
  Future<List<String>> lines(List<String> gitArgs) async {
    final ProcessResult r = await Process.run(
      'git',
      ['-C', projectRoot, ...gitArgs],
      stdoutEncoding: utf8,
    );
    if (r.exitCode != 0) return [];
    return (r.stdout as String)
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList();
  }

  final List<String> staged = await lines(['diff', '--name-only', 'HEAD']);
  final List<String> unstaged = await lines(['diff', '--name-only']);
  return <String>{...staged, ...unstaged}.toList();
}

Future<String?> _findDartBin() async {
  for (final String candidate in ['dart', 'fvm']) {
    final ProcessResult r = await Process.run(
      'command',
      ['-v', candidate],
      runInShell: true,
    );
    if (r.exitCode == 0) return candidate == 'fvm' ? 'fvm dart' : 'dart';
  }
  return null;
}

List<String> _buildDartArgs(String dartBin, String validatorScript, String projectRoot) {
  final List<String> parts = dartBin.split(' ');
  return [
    if (parts.length > 1) parts[1],
    'run',
    validatorScript,
    projectRoot,
  ].where((String s) => s.isNotEmpty).toList();
}

Future<void> main() async {
  final String projectRoot =
      Platform.script.resolve('../../..').toFilePath();

  final List<String> changed = await _gitChangedFiles(projectRoot);
  if (!isRelevantChange(changed)) exit(0);

  final String? dartBin = await _findDartBin();
  if (dartBin == null) {
    stdout.writeln(jsonEncode(<String, String>{
      'followup_message':
          'validate-migration hook: dart not found on PATH. '
          'Install Dart SDK or fvm.',
    }));
    exit(0);
  }

  final String executable = dartBin.split(' ').first;
  final String validatorScript = Platform.script
      .resolve('validate_migration.dart')
      .toFilePath();
  final List<String> dartArgs =
      _buildDartArgs(dartBin, validatorScript, projectRoot);

  final Process process = await Process.start(executable, dartArgs);

  final StringBuffer captured = StringBuffer();

  process.stdout.transform(utf8.decoder).listen((String chunk) {
    stdout.write(chunk);
    captured.write(chunk);
  });
  process.stderr.transform(utf8.decoder).listen((String chunk) {
    stderr.write(chunk);
    captured.write(chunk);
  });

  final int exitCode = await process.exitCode;
  if (exitCode == 0) exit(0);

  stdout.writeln(buildFollowupJson(captured.toString()));
  exit(0);
}
