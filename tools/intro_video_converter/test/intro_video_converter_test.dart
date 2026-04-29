import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:intro_video_converter/intro_video_converter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
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

