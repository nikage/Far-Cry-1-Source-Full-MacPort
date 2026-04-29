import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/metal_converter.dart';

void main() {
  test('maps manifest entries to multiple key variants', () {
    final Directory tempDir = Directory.systemTemp.createTempSync('entry_map_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final File manifest = File(p.join(tempDir.path, 'generated_manifest.json'));    
    manifest.writeAsStringSync(jsonEncode(<Map<String, dynamic>>[
      {
        'source': 'Shaders/HWScripts/Declarations/CGVShaders/Foo.crycg.json',
        'stage': 'vertex',
        'entryPoint': 'generated_foo_vertex',
      },
      {
        'source': 'Shaders/HWScripts/Declarations/CGPShaders/Bar.crycg.json',
        'stage': 'fragment',
        'fragment': 'generated_bar_fragment',
      },
    ]));

    final Map<String, Map<String, String>> map = loadEntryMapForTest(
      manifest,
      '6',
      inputDirPrefix:
          p.join(tempDir.path, 'tools', 'shader_port', 'output', 'hlsl', 'Shaders', 'HWScripts', 'Declarations'),
    );

    expect(map, isNotEmpty);
    expect(map['CGVShaders/Foo.crycg.hlsl']?['entry'], 'generated_foo_vertex');
    expect(map['CGVShaders/Foo.crycg.hlsl']?['profile'], 'vs_6_0');
    expect(map['Foo.crycg.hlsl']?['entry'], 'generated_foo_vertex');
    expect(map['CGPShaders/Bar.crycg.hlsl']?['entry'], 'generated_bar_fragment');
    expect(map['Bar.crycg.hlsl']?['profile'], 'ps_6_0');
  });

  test('skips invalid manifest rows', () {
    final Directory tempDir = Directory.systemTemp.createTempSync('entry_map_test_invalid_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final File manifest = File(p.join(tempDir.path, 'generated_manifest.json'));
    manifest.writeAsStringSync(jsonEncode(<Map<String, dynamic>>[
      {
        'source': 'Shaders/HWScripts/Declarations/CGVShaders/Valid.crycg.json',
        'stage': 'vertex',
        'entryPoint': 'generated_valid_vertex',
      },
      {
        'source': 'Shaders/HWScripts/Declarations/CGVShaders/Missing.crycg.json',
        'stage': 'vertex',
      },
    ]));

    final Map<String, Map<String, String>> map = loadEntryMapForTest(
      manifest,
      '6',
    );

    expect(map.containsKey('CGVShaders/Valid.crycg.hlsl'), isTrue);
    expect(map.containsKey('CGVShaders/Missing.crycg.hlsl'), isFalse);
  });
}








