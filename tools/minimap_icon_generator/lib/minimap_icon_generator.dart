/// Core logic for generating Far Cry minimap icons as DDS textures.
///
/// The generator paints the icons procedurally so we do not have to commit
/// binary art assets. It intentionally matches the color palette of the
/// original PC release and produces lossless, uncompressed DDS files that can
/// be packed directly into `FCData/Textures_dev.pak`.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Simple RGBA color representation for DDS pixels.
class DdsColor {
  const DdsColor(this.r, this.g, this.b, [this.a = 255]);

  final int r;
  final int g;
  final int b;
  final int a;
}

/// Describes a minimap icon variant.
class IconSpec {
  const IconSpec({
    required this.name,
    required this.fillColor,
    required this.borderColor,
  });

  final String name;
  final DdsColor fillColor;
  final DdsColor borderColor;
}

/// Generates uncompressed RGBA DDS images for the HUD minimap icons.
///
/// Typical usage is through the CLI wrapper (`bin/generate_minimap_icons.dart`)
/// which writes both a CryPak archive and optionally the raw DDS files so they
/// can be inspected in-engine. The class is also usable directly from unit
/// tests so we can validate the DDS headers without spawning external tools.
class MinimapIconGenerator {
  MinimapIconGenerator({
    this.size = 64,
    this.radius = 22.0,
    this.borderWidth = 3.0,
  })  : assert(size > 0, 'Icon size must be positive.'),
        assert(radius > 0, 'Radius must be positive.'),
        assert(borderWidth >= 0, 'Border width must be non-negative.');

  /// Default icon specifications that mirror the original Far Cry assets.
  static const List<IconSpec> defaultIcons = [
    IconSpec(
      name: 'map_player',
      fillColor: DdsColor(64, 196, 255),
      borderColor: DdsColor(255, 255, 255),
    ),
    IconSpec(
      name: 'map_vehicle',
      fillColor: DdsColor(255, 200, 64),
      borderColor: DdsColor(255, 255, 255),
    ),
    IconSpec(
      name: 'map_building',
      fillColor: DdsColor(200, 200, 200),
      borderColor: DdsColor(255, 255, 255),
    ),
    IconSpec(
      name: 'map_unknown',
      fillColor: DdsColor(255, 80, 80),
      borderColor: DdsColor(255, 255, 255),
    ),
  ];

  final int size;
  final double radius;
  final double borderWidth;

  /// Builds a CryPak-compatible archive that contains all [specs] as DDS files.
  Uint8List buildPak(List<IconSpec> specs) {
    final archive = Archive();
    for (final spec in specs) {
      final bytes = buildIcon(spec);
      archive.addFile(
        ArchiveFile(
          'Textures/gui/${spec.name}.dds',
          bytes.length,
          bytes,
        ),
      );
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('Failed to encode minimap icon archive.');
    }
    return Uint8List.fromList(encoded);
  }

  /// Generates the DDS bytes for a single [spec].
  Uint8List buildIcon(IconSpec spec) {
    final pixels = _paintPixels(spec);
    return _DdsEncoder.encode(width: size, height: size, pixels: pixels);
  }

  Uint8List _paintPixels(IconSpec spec) {
    final center = (size / 2) - 0.5;
    final pixels = Uint8List(size * size * 4);
    var offset = 0;
    const transparent = DdsColor(0, 0, 0, 0);

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final dx = x - center;
        final dy = y - center;
        final distance = math.sqrt(dx * dx + dy * dy);

        DdsColor color;
        if (distance <= radius) {
          final isBorder = (radius - distance) < borderWidth;
          color = isBorder ? spec.borderColor : spec.fillColor;
        } else {
          color = transparent;
        }

        pixels[offset++] = color.b;
        pixels[offset++] = color.g;
        pixels[offset++] = color.r;
        pixels[offset++] = color.a;
      }
    }

    return pixels;
  }
}

/// Encodes uncompressed RGBA pixels into a DDS payload.
class _DdsEncoder {
  static const int _ddsHeaderSize = 124;
  static const int _magic = 0x20534444; // 'DDS '
  static const int _pixelFormatOffset = 72;

  static Uint8List encode({
    required int width,
    required int height,
    required Uint8List pixels,
  }) {
    final expectedLength = width * height * 4;
    if (pixels.length != expectedLength) {
      throw ArgumentError(
        'Pixel buffer has length ${pixels.length}, expected $expectedLength.',
      );
    }

    final output = Uint8List(4 + _ddsHeaderSize + pixels.length);
    final writer = ByteData.view(output.buffer);

    writer.setUint32(0, _magic, Endian.little);
    writer.setUint32(4, _ddsHeaderSize, Endian.little);
    writer.setUint32(
      8,
      _DdsFlags.caps |
          _DdsFlags.height |
          _DdsFlags.width |
          _DdsFlags.pitch |
          _DdsFlags.pixelFormat,
      Endian.little,
    );
    writer.setUint32(12, height, Endian.little);
    writer.setUint32(16, width, Endian.little);
    writer.setUint32(20, width * 4, Endian.little); // pitch
    writer.setUint32(24, 0, Endian.little); // depth
    writer.setUint32(28, 1, Endian.little); // mip levels

    // Pixel format block.
    writer.setUint32(4 + _pixelFormatOffset, 32, Endian.little);
    writer.setUint32(
      4 + _pixelFormatOffset + 4,
      _PixelFormatFlags.alphaPixels | _PixelFormatFlags.rgb,
      Endian.little,
    );
    writer.setUint32(4 + _pixelFormatOffset + 8, 0, Endian.little); // fourCC
    writer.setUint32(4 + _pixelFormatOffset + 12, 32, Endian.little);
    writer.setUint32(4 + _pixelFormatOffset + 16, 0x00FF0000, Endian.little);
    writer.setUint32(4 + _pixelFormatOffset + 20, 0x0000FF00, Endian.little);
    writer.setUint32(4 + _pixelFormatOffset + 24, 0x000000FF, Endian.little);
    writer.setUint32(4 + _pixelFormatOffset + 28, 0xFF000000, Endian.little);

    // Caps.
    writer.setUint32(4 + 104, _CapsFlags.texture, Endian.little);
    writer.setUint32(4 + 108, 0, Endian.little);
    writer.setUint32(4 + 112, 0, Endian.little);
    writer.setUint32(4 + 116, 0, Endian.little);

    output.setRange(4 + _ddsHeaderSize, output.length, pixels);
    return output;
  }
}

class _DdsFlags {
  static const int caps = 0x1;
  static const int height = 0x2;
  static const int width = 0x4;
  static const int pitch = 0x8;
  static const int pixelFormat = 0x1000;
}

class _PixelFormatFlags {
  static const int alphaPixels = 0x1;
  static const int rgb = 0x40;
}

class _CapsFlags {
  static const int texture = 0x1000;
}

