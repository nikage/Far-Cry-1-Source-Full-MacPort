part of 'metal_generator.dart';

abstract class StageEmissionStrategy {
  const StageEmissionStrategy();

  void writeStageFunction(
    MetalFragmentBuilder builder,
    List<String> parameters,
    StringBuffer buffer,
  );
}

class VertexEmissionStrategy extends StageEmissionStrategy {
  const VertexEmissionStrategy();

  @override
  void writeStageFunction(
    MetalFragmentBuilder builder,
    List<String> parameters,
    StringBuffer buffer,
  ) {
    final String functionName =
        'generated_${builder.data.normalizedName}_vertex';
    buffer.writeln(
      'vertex ${builder._outputStructName} $functionName(${parameters.join(', ')})',
    );
    buffer.writeln('{');
    builder._writeFunctionBody(buffer);
    buffer.writeln('  return OUT;');
    buffer.writeln('}');
  }
}

class FragmentEmissionStrategy extends StageEmissionStrategy {
  const FragmentEmissionStrategy();

  @override
  void writeStageFunction(
    MetalFragmentBuilder builder,
    List<String> parameters,
    StringBuffer buffer,
  ) {
    buffer.writeln(
      'fragment float4 ${builder.data.fragmentName}(${parameters.join(', ')})',
    );
    buffer.writeln('{');
    builder._writeFunctionBody(buffer);
    buffer.writeln('  return ${builder._translator.returnExpression};');
    buffer.writeln('}');
  }
}
