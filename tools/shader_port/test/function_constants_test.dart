import 'package:test/test.dart';

// Function constant indices — must match kFC_* in MetalShaderLoader.mm
const int kFC_FogEnabled     = 0;
const int kFC_HdrEnabled     = 1;
const int kFC_GlossAlpha     = 2;
const int kFC_EnvLight       = 3;
const int kFC_AttenEnabled   = 4;
const int kFC_ProjLight      = 5;
const int kFC_PlantsBending  = 6;
const int kFC_AlphaGlow      = 7;
const int kFC_MultipleLights = 8;
const int kFC_HighPrecision  = 9;

// Dart mirror of BuildFunctionConstants from MetalShaderLoader.mm.
// Returns a map of constantIndex → bool value.
Map<int, bool> buildFunctionConstants(String lowerName, List<String> directives) {
  bool fogEnabled     = false;
  bool hdrEnabled     = false;
  bool glossAlpha     = false;
  bool envLight       = false;
  bool attenEnabled   = false;
  bool projLight      = false;
  bool plantsBending  = false;
  bool alphaGlow      = false;
  bool multipleLights = false;
  bool highPrecision  = false;

  envLight       = lowerName.contains('envlight');
  alphaGlow      = lowerName.contains('alphaglow');
  glossAlpha     = lowerName.contains('glossalpha');
  multipleLights = lowerName.contains('multiplelight');
  attenEnabled   = lowerName.contains('atten');
  projLight      = lowerName.contains('proj');
  plantsBending  = lowerName.contains('plants') || lowerName.contains('vegetation');

  for (final String d in directives) {
    final String lower = d.toLowerCase();
    if (lower == 'hdr' || lower.contains('hdr')) hdrEnabled = true;
    if (lower.contains('fog'))                   fogEnabled = true;
    if (lower.contains('highprecision') || lower.contains('high_precision'))
      highPrecision = true;
  }

  return <int, bool>{
    kFC_FogEnabled:     fogEnabled,
    kFC_HdrEnabled:     hdrEnabled,
    kFC_GlossAlpha:     glossAlpha,
    kFC_EnvLight:       envLight,
    kFC_AttenEnabled:   attenEnabled,
    kFC_ProjLight:      projLight,
    kFC_PlantsBending:  plantsBending,
    kFC_AlphaGlow:      alphaGlow,
    kFC_MultipleLights: multipleLights,
    kFC_HighPrecision:  highPrecision,
  };
}

void main() {
  group('BuildFunctionConstants (Dart mirror)', () {
    test('all-false for plain ambient shader', () {
      final Map<int, bool> cv =
          buildFunctionConstants('cgrcambient_ps20', <String>[]);
      for (final bool v in cv.values) {
        expect(v, isFalse);
      }
    });

    test('env_light is true for envlight shader', () {
      final Map<int, bool> cv = buildFunctionConstants(
          'cgrcambient_envlight', <String>[]);
      expect(cv[kFC_EnvLight], isTrue);
      expect(cv[kFC_FogEnabled], isFalse);
    });

    test('alpha_glow is true for alphaglow shader', () {
      final Map<int, bool> cv = buildFunctionConstants(
          'cgrcambient_alphaglow_envcmspec_ps20', <String>[]);
      expect(cv[kFC_AlphaGlow], isTrue);
      expect(cv[kFC_EnvLight], isFalse);
    });

    test('both envlight and alphaglow set simultaneously', () {
      final Map<int, bool> cv = buildFunctionConstants(
          'cgrcambient_alphaglow_envlight', <String>[]);
      expect(cv[kFC_EnvLight], isTrue);
      expect(cv[kFC_AlphaGlow], isTrue);
    });

    test('gloss_alpha set for glossalpha shader', () {
      final Map<int, bool> cv = buildFunctionConstants(
          'cgrcbump_diffspec_singlelight_atten_glossalpha_envlight',
          <String>[]);
      expect(cv[kFC_GlossAlpha], isTrue);
      expect(cv[kFC_AttenEnabled], isTrue);
      expect(cv[kFC_EnvLight], isTrue);
    });

    test('multiple_lights set for multiplelight shader', () {
      final Map<int, bool> cv = buildFunctionConstants(
          'cgrcbump_diff_multiplelight', <String>[]);
      expect(cv[kFC_MultipleLights], isTrue);
    });

    test('plants_bending set for plants shader', () {
      final Map<int, bool> cv =
          buildFunctionConstants('cgrcplants_bending', <String>[]);
      expect(cv[kFC_PlantsBending], isTrue);
    });

    test('plants_bending set for vegetation shader', () {
      final Map<int, bool> cv =
          buildFunctionConstants('cgrcvegetation_base', <String>[]);
      expect(cv[kFC_PlantsBending], isTrue);
    });

    test('proj_light set for proj shader', () {
      final Map<int, bool> cv =
          buildFunctionConstants('cgrcbump_diff_projsinglelight', <String>[]);
      expect(cv[kFC_ProjLight], isTrue);
    });

    test('hdr_enabled from directive "HDR"', () {
      final Map<int, bool> cv =
          buildFunctionConstants('cgrc_hdr_base_ps20', <String>['HDR']);
      expect(cv[kFC_HdrEnabled], isTrue);
    });

    test('fog_enabled from directive "Fog"', () {
      final Map<int, bool> cv = buildFunctionConstants(
          'cgrcambient_ps20', <String>['Fog']);
      expect(cv[kFC_FogEnabled], isTrue);
    });

    test('high_precision from directive', () {
      final Map<int, bool> cv = buildFunctionConstants(
          'cgrcwater_base', <String>['HighPrecision']);
      expect(cv[kFC_HighPrecision], isTrue);
    });

    test('directive matching is case-insensitive', () {
      final Map<int, bool> cv = buildFunctionConstants(
          'cgrcbase', <String>['FOG', 'hDR']);
      expect(cv[kFC_FogEnabled], isTrue);
      expect(cv[kFC_HdrEnabled], isTrue);
    });

    test('all constants are present in output', () {
      final Map<int, bool> cv =
          buildFunctionConstants('cgrcbase', <String>[]);
      expect(cv.length, 10);
      for (int i = 0; i < 10; i++) {
        expect(cv.containsKey(i), isTrue,
            reason: 'Missing constant at index $i');
      }
    });

    test('atten_enabled via manifest: atten substring in name', () {
      final Map<int, bool> cv = buildFunctionConstants(
          'cgrcbump_diff_projsinglelight_atten_envlight_ps20', <String>[]);
      expect(cv[kFC_AttenEnabled], isTrue);
      expect(cv[kFC_ProjLight], isTrue);
      expect(cv[kFC_EnvLight], isTrue);
    });
  });
}
