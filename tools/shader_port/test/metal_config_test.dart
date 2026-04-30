import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('metal_toolchain.json', () {
    late Map<String, dynamic> data;

    setUpAll(() {
      final File cfg = File(
        '${Directory.current.path}${Platform.pathSeparator}'
        'config${Platform.pathSeparator}metal_toolchain.json',
      );
      expect(cfg.existsSync(), isTrue,
          reason: 'config/metal_toolchain.json must exist');
      data = jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
    });

    test('metalStd field is present', () {
      expect(data.containsKey('metalStd'), isTrue);
    });

    test('metalStd is a non-empty string starting with "metal"', () {
      final Object? value = data['metalStd'];
      expect(value, isA<String>());
      expect(value as String, isNotEmpty);
      expect(value, startsWith('metal'));
    });
  });
}
