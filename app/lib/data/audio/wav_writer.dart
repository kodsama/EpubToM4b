/// Minimal WAV (PCM s16le) container writer.
///
/// Backends that receive raw PCM (ElevenLabs, Kokoro) use this to produce a
/// standard WAV so the rest of the pipeline treats every backend identically.
library;

import 'dart:typed_data';

/// Converts normalized float samples in `[-1, 1]` to little-endian signed
/// 16-bit PCM bytes. Used by model backends (e.g. Kokoro) that emit float audio.
Uint8List floatToPcm16(List<double> samples) {
  final out = Uint8List(samples.length * 2);
  final view = out.buffer.asByteData();
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    view.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
  }
  return out;
}

/// Builds the bytes of a mono 16-bit PCM WAV file wrapping [pcm] at
/// [sampleRate] Hz.
Uint8List buildWavPcm16Mono(Uint8List pcm, int sampleRate) {
  const channels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  const blockAlign = channels * bitsPerSample ~/ 8;
  final dataLen = pcm.length;
  final riffLen = 36 + dataLen;

  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) => b.add((Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little)));
  void u16(int v) => b.add((Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little)));

  str('RIFF');
  u32(riffLen);
  str('WAVE');
  str('fmt ');
  u32(16); // PCM fmt chunk size
  u16(1); // audio format = PCM
  u16(channels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  str('data');
  u32(dataLen);
  b.add(pcm);
  return b.toBytes();
}
