import 'dart:io';

import 'package:test/test.dart';

import '../bin/validate_migration.dart';

void main() {
  group('buildStages', () {
    test('default produces 4 stages including validate-ir and generate', () {
      final BuildStagesResult r = buildStages(rootArg: '.');
      expect(r.stages.length, 4);
      expect(r.stages.map((s) => s.name),
          ['validate-ir', 'generate', 'compile-check', 'validate-pairs']);
    });

    test('skipGenerate omits generate stage, keeps validate-ir', () {
      final BuildStagesResult r = buildStages(rootArg: '.', skipGenerate: true);
      expect(r.stages.length, 3);
      expect(r.stages.map((s) => s.name),
          ['validate-ir', 'compile-check', 'validate-pairs']);
    });

    test('skipValidateIr omits validate-ir stage, keeps generate', () {
      final BuildStagesResult r =
          buildStages(rootArg: '.', skipValidateIr: true);
      expect(r.stages.length, 3);
      expect(r.stages.map((s) => s.name),
          ['generate', 'compile-check', 'validate-pairs']);
    });

    test('skipValidateIr and skipGenerate produce 2 stages', () {
      final BuildStagesResult r =
          buildStages(rootArg: '.', skipValidateIr: true, skipGenerate: true);
      expect(r.stages.length, 2);
      expect(r.stages.map((s) => s.name),
          ['compile-check', 'validate-pairs']);
    });

    test('all stage executables are dart', () {
      final BuildStagesResult r = buildStages(rootArg: '.');
      for (final Stage s in r.stages) {
        expect(s.executable, 'dart');
      }
    });

    test('generate stage args include root arg', () {
      final BuildStagesResult r = buildStages(rootArg: '/tmp/myroot');
      final Stage gen = r.stages.firstWhere((s) => s.name == 'generate');
      expect(gen.args, contains('/tmp/myroot'));
    });

    test('overridesPath is forwarded to generate stage', () {
      final BuildStagesResult r = buildStages(
        rootArg: '.',
        overridesPath: '/path/to/overrides.json',
      );
      final Stage gen = r.stages.firstWhere((s) => s.name == 'generate');
      expect(gen.args, containsAll(['--overrides', '/path/to/overrides.json']));
    });

    test('metalStd is forwarded to compile-check stage', () {
      final BuildStagesResult r = buildStages(rootArg: '.', metalStd: 'metal2.4');
      final Stage check = r.stages.firstWhere((s) => s.name == 'compile-check');
      expect(check.args, containsAll(['--metal-std', 'metal2.4']));
    });

    test('verbose adds --verbose to compile-check stage', () {
      final BuildStagesResult r = buildStages(rootArg: '.', verbose: true);
      final Stage check = r.stages.firstWhere((s) => s.name == 'compile-check');
      expect(check.args, contains('--verbose'));
    });

    test('verbose=false does not add --verbose to compile-check stage', () {
      final BuildStagesResult r = buildStages(rootArg: '.', verbose: false);
      final Stage check = r.stages.firstWhere((s) => s.name == 'compile-check');
      expect(check.args, isNot(contains('--verbose')));
    });

    test('strict adds --strict to validate-pairs stage', () {
      final BuildStagesResult r = buildStages(rootArg: '.', strict: true);
      final Stage validate = r.stages.firstWhere((s) => s.name == 'validate-pairs');
      expect(validate.args, contains('--strict'));
    });

    test('script paths are under rootArg resolved directory', () {
      final BuildStagesResult r = buildStages(rootArg: '.');
      final String sep = Platform.pathSeparator;
      expect(r.validateIrScript, contains('validate_ir.dart'));
      expect(r.generatorScript, contains('metal_generator.dart'));
      expect(r.compileCheckScript, contains('compile_check.dart'));
      expect(r.validatePairsScript, contains('validate_pairs.dart'));
      expect(r.generatorScript, contains('tools${sep}shader_port'));
    });

    test('validate-pairs stage args include manifest path', () {
      final BuildStagesResult r = buildStages(rootArg: '.');
      final Stage validate = r.stages.firstWhere((s) => s.name == 'validate-pairs');
      expect(validate.args.any((a) => a.contains('generated_manifest.json')), isTrue);
    });

    test('returns skipGenerate flag as provided', () {
      expect(buildStages(rootArg: '.', skipGenerate: true).skipGenerate, isTrue);
      expect(buildStages(rootArg: '.', skipGenerate: false).skipGenerate, isFalse);
    });

    test('returns skipValidateIr flag as provided', () {
      expect(
          buildStages(rootArg: '.', skipValidateIr: true).skipValidateIr, isTrue);
      expect(
          buildStages(rootArg: '.', skipValidateIr: false).skipValidateIr, isFalse);
    });

    test('overridesPath is null when not provided', () {
      expect(buildStages(rootArg: '.').overridesPath, isNull);
    });

    test('overridesPath is not in generate args when absent', () {
      final BuildStagesResult r = buildStages(rootArg: '.');
      final Stage gen = r.stages.firstWhere((s) => s.name == 'generate');
      expect(gen.args, isNot(contains('--overrides')));
    });
  });
}
