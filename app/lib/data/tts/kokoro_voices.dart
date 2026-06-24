/// Parses Kokoro's `voices-*.bin` (an npz of per-voice style tensors).
///
/// Each voice is a NumPy `<f4` array of shape `(510, 1, 256)`: one 256-d style
/// vector per possible token length. Kokoro selects the row matching the
/// (unpadded) token count at inference time.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Holds every voice's flattened style table, keyed by voice id.
class KokoroVoices {
  /// voice id -> flat float32 table of length 510 * 256.
  final Map<String, Float32List> _tables;

  /// Style vector width.
  static const int dim = 256;

  /// Max supported token rows.
  static const int rows = 510;

  KokoroVoices(this._tables);

  /// Voice ids available in this pack.
  Iterable<String> get voiceIds => _tables.keys;

  /// Whether [voiceId] exists.
  bool has(String voiceId) => _tables.containsKey(voiceId);

  /// The 256-d style vector for [voiceId] at [tokenCount] (clamped to range).
  Float32List styleFor(String voiceId, int tokenCount) {
    final table = _tables[voiceId];
    if (table == null) {
      throw ArgumentError('Unknown Kokoro voice: $voiceId');
    }
    final row = tokenCount.clamp(0, rows - 1);
    return Float32List.sublistView(table, row * dim, (row + 1) * dim);
  }

  /// Parses the npz [bytes] of a Kokoro voices file.
  factory KokoroVoices.parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final tables = <String, Float32List>{};
    for (final file in archive.files) {
      if (!file.name.endsWith('.npy')) continue;
      final id = file.name.substring(0, file.name.length - 4);
      tables[id] = _parseNpyFloat32(file.content as List<int>);
    }
    if (tables.isEmpty) {
      throw const FormatException('No voices found in Kokoro voices file');
    }
    return KokoroVoices(tables);
  }
}

/// Parses a little-endian `<f4` C-order `.npy` payload into a [Float32List].
Float32List _parseNpyFloat32(List<int> raw) {
  // Copy to a fresh zero-offset buffer: archive entry content can be a view
  // into a larger buffer, which would make `.buffer` reads off by the view's
  // offset. `ByteData.sublistView` then reads correctly.
  final bytes = Uint8List.fromList(raw);
  final bd = ByteData.sublistView(bytes);
  // Magic: \x93NUMPY, version (2 bytes), then header length.
  if (bytes.length < 10 || bytes[0] != 0x93) {
    throw const FormatException('Not a .npy file');
  }
  final major = bytes[6];
  final int headerLen;
  final int dataStart;
  if (major == 1) {
    headerLen = bd.getUint16(8, Endian.little);
    dataStart = 10 + headerLen;
  } else {
    headerLen = bd.getUint32(8, Endian.little);
    dataStart = 12 + headerLen;
  }
  final header =
      String.fromCharCodes(bytes.sublist(dataStart - headerLen, dataStart));
  if (!header.contains('<f4')) {
    throw FormatException('Unsupported npy dtype (expected <f4): $header');
  }
  // Interpret the remaining bytes as little-endian float32.
  final data = bytes.sublist(dataStart);
  final dataBd = ByteData.sublistView(data);
  final floats = Float32List(data.length ~/ 4);
  for (var i = 0; i < floats.length; i++) {
    floats[i] = dataBd.getFloat32(i * 4, Endian.little);
  }
  return floats;
}
