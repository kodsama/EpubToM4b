import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:audiobook_studio/data/tts/kokoro_voices.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a valid little-endian `<f4` C-order `.npy` payload.
Uint8List _npy(Float32List data, List<int> shape) {
  var header =
      "{'descr': '<f4', 'fortran_order': False, 'shape': (${shape.join(', ')}), }";
  // Pad the header so the total (magic+version+len+header+newline) is 64-aligned.
  final unpadded = 10 + header.length + 1;
  final pad = (64 - (unpadded % 64)) % 64;
  header = '$header${' ' * pad}\n';
  final hb = ascii.encode(header);

  final b = BytesBuilder();
  b.add([0x93]);
  b.add(ascii.encode('NUMPY'));
  b.add([1, 0]);
  final lenBytes = Uint8List(2)
    ..buffer.asByteData().setUint16(0, hb.length, Endian.little);
  b.add(lenBytes);
  b.add(hb);
  final db = Uint8List(data.length * 4);
  final dv = ByteData.sublistView(db);
  for (var i = 0; i < data.length; i++) {
    dv.setFloat32(i * 4, data[i], Endian.little);
  }
  b.add(db);
  return b.toBytes();
}

void main() {
  test('parses an npz of voices and selects the right style row', () {
    // Two rows of width 256: row r filled with value r.0.
    final data = Float32List(KokoroVoices.rows * KokoroVoices.dim);
    for (var r = 0; r < KokoroVoices.rows; r++) {
      for (var c = 0; c < KokoroVoices.dim; c++) {
        data[r * KokoroVoices.dim + c] = r.toDouble();
      }
    }
    final npy = _npy(data, [KokoroVoices.rows, 1, KokoroVoices.dim]);
    final archive = Archive()
      ..addFile(ArchiveFile('ff_siwis.npy', npy.length, npy));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    final voices = KokoroVoices.parse(bytes);
    expect(voices.has('ff_siwis'), isTrue);

    final row5 = voices.styleFor('ff_siwis', 5);
    expect(row5.length, KokoroVoices.dim);
    expect(row5.every((v) => v == 5.0), isTrue); // row index 5 holds value 5

    // Out-of-range token counts clamp to the last row.
    final clamped = voices.styleFor('ff_siwis', 99999);
    expect(clamped.every((v) => v == (KokoroVoices.rows - 1).toDouble()), isTrue);
  });

  test('throws for an unknown voice', () {
    final npy = _npy(Float32List(KokoroVoices.rows * KokoroVoices.dim),
        [KokoroVoices.rows, 1, KokoroVoices.dim]);
    final archive = Archive()..addFile(ArchiveFile('x.npy', npy.length, npy));
    final voices =
        KokoroVoices.parse(Uint8List.fromList(ZipEncoder().encode(archive)));
    expect(() => voices.styleFor('nope', 1), throwsArgumentError);
  });
}
