import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final Directory root = (args.isEmpty ? Directory.current : Directory(args.first)).absolute;
  final String sep = Platform.pathSeparator;
  final String rootPath = root.path.endsWith(sep) ? root.path : root.path + sep;
  final Directory legacyDir = Directory(rootPath + 'Shaders${sep}Legacy');
  if (!legacyDir.existsSync()) {
    stderr.writeln('Missing directory: ${legacyDir.path}');
    exit(1);
  }
  final List<Map<String, String>> legacyFiles = [];
  for (final FileSystemEntity entity in legacyDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final String lower = entity.path.toLowerCase();
    if (!(lower.endsWith('.cryps') || lower.endsWith('.crycg'))) continue;
    final String relative = entity.path.substring(legacyDir.path.length + 1).replaceAll(RegExp(r'[\\/]'), '/');
    legacyFiles.add({'path': relative});
  }
  final Directory d3d9Dir = Directory(rootPath + 'RenderDll${sep}XRenderD3D9');
  if (!d3d9Dir.existsSync()) {
    stderr.writeln('Missing directory: ${d3d9Dir.path}');
    exit(1);
  }
  final RegExp loadPattern = RegExp(r'EF_LoadShader\s*\(\s*"([^"]+)"');
  final RegExp forNamePattern = RegExp(r'mfForName\s*\(\s*"([^"]+)"');
  final Map<String, Set<String>> fileReferences = {};
  final Set<String> shaderNames = {};
  for (final FileSystemEntity entity in d3d9Dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.cpp') && !entity.path.endsWith('.h')) continue;
    final String content = entity.readAsStringSync(encoding: latin1);
    final List<Match> matches = [
      ...loadPattern.allMatches(content),
      ...forNamePattern.allMatches(content)
    ];
    if (matches.isEmpty) continue;
    final String relative = entity.path.substring(rootPath.length).replaceAll(RegExp(r'[\\/]'), '/');
    final Set<String> names = fileReferences.putIfAbsent(relative, () => <String>{});
    for (final Match match in matches) {
      final String name = match.group(1)?.trim() ?? '';
      if (name.isEmpty) continue;
      names.add(name);
      shaderNames.add(name);
    }
  }
  final Map<String, List<String>> families = {
    'terrain': [],
    'water': [],
    'post_process': [],
    'characters': [],
    'ui': [],
    'lighting': [],
    'misc': []
  };
  for (final String name in shaderNames) {
    final String lower = name.toLowerCase();
    String family;
    if (lower.contains('terrain')) {
      family = 'terrain';
    } else if (lower.contains('water') || lower.contains('ocean')) {
      family = 'water';
    } else if (lower.contains('screen') || lower.contains('distort') || lower.contains('post')) {
      family = 'post_process';
    } else if (lower.contains('character') || lower.contains('soldier') || lower.contains('human')) {
      family = 'characters';
    } else if (lower.contains('hud') || lower.contains('ui') || lower.contains('font')) {
      family = 'ui';
    } else if (lower.contains('light') || lower.contains('flare')) {
      family = 'lighting';
    } else {
      family = 'misc';
    }
    families[family]!.add(name);
  }
  for (final List<String> values in families.values) {
    values.sort();
  }
  legacyFiles.sort((a, b) => a['path']!.compareTo(b['path']!));
  final Map<String, dynamic> output = {
    'legacy': legacyFiles,
    'references': fileReferences.map((key, value) => MapEntry(key, value.toList()..sort())),
    'families': families
  };
  final File manifest = File(rootPath + 'tools${sep}shader_port${sep}output${sep}shader_inventory.json');
  manifest.parent.createSync(recursive: true);
  manifest.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
  stdout.writeln('Cataloged ${legacyFiles.length} legacy shader files and ${shaderNames.length} references');
}
