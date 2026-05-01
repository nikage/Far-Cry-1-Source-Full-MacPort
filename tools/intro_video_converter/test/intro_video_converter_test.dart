import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:intro_video_converter/convert_config.dart';
import 'package:intro_video_converter/intro_video_converter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('buildConfig', () {
    test('paths are rooted under the given project root', () {
      final config = buildConfig('/myproject');
      expect(config.manifestPath, contains('intro_videos.yaml'));
      expect(config.inputDirectory, endsWith(p.join('Languages', 'Movies')));
      expect(config.outputDirectory, endsWith(p.join('build', 'converted_videos')));
      expect(config.pakOutputPath, endsWith('VideoConverted.pak'));
      expect(config.pakDirectory, 'languages/movies/english');
    });

    test('crf, preset and audioBitrate are forwarded', () {
      final config = buildConfig('/r', crf: 23, preset: 'fast', audioBitrate: '128k');
      expect(config.crf, 23);
      expect(config.preset, 'fast');
      expect(config.audioBitrate, '128k');
    });
  });

  group('intro_videos.yaml output paths match CMakeLists expectations', () {
    late List<VideoSpec> specs;

    setUp(() {
      final yamlPath = p.join(Directory.current.path, 'intro_videos.yaml');
      specs = VideoSpec.loadFromYaml(File(yamlPath).readAsStringSync());
    });

    test('all English intro videos output to english/English/', () {
      final introSpecs = specs.where((s) => s.source.startsWith('English/')).toList();
      expect(introSpecs, isNotEmpty);
      for (final spec in introSpecs) {
        expect(
          spec.output,
          startsWith('english/English/'),
          reason: '${spec.id}: output "${spec.output}" must start with english/English/  '
              '(CMakeLists copies converted_videos/english/English/ -> Resources/languages/movies/english/)',
        );
      }
    });

    test('demo loop outputs to english/DemoLoops/', () {
      final demoSpecs = specs.where((s) => s.source.startsWith('DemoLoops/')).toList();
      expect(demoSpecs, isNotEmpty);
      for (final spec in demoSpecs) {
        expect(
          spec.output,
          startsWith('english/DemoLoops/'),
          reason: '${spec.id}: output "${spec.output}" must start with english/DemoLoops/  '
              '(CMakeLists copies converted_videos/english/DemoLoops/ -> Resources/languages/movies/english/demoloops/)',
        );
      }
    });

    test('all outputs end with .mp4', () {
      for (final spec in specs) {
        expect(spec.output, endsWith('.mp4'), reason: '${spec.id} must produce an .mp4');
      }
    });
  });

  group('VideoSpec', () {
    test('parses manifest', () {
      const yaml = '''
videos:
  - id: first
    source: A.bik
    output: A.mp4
''';
      final specs = VideoSpec.loadFromYaml(yaml);
      expect(specs.length, 1);
      expect(specs.first.id, 'first');
      expect(specs.first.source, 'A.bik');
      expect(specs.first.output, 'A.mp4');
    });
  });

  group('IntroVideoConverter', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('intro_video_converter_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('runs ffprobe and ffmpeg for each spec', () async {
      final manifest = File(p.join(tempDir.path, 'manifest.yaml'));
      manifest.writeAsStringSync('''
videos:
  - id: test
    source: Test.bik
    output: Test.mp4
''');
      final inputDir = Directory(p.join(tempDir.path, 'input'))..createSync();
      File(p.join(inputDir.path, 'Test.bik')).writeAsBytesSync(<int>[0, 1, 2]);
      final outputDir = p.join(tempDir.path, 'out');
      final pakPath = p.join(tempDir.path, 'VideoConverted.pak');
      final runner = _FakeRunner();
      final converter = IntroVideoConverter(runner: runner);
      final results = await converter.convert(
        ConversionConfig(
          manifestPath: manifest.path,
          inputDirectory: inputDir.path,
          outputDirectory: outputDir,
          pakOutputPath: pakPath,
          pakDirectory: 'languages/movies/english',
          ffmpegPath: 'ffmpeg',
          ffprobePath: 'ffprobe',
          crf: 20,
          preset: 'medium',
          audioBitrate: '128k',
        ),
      );
      expect(results.length, 1);
      expect(results.first.spec.output, 'Test.mp4');
      expect(File(p.join(outputDir, 'Test.mp4')).existsSync(), isTrue);
      expect(File(pakPath).existsSync(), isTrue);
      final archive = ZipDecoder().decodeBytes(File(pakPath).readAsBytesSync());
      expect(archive.files.length, 1);
      expect(archive.files.first.name, 'languages/movies/english/Test.mp4');
      expect(runner.invocations.where((i) => i.executable == 'ffprobe').length, 1);
      expect(runner.invocations.where((i) => i.executable == 'ffmpeg').length, 1);
    });
  });
}

class _Invocation {
  _Invocation(this.executable, this.arguments);
  final String executable;
  final List<String> arguments;
}

class _FakeRunner implements ProcessRunner {
  final List<_Invocation> invocations = [];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    invocations.add(_Invocation(executable, List<String>.from(arguments)));
    if (executable == 'ffprobe') {
      final json = jsonEncode({
        'streams': [
          {
            'codec_type': 'video',
            'width': 640,
            'height': 480,
            'avg_frame_rate': '30/1',
            'duration': '5.0',
          }
        ]
      });
      return ProcessResult(0, 0, json, '');
    }
    if (executable == 'ffmpeg') {
      final target = arguments.last;
      File(target).writeAsBytesSync(List<int>.filled(8, 1));
      return ProcessResult(0, 0, '', '');
    }
    return ProcessResult(0, 1, '', 'unsupported command');
  }
}

