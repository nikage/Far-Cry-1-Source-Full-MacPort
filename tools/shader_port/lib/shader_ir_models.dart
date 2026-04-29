part of 'metal_generator.dart';

class UniformBinding {
  UniformBinding(this.type, this.name, this.semantic, {this.arraySize});
  final String type;
  final String name;
  final String semantic;
  final int? arraySize;
}

class TextureBinding {
  TextureBinding(this.type, this.name, this.slot, this.semantic);
  final String type;
  final String name;
  final int slot;
  final String semantic;
}

class ShaderIrData {
  ShaderIrData({
    required this.shaderName,
    required this.normalizedName,
    required this.fragmentName,
    required this.uniformStruct,
    required this.uniforms,
    required this.textures,
    required this.coreExpressions,
    required this.coreMacros,
    required this.coreFlow,
    required this.passStates,
    required this.positionScripts,
    required this.positionScriptBlocks,
    required this.outputFieldTypes,
    required this.maskReferences,
    required this.stage,
    required this.vertexAttributes,
    required this.vertexAttributeMetadata,
  });

  final String shaderName;
  final String normalizedName;
  final String fragmentName;
  final String uniformStruct;
  final List<UniformBinding> uniforms;
  final List<TextureBinding> textures;
  final List<Map<String, dynamic>> coreExpressions;
  final List<MacroDefinition> coreMacros;
  final List<Map<String, dynamic>> coreFlow;
  final List<Map<String, dynamic>> passStates;
  final List<String> positionScripts;
  final List<Map<String, String>> positionScriptBlocks;
  final Map<String, String> outputFieldTypes;
  final List<String> maskReferences;
  final String stage;
  final List<dynamic> vertexAttributes;
  final List<Map<String, dynamic>> vertexAttributeMetadata;
}

class MacroDefinition {
  MacroDefinition({
    required this.name,
    required this.value,
    required this.guards,
    required this.active,
    required this.raw,
  });

  final String name;
  final String value;
  final List<Map<String, dynamic>> guards;
  final bool? active;
  final String raw;
}

class ShaderIrParseResult {
  ShaderIrParseResult({
    required this.data,
    required this.directives,
    required this.vertexAttributes,
    required this.vertexAttributeMetadata,
  });

  final ShaderIrData data;
  final List<dynamic> directives;
  final List<dynamic> vertexAttributes;
  final List<Map<String, dynamic>> vertexAttributeMetadata;
}

