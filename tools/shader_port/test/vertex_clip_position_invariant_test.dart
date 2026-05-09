import 'package:shader_port/metal_generator.dart';
import 'package:test/test.dart';

void main() {
  group('mergeVertexClipPositionInvariant', () {
    test('vertex stage inserts HPosition 4 when map empty', () {
      final m = <String, int>{};
      mergeVertexClipPositionInvariant(m, 'vertex');
      expect(m, equals(<String, int>{'HPosition': 4}));
    });

    test('vertex stage widens HPosition below 4 to 4', () {
      final m = <String, int>{'HPosition': 2, 'Tex0': 2};
      mergeVertexClipPositionInvariant(m, 'vertex');
      expect(m['HPosition'], 4);
      expect(m['Tex0'], 2);
    });

    test('fragment stage leaves map unchanged', () {
      final m = <String, int>{'Color': 4};
      mergeVertexClipPositionInvariant(m, 'fragment');
      expect(m, equals(<String, int>{'Color': 4}));
    });
  });
}
