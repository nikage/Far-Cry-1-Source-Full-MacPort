import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class VideoSpec {
  VideoSpec({
    required this.id,
    required this.source,
    required this.output,
  });

  final String id;
  final String source;
  final String output;

  static List<VideoSpec> loadFromYaml(String contents) {
    final data = loadYaml(contents) as YamlMap;
    final rawVideos = data['videos'] as YamlList? ?? YamlList();
    return rawVideos
        .map((entry) {
          final map = entry as YamlMap;
          final id = map['id']?.toString();
          final source = map['source']?.toString();
          final output = map['output']?.toString();
          if (id == null || source == null || output == null) {
            return null;
          }
          return VideoSpec(id: id, source: source, output: output);
        })
        .whereType<VideoSpec>()
        .toList(growable: false);
  }
}

class ConversionConfig {
  ConversionConfig({
    required this.manifestPath,
    required this.inputDirectory,
    required this.outputDirectory,
    required this.pakOutputPath,
    required this.pakDirectory,
    this.ffmpegPath = 'ffmpeg',
    this.ffprobePath = 'ffprobe',
    this.crf = 18,
    this.preset = 'slow',
    this.audioBitrate = '192k',
  });

  final String manifestPath;
  final String inputDirectory;
  final String outputDirectory;
  final String pakOutputPath;
  final String pakDirectory;
  final String ffmpegPath;
  final String ffprobePath;
  final int crf;
  final String preset;
  final String audioBitrate;
}

class ConversionResult {
  ConversionResult({
    required this.spec,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.durationSeconds,
    required this.outputPath,
  });

  final VideoSpec spec;
  final int width;
  final int height;
  final double frameRate;
  final double durationSeconds;
  final String outputPath;
}

abstract class ProcessRunner {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

class SystemProcessRunner implements ProcessRunner {
  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    return Process.run(executable, arguments, workingDirectory: workingDirectory);
  }
}

class IntroVideoConverter {
  IntroVideoConverter({ProcessRunner? runner}) : _runner = runner ?? SystemProcessRunner();

  final ProcessRunner _runner;

  Future<List<ConversionResult>> convert(ConversionConfig config) async {
    final manifestFile = File(config.manifestPath);
    if (!manifestFile.existsSync()) {
      throw StateError('Manifest not found: ${config.manifestPath}');
    }
    final specs = VideoSpec.loadFromYaml(manifestFile.readAsStringSync());
    if (specs.isEmpty) {
      return <ConversionResult>[];
    }

    final outputDir = Directory(config.outputDirectory);
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    final results = <ConversionResult>[];
    for (final spec in specs) {
      final sourcePath = p.join(config.inputDirectory, spec.source);
      final metadata = await _probeMetadata(config.ffprobePath, sourcePath);
      final targetPath = p.join(config.outputDirectory, spec.output);
      await _transcode(config, sourcePath, targetPath);
      results.add(
        ConversionResult(
          spec: spec,
          width: metadata.width,
          height: metadata.height,
          frameRate: metadata.frameRate,
          durationSeconds: metadata.durationSeconds,
          outputPath: targetPath,
        ),
      );
    }

    await _writePak(config, results);
    return results;
  }

  Future<_ProbeMetadata> _probeMetadata(String ffprobePath, String source) async {
    final args = [
      '-v',
      'quiet',
      '-print_format',
      'json',
      '-show_streams',
      source,
    ];
    final result = await _runner.run(ffprobePath, args);
    if (result.exitCode != 0) {
      throw StateError('ffprobe failed for $source: ${result.stderr}');
    }
    final data = jsonDecode(result.stdout as String);
    final streams = data['streams'] as List<dynamic>? ?? <dynamic>[];
    final videoStream = streams.firstWhere(
      (stream) => stream['codec_type'] == 'video',
      orElse: () => null,
    );
    if (videoStream == null) {
      throw StateError('No video stream found for $source');
    }
    final width = videoStream['width'] as int? ?? 0;
    final height = videoStream['height'] as int? ?? 0;
    final avgFrameRate = videoStream['avg_frame_rate'] as String? ?? '0/1';
    final duration = (videoStream['duration'] as String?) ?? data['format']?['duration']?.toString() ?? '0';
    final frameRate = _parseRate(avgFrameRate);
    final durationSeconds = double.tryParse(duration) ?? 0;
    return _ProbeMetadata(
      width: width,
      height: height,
      frameRate: frameRate,
      durationSeconds: durationSeconds,
    );
  }

  Future<void> _transcode(ConversionConfig config, String source, String target) async {
    final parent = Directory(p.dirname(target));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final args = [
      '-y',
      '-i',
      source,
      '-c:v',
      'libx264',
      '-preset',
      config.preset,
      '-crf',
      config.crf.toString(),
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      config.audioBitrate,
      '-movflags',
      '+faststart',
      target,
    ];
    final result = await _runner.run(config.ffmpegPath, args);
    if (result.exitCode != 0) {
      throw StateError('ffmpeg failed for $source: ${result.stderr}');
    }
  }

  Future<void> _writePak(ConversionConfig config, List<ConversionResult> results) async {
    final archive = Archive();
    for (final result in results) {
      final file = File(result.outputPath);
      if (!file.existsSync()) {
        continue;
      }
      final data = file.readAsBytesSync();
      final entryPath = p.posix.join(config.pakDirectory.replaceAll('\\', '/'), result.spec.output);
      archive.addFile(ArchiveFile(entryPath, data.length, data));
    }
    final encoder = ZipEncoder();
    final pakBytes = encoder.encode(archive);
    File(config.pakOutputPath).writeAsBytesSync(pakBytes);
  }

  double _parseRate(String rate) {
    final parts = rate.split('/');
    if (parts.length != 2) {
      return 0;
    }
    final num = double.tryParse(parts[0]) ?? 0;
    final den = double.tryParse(parts[1]) ?? 1;
    if (den == 0) {
      return 0;
    }
    return num / den;
  }
}

class _ProbeMetadata {
  _ProbeMetadata({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.durationSeconds,
  });

  final int width;
  final int height;
  final double frameRate;
  final double durationSeconds;
}

