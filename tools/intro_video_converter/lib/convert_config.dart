import 'package:intro_video_converter/intro_video_converter.dart';
import 'package:path/path.dart' as p;

ConversionConfig buildConfig(
  String projectRoot, {
  int crf = 18,
  String preset = 'slow',
  String audioBitrate = '192k',
}) {
  return ConversionConfig(
    manifestPath: p.join(
      projectRoot,
      'tools',
      'intro_video_converter',
      'intro_videos.yaml',
    ),
    inputDirectory: p.join(
      projectRoot,
      'external_assets',
      'Languages',
      'Movies',
    ),
    outputDirectory: p.join(projectRoot, 'build', 'converted_videos'),
    pakOutputPath: p.join(
      projectRoot,
      'build',
      'converted_videos',
      'VideoConverted.pak',
    ),
    pakDirectory: 'languages/movies/english',
    crf: crf,
    preset: preset,
    audioBitrate: audioBitrate,
  );
}
