import 'dart:convert';
import 'dart:io';

class Scenario {
  Scenario(this.name, this.capture, this.filename);

  final String name;
  final String capture;
  final String filename;
}

class ScenarioResult {
  ScenarioResult(this.scenario, this.status, this.message);

  final Scenario scenario;
  final String status;
  final String message;

  Map<String, dynamic> toJson() => {
        'name': scenario.name,
        'status': status,
        'message': message,
      };
}

void main(List<String> rawArgs) {
  final Map<String, String> options = <String, String>{};
  String rootPath = Directory.current.path;
  int index = 0;
  if (rawArgs.isNotEmpty && !rawArgs[0].startsWith('--')) {
    rootPath = rawArgs[0];
    index = 1;
  }
  for (int i = index; i < rawArgs.length; ++i) {
    final String arg = rawArgs[i];
    if (arg.startsWith('--')) {
      final int eq = arg.indexOf('=');
      if (eq == -1) {
        options[arg.substring(2)] = 'true';
      } else {
        final String key = arg.substring(2, eq);
        final String value = arg.substring(eq + 1);
        options[key] = value;
      }
    } else {
      stderr.writeln('Unrecognised argument "$arg"');
      exit(64);
    }
  }

  final Directory root = Directory(rootPath).absolute;
  if (!root.existsSync()) {
    stderr.writeln('Root path not found: ${root.path}');
    exit(1);
  }
  final String sep = Platform.pathSeparator;

  final String scenariosPath = options['scenarios'] ??
      root.path + '${sep}Testing${sep}renderer_compare${sep}scenarios.json';
  final File scenariosFile = File(scenariosPath);
  if (!scenariosFile.existsSync()) {
    stderr.writeln('Scenario configuration not found: ${scenariosFile.path}');
    exit(1);
  }

  final Map<String, dynamic> parsed =
      jsonDecode(scenariosFile.readAsStringSync(encoding: utf8))
          as Map<String, dynamic>;
  final List<dynamic> scenarioList = parsed['scenarios'] as List<dynamic>? ?? <dynamic>[];
  if (scenarioList.isEmpty) {
    stderr.writeln('Scenario configuration does not contain any entries');
    exit(1);
  }

  final List<Scenario> scenarios = scenarioList.map((dynamic entry) {
    if (entry is! Map<String, dynamic>) {
      return Scenario('unknown', 'unknown', 'unknown.png');
    }
    final String name = (entry['name'] as String?) ?? 'unnamed';
    final String capture = (entry['capture'] as String?) ?? name;
    final String filename = (entry['filename'] as String?) ?? '$capture.png';
    return Scenario(name, capture, filename);
  }).toList();

  final Directory outputRoot = Directory(options['output'] ??
      root.path + '${sep}Testing${sep}renderer_compare${sep}output');
  outputRoot.createSync(recursive: true);

  final Directory d3d9Dir = Directory(options['d3d9-dir'] ??
      outputRoot.path + '${sep}d3d9');
  d3d9Dir.createSync(recursive: true);

  final Directory metalDir = Directory(options['metal-dir'] ??
      outputRoot.path + '${sep}metal');
  metalDir.createSync(recursive: true);

  final String? d3d9CommandTemplate = options['d3d9-cmd'];
  final String? metalCommandTemplate = options['metal-cmd'];

  final List<ScenarioResult> results = <ScenarioResult>[];

  for (final Scenario scenario in scenarios) {
    final File d3d9Output = File('${d3d9Dir.path}${sep}${scenario.filename}');
    final File metalOutput = File('${metalDir.path}${sep}${scenario.filename}');

    if (d3d9CommandTemplate != null) {
      _runCaptureCommand(d3d9CommandTemplate, scenario, d3d9Output, root);
    }
    if (metalCommandTemplate != null) {
      _runCaptureCommand(metalCommandTemplate, scenario, metalOutput, root);
    }

    if (!d3d9Output.existsSync() && !metalOutput.existsSync()) {
      results.add(ScenarioResult(scenario, 'missing',
          'Both renderer outputs are missing for ${scenario.filename}'));
      continue;
    }
    if (!d3d9Output.existsSync()) {
      results.add(ScenarioResult(scenario, 'missing',
          'D3D9 output missing at ${d3d9Output.path}')); 
      continue;
    }
    if (!metalOutput.existsSync()) {
      results.add(ScenarioResult(scenario, 'missing',
          'Metal output missing at ${metalOutput.path}'));
      continue;
    }

    final FileComparison comparison = _compareFiles(d3d9Output, metalOutput);
    if (comparison.equal) {
      results.add(ScenarioResult(scenario, 'match',
          'Outputs match (${comparison.length} bytes)'));
    } else {
      results.add(ScenarioResult(scenario, 'diff',
          'Mismatch at byte ${comparison.firstDifference} (sizes ${comparison.length} vs ${comparison.otherLength})'));
    }
  }

  final int failures =
      results.where((ScenarioResult r) => r.status != 'match').length;

  for (final ScenarioResult result in results) {
    stdout.writeln('[${result.status.toUpperCase()}] ${result.scenario.name}: ${result.message}');
  }

  final Map<String, dynamic> summary = {
    'root': root.path,
    'd3d9Dir': d3d9Dir.path,
    'metalDir': metalDir.path,
    'scenarios': results.map((ScenarioResult r) => r.toJson()).toList(),
    'failures': failures,
  };
  final File summaryFile =
      File('${outputRoot.path}${sep}comparison_summary.json');
  summaryFile.writeAsStringSync(jsonEncode(summary), encoding: utf8);

  if (failures == 0) {
    stdout.writeln('Renderer comparison succeeded for ${results.length} scenario(s).');
    exit(0);
  } else {
    stderr.writeln('Renderer comparison failed for $failures scenario(s). See ${summaryFile.path}');
    exit(2);
  }
}

void _runCaptureCommand(String template, Scenario scenario, File outputFile, Directory root) {
  final String command = template
      .replaceAll('{scenario}', scenario.capture)
      .replaceAll('{output}', outputFile.path);
  stdout.writeln('Executing: $command');
  final ProcessResult result = Process.runSync(
      Platform.isWindows ? 'cmd' : '/bin/sh',
      Platform.isWindows ? <String>['/c', command] : <String>['-c', command],
      workingDirectory: root.path);
  if (result.exitCode != 0) {
    stderr.writeln('Capture command failed for ${scenario.name}: ${result.stderr}');
  }
}

class FileComparison {
  FileComparison(this.equal, this.length, this.otherLength, this.firstDifference);

  final bool equal;
  final int length;
  final int otherLength;
  final int firstDifference;
}

FileComparison _compareFiles(File a, File b) {
  final List<int> bytesA = a.readAsBytesSync();
  final List<int> bytesB = b.readAsBytesSync();
  if (bytesA.length != bytesB.length) {
    return FileComparison(false, bytesA.length, bytesB.length, -1);
  }
  for (int i = 0; i < bytesA.length; ++i) {
    if (bytesA[i] != bytesB[i]) {
      return FileComparison(false, bytesA.length, bytesB.length, i);
    }
  }
  return FileComparison(true, bytesA.length, bytesB.length, -1);
}
