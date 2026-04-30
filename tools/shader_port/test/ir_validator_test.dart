import 'package:shader_port/ir_validator.dart';
import 'package:shader_port/parser.dart';
import 'package:test/test.dart';

Map<String, dynamic> _ir({
  String name = 'TestShader',
  List<dynamic> blocks = const [],
  List<dynamic> coreScriptExpressions = const [],
  List<String> positionScripts = const [],
  List<dynamic> positionScriptBlocks = const [],
  List<String> maskReferences = const [],
}) {
  return <String, dynamic>{
    'name': name,
    'blocks': blocks,
    'coreScriptExpressions': coreScriptExpressions,
    'positionScripts': positionScripts,
    'positionScriptBlocks': positionScriptBlocks,
    'maskReferences': maskReferences,
  };
}

Map<String, dynamic> _block(String name, String content) =>
    <String, dynamic>{'name': name, 'content': content};

Map<String, dynamic> _expr(String raw, {bool active = true}) =>
    <String, dynamic>{'type': 'assignment', 'raw': raw, 'active': active};

ParseResult _parseResult({
  String name = 'TestShader',
  String relativePath = 'CGPShaders/TestShader.crycg',
  List<Block> blocks = const [],
  List<Map<String, dynamic>> coreScriptExpressions = const [],
  List<String> positionScripts = const [],
  List<Map<String, String>> positionScriptBlocks = const [],
}) {
  return ParseResult(
    name,
    'crycg',
    relativePath,
    const [],
    blocks,
    const [],
    const [],
    coreScriptExpressions,
    const [],
    const [],
    const [],
    const [],
    const [],
    const [],
    positionScripts,
    positionScriptBlocks,
    const {},
    null,
  );
}

void main() {
  final IrValidator validator = IrValidator();

  group('IrValidator.validateIr — IR-1 (fully empty shader)', () {
    test('fails when no CoreScript, no positionScripts, no positionScriptBlocks', () {
      final IrValidationResult result = validator.validateIr(
        _ir(name: 'EmptyShader'),
        'CGPShaders/EmptyShader.crycg',
      );
      expect(result.passed, isFalse);
      expect(result.errors, hasLength(1));
      expect(result.errors.first.rule, 'IR-1');
    });

    test('passes when positionScripts is non-empty (position-only vertex shader)', () {
      final IrValidationResult result = validator.validateIr(
        _ir(positionScripts: ['PosCommon']),
        'CGVShaders/CGVProgSimple.crycg',
      );
      expect(result.passed, isTrue);
    });

    test('passes when positionScriptBlocks is non-empty', () {
      final IrValidationResult result = validator.validateIr(
        _ir(positionScriptBlocks: [<String, dynamic>{'name': 'PosBeam', 'content': ''}]),
        'CGVShaders/Beam.crycg',
      );
      expect(result.passed, isTrue);
    });

    test('passes when CoreScript block is present', () {
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [_block('CoreScript', 'OUT.Color = float4(1,0,0,1);')],
          coreScriptExpressions: [_expr('OUT.Color = float4(1,0,0,1);')],
        ),
        'CGPShaders/Valid.crycg',
      );
      expect(result.passed, isTrue);
    });

    test('passes when empty shader is masked to non-Metal backends only (D3D, OPENGL)', () {
      final IrValidationResult result = validator.validateIr(
        _ir(name: 'CGRCBump_ReflLight', maskReferences: ['D3D', 'OPENGL']),
        'CGPShaders/CGRCBump_ReflLight.crycg',
      );
      expect(result.passed, isTrue,
          reason: 'D3D/OPENGL-only shaders are intentionally empty for Metal');
    });

    test('fails when empty shader has no maskReferences (platform-agnostic missing body)', () {
      final IrValidationResult result = validator.validateIr(
        _ir(name: 'PlatformAgnosticEmpty'),
        'CGPShaders/PlatformAgnosticEmpty.crycg',
      );
      expect(result.passed, isFalse);
      expect(result.errors.first.rule, 'IR-1');
    });

    test('fails when empty shader maskReferences contains METAL', () {
      final IrValidationResult result = validator.validateIr(
        _ir(name: 'MetalEmptyShader', maskReferences: ['METAL', 'D3D']),
        'CGPShaders/MetalEmptyShader.crycg',
      );
      expect(result.passed, isFalse,
          reason: 'METAL in maskReferences means Metal body is expected');
    });
  });

  group('IrValidator.validateIr — IR-2 (dead CoreScript)', () {
    test('fails when CoreScript block exists but all expressions are inactive', () {
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [_block('CoreScript', '#ifdef NEVER\nOUT.Color = float4(1,0,0,1);\n#endif')],
          coreScriptExpressions: [_expr('OUT.Color = float4(1,0,0,1);', active: false)],
        ),
        'CGPShaders/DeadCore.crycg',
      );
      expect(result.passed, isFalse);
      expect(result.errors.first.rule, 'IR-2');
    });

    test('passes when at least one active expression exists', () {
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [_block('CoreScript', 'OUT.Color = float4(1,0,0,1);')],
          coreScriptExpressions: [
            _expr('OUT.Color = float4(0,0,0,0);', active: false),
            _expr('OUT.Color = float4(1,0,0,1);', active: true),
          ],
        ),
        'CGPShaders/PartialActive.crycg',
      );
      expect(result.passed, isTrue);
    });

    test('passes when expression has null active field (treated as active)', () {
      final Map<String, dynamic> exprWithNullActive = <String, dynamic>{
        'type': 'assignment',
        'raw': 'OUT.Color = float4(1,0,0,1);',
      };
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [_block('CoreScript', 'OUT.Color = float4(1,0,0,1);')],
          coreScriptExpressions: [exprWithNullActive],
        ),
        'CGPShaders/NullActive.crycg',
      );
      expect(result.passed, isTrue);
    });

    test('does not fire IR-2 when there is no CoreScript block', () {
      final IrValidationResult result = validator.validateIr(
        _ir(positionScripts: ['PosCommon']),
        'CGVShaders/NoCoreScript.crycg',
      );
      final List<String> rules = result.errors.map((e) => e.rule).toList();
      expect(rules, isNot(contains('IR-2')));
    });
  });

  group('IrValidator.validateIr — IR-3 (duplicate uniform)', () {
    test('fails on duplicate uniform name in MainInput', () {
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [
            _block('MainInput', 'uniform float4 Color;\nuniform float4 Color;'),
            _block('CoreScript', 'OUT.Color = Color;'),
          ],
          coreScriptExpressions: [_expr('OUT.Color = Color;')],
        ),
        'CGPShaders/DupUniform.crycg',
      );
      expect(result.passed, isFalse);
      final List<IrValidationError> ir3 =
          result.errors.where((e) => e.rule == 'IR-3').toList();
      expect(ir3, hasLength(1));
      expect(ir3.first.message, contains('Color'));
    });

    test('passes with distinct uniform names', () {
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [
            _block('MainInput', 'uniform float4 Diffuse;\nuniform float4 Specular;'),
            _block('CoreScript', 'OUT.Color = Diffuse;'),
          ],
          coreScriptExpressions: [_expr('OUT.Color = Diffuse;')],
        ),
        'CGPShaders/DistinctUniforms.crycg',
      );
      expect(result.passed, isTrue);
    });

    test('passes when same uniform name appears in mutually-exclusive #if/#elif branches', () {
      const String content = '''
#if %ENVCMAMB
uniform float4x4 TexMatrix,
#elif %TEMP_ENVLIGHT
uniform float4 EnvColors[6],
uniform float4x4 TexMatrix,
#elif %ENVCMSPEC
uniform float4x4 ModelMatrix,
#endif''';
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [
            _block('MainInput', content),
            _block('CoreScript', 'OUT.envTC = mul(tRM, TexMatrix);'),
          ],
          coreScriptExpressions: [_expr('OUT.envTC = mul(tRM, TexMatrix);')],
        ),
        'CGVShaders/CGVProgAmbientTempl.crycg',
      );
      final List<IrValidationError> ir3 =
          result.errors.where((e) => e.rule == 'IR-3').toList();
      expect(ir3, isEmpty,
          reason: 'TexMatrix in different #if/#elif branches must not be flagged as a duplicate');
    });

    test('fails when same uniform name appears twice in the same branch', () {
      const String content = '''
#if %ENVCMAMB
uniform float4x4 TexMatrix,
uniform float4x4 TexMatrix,
#endif''';
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [
            _block('MainInput', content),
            _block('CoreScript', 'OUT.envTC = mul(tRM, TexMatrix);'),
          ],
          coreScriptExpressions: [_expr('OUT.envTC = mul(tRM, TexMatrix);')],
        ),
        'CGVShaders/DupSameBranch.crycg',
      );
      final List<IrValidationError> ir3 =
          result.errors.where((e) => e.rule == 'IR-3').toList();
      expect(ir3, hasLength(1), reason: 'Two TexMatrix in the same branch IS a real duplicate');
    });

    test('passes when same texture name appears in independent sibling #ifdef blocks', () {
      const String content = '''
#ifdef OPENGL
uniform samplerRECT refMap : texunit2,
#endif
#ifdef D3D
uniform sampler2D refMap : texunit2,
#endif''';
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [
            _block('MainInput', content),
            _block('CoreScript', 'OUT.Color = tex2D(refMap, IN.Tex0.xy);'),
          ],
          coreScriptExpressions: [_expr('OUT.Color = tex2D(refMap, IN.Tex0.xy);')],
        ),
        'CGPShaders/CGRCRefractiveOverlay.crycg',
      );
      final List<IrValidationError> ir4 =
          result.errors.where((e) => e.rule == 'IR-4').toList();
      expect(ir4, isEmpty,
          reason: 'refMap in sibling #ifdef/#ifdef blocks must not be flagged as a duplicate');
    });
  });

  group('IrValidator.validateIr — IR-4 (duplicate texture)', () {
    test('fails on duplicate texture name in MainInput', () {
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [
            _block('MainInput',
                'uniform sampler2D baseMap;\nuniform sampler2D baseMap;'),
            _block('CoreScript', 'OUT.Color = tex2D(baseMap, IN.Tex0.xy);'),
          ],
          coreScriptExpressions: [
            _expr('OUT.Color = tex2D(baseMap, IN.Tex0.xy);'),
          ],
        ),
        'CGPShaders/DupTexture.crycg',
      );
      expect(result.passed, isFalse);
      final List<IrValidationError> ir4 =
          result.errors.where((e) => e.rule == 'IR-4').toList();
      expect(ir4, hasLength(1));
      expect(ir4.first.message, contains('baseMap'));
    });

    test('passes with distinct texture names', () {
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [
            _block('MainInput',
                'uniform sampler2D baseMap;\nuniform sampler2D bumpMap;'),
            _block('CoreScript', 'OUT.Color = tex2D(baseMap, IN.Tex0.xy);'),
          ],
          coreScriptExpressions: [
            _expr('OUT.Color = tex2D(baseMap, IN.Tex0.xy);'),
          ],
        ),
        'CGPShaders/DistinctTextures.crycg',
      );
      expect(result.passed, isTrue);
    });
  });

  group('IrValidator.validateIr — IR-5 (unrecognized uniform type)', () {
    test('fails on unknown type in MainInput', () {
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [
            _block('MainInput', 'uniform mystery3 WeirdParam;'),
            _block('CoreScript', 'OUT.Color = float4(1,0,0,1);'),
          ],
          coreScriptExpressions: [_expr('OUT.Color = float4(1,0,0,1);')],
        ),
        'CGPShaders/UnknownType.crycg',
      );
      expect(result.passed, isFalse);
      final List<IrValidationError> ir5 =
          result.errors.where((e) => e.rule == 'IR-5').toList();
      expect(ir5, hasLength(1));
      expect(ir5.first.message, contains('mystery3'));
    });

    test('passes for all allowed types', () {
      const List<String> allowedTypes = <String>[
        'float', 'float2', 'float3', 'float4',
        'float2x4', 'float3x3', 'float3x4', 'float4x4',
        'half4', 'FLOAT4',
      ];
      for (final String type in allowedTypes) {
        final IrValidationResult result = validator.validateIr(
          _ir(
            blocks: [
              _block('MainInput', 'uniform $type Param;'),
              _block('CoreScript', 'OUT.Color = float4(1,0,0,1);'),
            ],
            coreScriptExpressions: [_expr('OUT.Color = float4(1,0,0,1);')],
          ),
          'CGPShaders/Type_$type.crycg',
        );
        expect(result.passed, isTrue, reason: 'type "$type" should be allowed');
      }
    });

    test('samplers are not checked against uniform type allowlist', () {
      final IrValidationResult result = validator.validateIr(
        _ir(
          blocks: [
            _block('MainInput', 'uniform samplerCUBE envMap;'),
            _block('CoreScript', 'OUT.Color = float4(1,0,0,1);'),
          ],
          coreScriptExpressions: [_expr('OUT.Color = float4(1,0,0,1);')],
        ),
        'CGPShaders/SamplerCube.crycg',
      );
      expect(result.passed, isTrue);
    });
  });

  group('IrValidator.validateParseResult — mirrors validateIr rules', () {
    test('IR-1: fails on fully empty ParseResult', () {
      final ParseResult result = _parseResult();
      final IrValidationResult validation =
          validator.validateParseResult(result);
      expect(validation.passed, isFalse);
      expect(validation.errors.first.rule, 'IR-1');
    });

    test('IR-1: passes for position-only shader with positionScripts', () {
      final ParseResult result = _parseResult(
        positionScripts: ['PosCommon'],
        blocks: [
          Block('MainInput', 'VIEWPROJ_MATRIX'),
          Block('VertAttributes', 'POSITION_3'),
        ],
      );
      final IrValidationResult validation =
          validator.validateParseResult(result);
      expect(validation.passed, isTrue);
    });

    test('IR-2: fails when CoreScript block present but expressions all inactive', () {
      final ParseResult result = _parseResult(
        blocks: [Block('CoreScript', '#ifdef NEVER\n...\n#endif')],
        coreScriptExpressions: [
          <String, dynamic>{'raw': 'OUT.Color = float4(0,0,0,0);', 'active': false},
        ],
      );
      final IrValidationResult validation =
          validator.validateParseResult(result);
      expect(validation.passed, isFalse);
      expect(validation.errors.first.rule, 'IR-2');
    });

    test('IR-3: fails on duplicate uniform via ParseResult', () {
      final ParseResult result = _parseResult(
        blocks: [
          Block('MainInput', 'uniform float4 Color;\nuniform float4 Color;'),
          Block('CoreScript', 'OUT.Color = Color;'),
        ],
        coreScriptExpressions: [
          <String, dynamic>{'raw': 'OUT.Color = Color;', 'active': true},
        ],
      );
      final IrValidationResult validation =
          validator.validateParseResult(result);
      expect(validation.passed, isFalse);
      expect(validation.errors.any((e) => e.rule == 'IR-3'), isTrue);
    });

    test('IR-5: fails on unknown type via ParseResult', () {
      final ParseResult result = _parseResult(
        blocks: [
          Block('MainInput', 'uniform unknownType Param;'),
          Block('CoreScript', 'OUT.Color = float4(1,0,0,1);'),
        ],
        coreScriptExpressions: [
          <String, dynamic>{'raw': 'OUT.Color = float4(1,0,0,1);', 'active': true},
        ],
      );
      final IrValidationResult validation =
          validator.validateParseResult(result);
      expect(validation.passed, isFalse);
      expect(validation.errors.any((e) => e.rule == 'IR-5'), isTrue);
    });
  });

  group('IrValidationError.toString', () {
    test('formats as [rule] shader: message', () {
      const IrValidationError error = IrValidationError(
        'IR-1', 'MyShader', 'some problem',
      );
      expect(error.toString(), '[IR-1] MyShader: some problem');
    });
  });

  group('IrValidationResult', () {
    test('passed is true when errors is empty', () {
      const IrValidationResult result = IrValidationResult(
        shader: 'X',
        errors: [],
      );
      expect(result.passed, isTrue);
    });

    test('passed is false when errors is non-empty', () {
      final IrValidationResult result = IrValidationResult(
        shader: 'X',
        errors: [const IrValidationError('IR-1', 'X', 'msg')],
      );
      expect(result.passed, isFalse);
    });
  });
}
