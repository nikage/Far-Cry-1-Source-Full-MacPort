import 'package:shader_port/metal_generator.dart';
import 'package:test/test.dart';

Map<String, dynamic> _ir({
  String name = 'TestShader',
  List<dynamic> blocks = const [],
  List<dynamic> coreScriptExpressions = const [],
  List<dynamic> positionScripts = const [],
  List<dynamic> positionScriptBlocks = const [],
  List<dynamic>? vertexAttributes,
  List<dynamic>? vertexAttributeMetadata,
  Map<String, dynamic>? compilerMetadata,
}) {
  return <String, dynamic>{
    'name': name,
    'blocks': blocks,
    'coreScriptExpressions': coreScriptExpressions,
    'positionScripts': positionScripts,
    'positionScriptBlocks': positionScriptBlocks,
    if (vertexAttributes != null) 'vertexAttributes': vertexAttributes,
    if (vertexAttributeMetadata != null) 'vertexAttributeMetadata': vertexAttributeMetadata,
    if (compilerMetadata != null) 'compilerMetadata': compilerMetadata,
  };
}

Map<String, dynamic> _mainInput(String content) =>
    <String, dynamic>{'name': 'MainInput', 'content': content};

void main() {
  final ShaderIrParser parser = ShaderIrParser();

  group('ShaderIrParser — empty IR', () {
    test('produces empty uniforms, textures, and defaults to fragment stage', () {
      final ShaderIrParseResult result = parser.parse(<String, dynamic>{}, 'Shaders/empty.crycg');
      expect(result.data.uniforms, isEmpty);
      expect(result.data.textures, isEmpty);
      expect(result.data.stage, 'fragment');
    });

    test('name falls back to relative path when IR name is empty', () {
      final ShaderIrParseResult result =
          parser.parse(<String, dynamic>{'name': ''}, 'Shaders/fallback.crycg');
      expect(result.data.shaderName, 'Shaders/fallback.crycg');
    });
  });

  group('ShaderIrParser — MainInput block parsing', () {
    test('parses scalar uniform from MainInput', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('uniform float4 Color : COLOR;')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('Color'));
    });

    test('parses multiple uniforms preserving order', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('uniform float4 Diffuse;\nuniform float Opacity;')]),
        'Shaders/test.crycg',
      );
      final List<String> names = result.data.uniforms.map((UniformBinding u) => u.name).toList();
      expect(names.indexOf('Diffuse'), lessThan(names.indexOf('Opacity')));
    });

    test('parses sampler texture and assigns sequential slots', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [
          _mainInput('uniform sampler2D baseMap;\nuniform sampler2D lightMap;'),
        ]),
        'Shaders/test.crycg',
      );
      expect(result.data.textures, hasLength(2));
      expect(result.data.textures[0].name, 'baseMap');
      expect(result.data.textures[0].slot, 0);
      expect(result.data.textures[1].name, 'lightMap');
      expect(result.data.textures[1].slot, 1);
    });

    test('sampler does not appear in uniforms list', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('uniform sampler2D baseMap;')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), isNot(contains('baseMap')));
    });

    test('parses array uniform with arraySize', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('uniform float4 Bones[64];')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms, hasLength(1));
      expect(result.data.uniforms.first.name, 'Bones');
      expect(result.data.uniforms.first.arraySize, 64);
    });

    test('deduplicates uniform names across repeated declarations', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('uniform float4 Color;\nuniform float4 Color;')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.where((UniformBinding u) => u.name == 'Color'), hasLength(1));
    });
  });

  group('ShaderIrParser — macro uniform injection', () {
    test('VIEWPROJ_MATRIX in MainInput injects ModelViewProj', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('VIEWPROJ_MATRIX')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('ModelViewProj'));
      expect(
        result.data.uniforms.firstWhere((UniformBinding u) => u.name == 'ModelViewProj').type,
        'float4x4',
      );
    });

    test('PROJ_MATRIX in MainInput injects ProjMatrix', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('PROJ_MATRIX')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('ProjMatrix'));
    });

    test('CAMERA_POS in MainInput injects CameraPos', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('CAMERA_POS')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('CameraPos'));
    });

    test('ATTEN in MainInput injects AttenInfo', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('ATTEN')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('AttenInfo'));
    });

    test('BEND in MainInput injects Bend', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('BEND')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('Bend'));
    });

    test('TEX_MATRIX2x4 in MainInput injects TexMatrix', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('TEX_MATRIX2x4')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('TexMatrix'));
    });

    test('LIGHT_MATRIX in MainInput injects LightMatrix', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('LIGHT_MATRIX')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('LightMatrix'));
    });

    test('CLIPPLANE in MainInput injects ClipPlane', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('CLIPPLANE')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('ClipPlane'));
    });

    test('LIGHT_POS in MainInput injects LightPos via macro map', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('LIGHT_POS')]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('LightPos'));
    });

    test('macro uniform not duplicated when already declared explicitly', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [_mainInput('uniform float4x4 ModelViewProj;\nVIEWPROJ_MATRIX')]),
        'Shaders/test.crycg',
      );
      expect(
        result.data.uniforms.where((UniformBinding u) => u.name == 'ModelViewProj'),
        hasLength(1),
      );
    });
  });

  group('ShaderIrParser — identifier-based uniform injection', () {
    test('injects LightPos when referenced in coreScriptExpressions', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(coreScriptExpressions: [<String, dynamic>{'raw': 'OUT.Color = LightPos * 2.0;'}]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('LightPos'));
    });

    test('injects Fog when referenced in coreScriptExpressions', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(coreScriptExpressions: [<String, dynamic>{'raw': 'result *= Fog.x;'}]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('Fog'));
    });

    test('injects GlobalFogColor when referenced in coreScriptExpressions', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(coreScriptExpressions: [<String, dynamic>{'raw': 'color += GlobalFogColor;'}]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('GlobalFogColor'));
    });

    test('injects Layer2TexGen0 when referenced', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(coreScriptExpressions: [<String, dynamic>{'raw': 'uv = Layer2TexGen0.xy;'}]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('Layer2TexGen0'));
    });

    test('injects Layer2TexGen1 when referenced', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(coreScriptExpressions: [<String, dynamic>{'raw': 'uv = Layer2TexGen1.xy;'}]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('Layer2TexGen1'));
    });

    test('injects AlphaGlowTexGen0 when referenced', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(coreScriptExpressions: [<String, dynamic>{'raw': 'uv = AlphaGlowTexGen0.xy;'}]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('AlphaGlowTexGen0'));
    });

    test('injects AlphaGlowTexGen1 when referenced', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(coreScriptExpressions: [<String, dynamic>{'raw': 'uv = AlphaGlowTexGen1.xy;'}]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('AlphaGlowTexGen1'));
    });

    test('injects g_VSCONST_0_025_05_1 when referenced', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(coreScriptExpressions: [<String, dynamic>{'raw': 'x = g_VSCONST_0_025_05_1.z;'}]),
        'Shaders/test.crycg',
      );
      expect(
        result.data.uniforms.map((UniformBinding u) => u.name),
        contains('g_VSCONST_0_025_05_1'),
      );
    });

    test('does not inject identifier uniform if not referenced', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(coreScriptExpressions: [<String, dynamic>{'raw': 'OUT.Color = float4(1,0,0,1);'}]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), isNot(contains('Fog')));
    });

    test('searches blocks content as well as coreScriptExpressions', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(blocks: [<String, dynamic>{'name': 'SomeBlock', 'content': 'LightPos.xyz'}]),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('LightPos'));
    });
  });

  group('ShaderIrParser — stage inference', () {
    test('infers vertex stage from /CGVShaders/ in path', () {
      final ShaderIrParseResult result = parser.parse(
        <String, dynamic>{},
        'output/ir/CGVShaders/CGVProgSimple.crycg.json',
      );
      expect(result.data.stage, 'vertex');
    });

    test('infers vertex stage from cgv-prefixed shader name', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(name: 'CGVProgBeam'),
        'Shaders/CGVProgBeam.crycg',
      );
      expect(result.data.stage, 'vertex');
    });

    test('defaults to fragment stage for non-vertex paths', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(name: 'CGRCAmbient'),
        'Shaders/CGRCAmbient.crycg',
      );
      expect(result.data.stage, 'fragment');
    });
  });

  group('ShaderIrParser — positionScripts and positionScriptBlocks', () {
    test('injects GeomConstants when PosBeam in positionScripts', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(positionScripts: <String>['PosBeam']),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('GeomConstants'));
    });

    test('does not inject GeomConstants without PosBeam', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(positionScripts: <String>['PosStd']),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), isNot(contains('GeomConstants')));
    });

    test('round-trips positionScriptBlocks name and content', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(positionScriptBlocks: <Map<String, dynamic>>[
          <String, dynamic>{'name': 'PosStd', 'content': 'OUT.hPosition = mul(ModelViewProj, IN.pos);'},
        ]),
        'Shaders/test.crycg',
      );
      expect(result.data.positionScriptBlocks, hasLength(1));
      expect(result.data.positionScriptBlocks.first['name'], 'PosStd');
      expect(result.data.positionScriptBlocks.first['content'], contains('hPosition'));
    });
  });

  group('ShaderIrParser — reflection merging via compilerMetadata', () {
    test('merges uniform from compilerMetadata.uniforms', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(
          compilerMetadata: <String, dynamic>{
            'EntryPoint': 'main',
            'uniforms': <Map<String, dynamic>>[
              <String, dynamic>{'name': 'ReflUniform', 'type': 'float4', 'semantic': ''},
            ],
          },
        ),
        'Shaders/test.crycg',
      );
      expect(result.data.uniforms.map((UniformBinding u) => u.name), contains('ReflUniform'));
    });

    test('merges texture from compilerMetadata via Resources SRV', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(
          compilerMetadata: <String, dynamic>{
            'EntryPoint': 'main',
            'Resources': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'SRV', 'name': 'envMap', 'slot': 2},
            ],
          },
        ),
        'Shaders/test.crycg',
      );
      expect(result.data.textures.map((TextureBinding t) => t.name), contains('envMap'));
    });

    test('does not duplicate uniform already declared in MainInput', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(
          blocks: [_mainInput('uniform float4 ExistingUniform;')],
          compilerMetadata: <String, dynamic>{
            'uniforms': <Map<String, dynamic>>[
              <String, dynamic>{'name': 'ExistingUniform', 'type': 'float4', 'semantic': ''},
            ],
          },
        ),
        'Shaders/test.crycg',
      );
      expect(
        result.data.uniforms.where((UniformBinding u) => u.name == 'ExistingUniform'),
        hasLength(1),
      );
    });

    test('merges vertex inputs from compilerMetadata', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(
          vertexAttributes: <dynamic>[],
          vertexAttributeMetadata: <dynamic>[],
          compilerMetadata: <String, dynamic>{
            'vertex_inputs': <Map<String, dynamic>>[
              <String, dynamic>{'name': 'position0', 'components': 4},
            ],
          },
        ),
        'Shaders/test.crycg',
      );
      expect(result.data.vertexAttributes, contains('position0'));
    });
  });

  group('ShaderIrParser — normalizeName integration', () {
    test('normalizedName is lowercase and hyphens become underscores', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(name: 'CGVProg-Test-Shader'),
        'Shaders/test.crycg',
      );
      expect(result.data.normalizedName, isNot(contains('-')));
      expect(result.data.normalizedName, equals(result.data.normalizedName.toLowerCase()));
      expect(result.data.normalizedName, equals('cgvprog_test_shader'));
    });

    test('normalizedName collapses multiple non-alphanum to single underscore', () {
      final ShaderIrParseResult result = parser.parse(
        _ir(name: 'A--B'),
        'Shaders/test.crycg',
      );
      expect(result.data.normalizedName, 'a_b');
    });
  });
}
