part of '../metal_generator.dart';

class ComputeLightVectorsTransformer implements LineTransformer {
  @override
  String transform(String line) {
    if (!line.contains('ComputeLightVectors')) {
      return line;
    }
    return [
      'float3 _lightVectorTemp = uniforms.LightPos.xyz - vPos.xyz;',
      'float LightDistance = length(_lightVectorTemp);',
      'LightDirection = _lightVectorTemp / LightDistance;',
      'ViewDirection = normalize(uniforms.CameraPos.xyz - vPos.xyz);',
      'HalfVector = normalize(ViewDirection + LightDirection);'
    ].join('\n');
  }
}
