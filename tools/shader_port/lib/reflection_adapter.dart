class ReflectionInfo {
  ReflectionInfo({
    required this.uniforms,
    required this.textures,
    required this.vertexInputs,
    this.entryPoint,
  });

  final List<Map<String, dynamic>> uniforms;
  final List<Map<String, dynamic>> textures;
  final List<Map<String, dynamic>> vertexInputs;
  final String? entryPoint;
}

class ReflectionAdapter {
  ReflectionAdapter(this.raw);

  final Map<String, dynamic> raw;

  ReflectionInfo toInfo() {
    final List<Map<String, dynamic>> uniforms = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> textures = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> vertexInputs = <Map<String, dynamic>>[];
    final String? entryPoint = _stringValue(raw['EntryPoint']) ??
        _stringValue(raw['entryPoint']);
    uniforms.addAll(_extractUniforms());
    textures.addAll(_extractTextures());
    vertexInputs.addAll(_extractVertexInputs());
    return ReflectionInfo(
      uniforms: uniforms,
      textures: textures,
      vertexInputs: vertexInputs,
      entryPoint: entryPoint,
    );
  }

  Iterable<Map<String, dynamic>> _extractUniforms() sync* {
    final Object? list = raw['uniforms'];
    if (list is Iterable) {
      for (final Object? item in list) {
        if (item is Map<String, dynamic>) {
          yield item;
        }
      }
    }
    final Object? resources = raw['Resources'] ?? raw['resources'];
    if (resources is Iterable) {
      for (final Object? entry in resources) {
        if (entry is Map<String, dynamic>) {
          final String type =
              _stringValue(entry['type']) ?? _stringValue(entry['Type']) ?? '';
          if (type.toUpperCase() == 'CBV') {
            yield <String, dynamic>{
              'name': entry['name'] ?? entry['Name'] ?? '',
              'type': entry['elementType'] ?? entry['ElementType'] ?? '',
              'slot': entry['slot'] ?? entry['Slot'],
            };
          }
        }
      }
    }
  }

  Iterable<Map<String, dynamic>> _extractTextures() sync* {
    final Object? resources = raw['Resources'] ?? raw['resources'];
    if (resources is Iterable) {
      for (final Object? entry in resources) {
        if (entry is Map<String, dynamic>) {
          final String type =
              _stringValue(entry['type']) ?? _stringValue(entry['Type']) ?? '';
          if (type.toUpperCase() == 'SRV') {
            yield <String, dynamic>{
              'name': entry['name'] ?? entry['Name'] ?? '',
              'slot': entry['slot'] ?? entry['Slot'],
              'space': entry['space'] ?? entry['Space'],
            };
          }
        }
      }
    }
    final Object? textures = raw['textures'];
    if (textures is Iterable) {
      for (final Object? entry in textures) {
        if (entry is Map<String, dynamic>) {
          yield entry;
        }
      }
    }
  }

  Iterable<Map<String, dynamic>> _extractVertexInputs() sync* {
    final Object? inputs = raw['vertex_inputs'] ?? raw['inputs'];
    if (inputs is Iterable) {
      for (final Object? entry in inputs) {
        if (entry is Map<String, dynamic>) {
          yield entry;
        } else if (entry is String) {
          yield <String, dynamic>{'name': entry};
        }
      }
    }
  }

  String? _stringValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }
}
