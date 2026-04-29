import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:minimap_icon_generator/minimap_icon_generator.dart';
import 'package:test/test.dart';

void main() {
  test('DDS header is well formed', () {
    final generator = MinimapIconGenerator(size: 4, radius: 1.5, borderWidth: 0.5);
    final icon = generator.buildIcon(
      const IconSpec(
        name: 'test',
        fillColor: DdsColor(10, 20, 30),
        borderColor: DdsColor(40, 50, 60),
      ),
    );

    final view = ByteData.view(icon.buffer);
    expect(String.fromCharCodes(icon.sublist(0, 4)), equals('DDS '));
    expect(view.getUint32(4, Endian.little), equals(124));
    expect(view.getUint32(4 + 72, Endian.little), equals(32));
    expect(view.getUint32(4 + 76, Endian.little), equals(0x41));
    expect(icon.length, equals(4 + 124 + (4 * 4 * 4)));
  });

  test('Generated pak contains all default icons', () {
    final generator = MinimapIconGenerator();
    final pak = generator.buildPak(MinimapIconGenerator.defaultIcons);
    final archive = ZipDecoder().decodeBytes(pak);

    final files = archive.files.map((file) => file.name).toSet();
    expect(
      files,
      containsAll(const [
        'Textures/gui/map_player.dds',
        'Textures/gui/map_vehicle.dds',
        'Textures/gui/map_building.dds',
        'Textures/gui/map_unknown.dds',
      ]),
    );
  });
}

