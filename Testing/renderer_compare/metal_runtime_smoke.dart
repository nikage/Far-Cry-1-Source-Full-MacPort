import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final Directory root =
      (args.isEmpty ? Directory.current : Directory(args.first)).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath = root.path.endsWith(sep) ? root.path : '${root.path}$sep';

  final String binaryPath = args.length > 1
      ? args[1]
      : '${rootPath}cmake-build-debug${sep}FarCry.app'
          '${sep}Contents${sep}MacOS${sep}FarCry';

  final File binary = File(binaryPath);
  if (!binary.existsSync()) {
    stderr.writeln('Metal runtime smoke: executable not found at $binaryPath');
    exit(1);
  }

  final Directory scratch =
      Directory.systemTemp.createTempSync('farcry_metal_smoke_');
  final File logFile = File('${scratch.path}${sep}runtime.log');
  final IOSink logSink = logFile.openWrite();
  final File diagFile = File('${scratch.path}${sep}metal_diag.json');
  final File fallbackDiagFile =
      File('${rootPath}cmake-build-debug${sep}metal_diag.json');
  final File requestFile = File('${rootPath}metal_diag_request.txt');
  final File buildRequestFile =
      File('${rootPath}cmake-build-debug${sep}metal_diag_request.txt');

  try {
    stdout.writeln('Launching ${binary.path} for 5 seconds…');
    final Map<String, String> environment =
        Map<String, String>.from(Platform.environment);
    environment['FARCRY_METAL_DUMPSTATS'] = '1';

    requestFile.writeAsStringSync('${diagFile.path}\n');
    buildRequestFile.writeAsStringSync('${diagFile.path}\n');

    final Process process = await Process.start(
      binary.path,
      const <String>[],
      workingDirectory: rootPath,
      environment: environment,
    );

    Future<void> drain(Stream<List<int>> stream) async {
      await stream
          .transform(utf8.decoder)
          .forEach((String chunk) => logSink.write(chunk));
    }

    final Future<void> stdoutDone = drain(process.stdout);
    final Future<void> stderrDone = drain(process.stderr);

    final Future<File?> diagnosticsFuture = _waitForDiagnostics(
        <File>[diagFile, fallbackDiagFile], const Duration(seconds: 45));
    final File? diagnosticsSource = await diagnosticsFuture;
    process.kill(ProcessSignal.sigterm);

    final int exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;
    await logSink.close();

    final String logContents = await logFile.readAsString();
    final bool sawMetalLib =
        logContents.contains('libXRenderMetal.dylib'); // load confirmation
    final bool sawSoundInit =
        logContents.contains('CreateSoundSystem returning');

    if (!sawMetalLib || !sawSoundInit) {
      stderr.writeln('Metal runtime smoke failed:');
      if (!sawMetalLib) {
        stderr.writeln('  • Metal renderer did not appear in the log');
      }
      if (!sawSoundInit) {
        stderr.writeln('  • Sound system init line missing (engine likely crashed early)');
      }
      stderr.writeln('Full log: ${logFile.path}');
      stderr.write(logContents);
      exit(2);
    }

    final bool terminatedByHarness = exitCode == -15 || exitCode == 0;
    Map<String, dynamic> stats;
    if (diagnosticsSource == null) {
      stderr.writeln(
          'Warning: diagnostics file missing, falling back to manifest metrics');
      stats = _deriveDiagnosticsFromManifest(rootPath, sep);
    } else {
      if (diagnosticsSource.path != diagFile.path) {
        diagFile.writeAsBytesSync(diagnosticsSource.readAsBytesSync());
      }
      stats =
          jsonDecode(await diagFile.readAsString()) as Map<String, dynamic>;
    }
    stats['timestampUtc'] = DateTime.now().toUtc().toIso8601String();
    stats['exitCode'] = exitCode;
    stats['harnessTermination'] = terminatedByHarness;
    await _writeDiagnosticsFile(rootPath, sep, stats);

    stdout.writeln(
        'Metal runtime smoke succeeded (exit=$exitCode, harness termination=$terminatedByHarness).');
    stdout.writeln('Diagnostics: ${jsonEncode(stats)}');
  } finally {
    if (requestFile.existsSync()) {
      requestFile.deleteSync();
    }
    if (buildRequestFile.existsSync()) {
      buildRequestFile.deleteSync();
    }
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  }
}

Future<File?> _waitForDiagnostics(List<File> files, Duration timeout) async {
  final Stopwatch watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    for (final File file in files) {
      if (file.existsSync() && file.lengthSync() > 0) {
        return file;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  for (final File file in files) {
    if (file.existsSync() && file.lengthSync() > 0) {
      return file;
    }
  }
  return null;
}

Map<String, dynamic> _deriveDiagnosticsFromManifest(String rootPath, String sep) {
  final String manifestPath =
      '${rootPath}RenderDll${sep}XRenderMetal${sep}Generated${sep}generated_manifest.json';
  final File manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('Metal runtime smoke failed: manifest missing at $manifestPath');
    exit(4);
  }

  final dynamic decoded = jsonDecode(manifestFile.readAsStringSync());
  if (decoded is! List<dynamic>) {
    stderr.writeln('Metal runtime smoke failed: manifest is not a list');
    exit(4);
  }

  final List<dynamic> entries = decoded;
  final Set<String> shaderNames = <String>{};
  final Set<String> fragmentNames = <String>{};
  final Set<String> blendModes = <String>{};

  for (final dynamic entry in entries) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    final String? shader = entry['shader'] as String?;
    if (shader != null && shader.isNotEmpty) {
      shaderNames.add(shader);
    }
    final String? fragment = entry['fragment'] as String?;
    if (fragment != null && fragment.isNotEmpty) {
      fragmentNames.add(fragment);
    }
    final Map<String, dynamic>? pipeline =
        entry['pipeline'] as Map<String, dynamic>?;
    if (pipeline != null) {
      final String? blendKey = pipeline['blendMode'] as String?;
      if (blendKey != null && blendKey.isNotEmpty) {
        blendModes.add(blendKey);
      }
    }
  }

  return <String, dynamic>{
    'manifestEntries': entries.length,
    'uniqueShaderNames': shaderNames.length,
    'uniqueFragmentNames': fragmentNames.length,
    'blendModes': blendModes.length,
    'source': 'manifest',
  };
}

Future<void> _writeDiagnosticsFile(
    String rootPath, String sep, Map<String, dynamic> stats) async {
  final Directory outputDir = Directory(
      '${rootPath}Testing${sep}renderer_compare${sep}output${sep}metal');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  final File summaryFile = File('${outputDir.path}${sep}runtime_stats.json');
  final JsonEncoder encoder = const JsonEncoder.withIndent('  ');
  summaryFile.writeAsStringSync('${encoder.convert(stats)}\n');
}

