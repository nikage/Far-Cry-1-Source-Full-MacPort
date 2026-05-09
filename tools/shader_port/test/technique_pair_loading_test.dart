import 'dart:io';

import 'package:shader_port/metal_generator.dart';
import 'package:test/test.dart';

void main() {
  group('loadTechniqueFragmentToVertexShaderMap', () {
    test('reads FragmentProgram to CGVProgram from Technique blocks', () {
      final Directory tmp =
          Directory.systemTemp.createTempSync('technique_pair_test_');
      try {
        final String sep = Platform.pathSeparator;
        final Directory assets = Directory(
          '${tmp.path}${sep}Assets${sep}Shaders${sep}Source',
        );
        assets.createSync(recursive: true);
        File('${assets.path}${sep}Mini.crycg').writeAsStringSync(r'''
Technique T1 {
  Pass P {
    CGVProgram = "CGVProgScreen"
    FragmentProgram = "CGRCFoo"
  }
}
''');
        final String root = tmp.path.endsWith(sep) ? tmp.path : '${tmp.path}$sep';
        final Map<String, String> map =
            loadTechniqueFragmentToVertexShaderMap(root, sep);
        expect(map['cgrcfoo'], 'CGVProgScreen');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('returns empty map when shader source tree is absent', () {
      final Directory tmp =
          Directory.systemTemp.createTempSync('technique_pair_empty_');
      try {
        final String sep = Platform.pathSeparator;
        final String root =
            tmp.path.endsWith(sep) ? tmp.path : '${tmp.path}$sep';
        expect(loadTechniqueFragmentToVertexShaderMap(root, sep), isEmpty);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}
